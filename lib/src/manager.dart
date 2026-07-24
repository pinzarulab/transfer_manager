import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'auth.dart';
import 'engine.dart';
import 'exceptions.dart';
import 'models.dart';
import 'storage.dart';

final class TransferManager {
  TransferManager({
    TransferStorage? storage,
    TransferAuthProvider? authProvider,
    this.configuration = const TransferConfiguration(),
    List<TransferEngine>? engines,
  }) : storage = storage ?? InMemoryTransferStorage(),
       authProvider = authProvider == null
           ? null
           : SingleFlightAuthProvider(authProvider),
       _engines = engines ?? [TusTransferEngine(), HttpTransferEngine()];

  final TransferStorage storage;
  final TransferAuthProvider? authProvider;
  final TransferConfiguration configuration;
  final List<TransferEngine> _engines;
  final Map<String, TransferRecord> _records = {};
  final Map<String, TransferTask> _tasks = {};
  final Map<String, TransferControl> _controls = {};
  final Map<String, int> _runningByHost = {};
  final Queue<String> _ready = Queue();
  final Random _random = Random();
  int _running = 0;
  int _runningUploads = 0;
  int _runningDownloads = 0;
  int _idCounter = 0;
  bool _initialized = false;
  bool _closed = false;

  Future<void> initialize() async {
    if (_initialized) return;
    await storage.initialize();
    final restored = await storage.loadAll();
    for (final record in restored) {
      if (_isRecoverable(record.state)) {
        record.state = TransferState.queued;
        record.updatedAt = DateTime.now().toUtc();
        await storage.save(record);
      }
      _records[record.id] = record;
      _tasks[record.id] = TransferTask._(this, record.id);
      if (record.state == TransferState.queued) _ready.add(record.id);
    }
    _initialized = true;
    _schedule();
  }

  Future<TransferTask> enqueue(TransferRequest request) async {
    _ensureUsable();
    final id =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${(_idCounter++).toRadixString(36)}';
    final record = TransferRecord(id: id, request: request);
    _records[id] = record;
    final task = TransferTask._(this, id);
    _tasks[id] = task;
    await _transition(record, TransferState.queued);
    _insertReady(id);
    _schedule();
    return task;
  }

  Future<List<TransferTask>> tasks({Set<TransferState>? states}) async {
    _ensureUsable();
    return _records.values
        .where((record) => states == null || states.contains(record.state))
        .map((record) => _tasks[record.id]!)
        .toList(growable: false);
  }

  TransferTask? task(String id) => _tasks[id];

  Future<TransferCapabilities> get platformCapabilities async =>
      const TransferCapabilities();

  Future<void> pause(String id) async {
    final record = _require(id);
    if (record.state == TransferState.queued ||
        record.state == TransferState.retryWaiting) {
      _ready.remove(id);
      await _transition(record, TransferState.paused);
    } else if (record.state == TransferState.running ||
        record.state == TransferState.preparing) {
      _controls[id]?.pause();
    }
  }

  Future<void> resume(String id) async {
    final record = _require(id);
    if (record.state != TransferState.paused) return;
    await _transition(record, TransferState.queued);
    _insertReady(id);
    _schedule();
  }

  Future<void> cancel(String id) async {
    final record = _require(id);
    if (_terminal(record.state)) return;
    _ready.remove(id);
    if (record.state == TransferState.running ||
        record.state == TransferState.preparing) {
      _controls[id]?.cancel();
    } else {
      _controls[id]?.cancel();
      await _transition(record, TransferState.cancelled);
    }
  }

  Future<void> retry(String id) async {
    final record = _require(id);
    if (record.state != TransferState.failed) return;
    record.retryAttempts = 0;
    record.error = null;
    await _transition(record, TransferState.queued);
    _insertReady(id);
    _schedule();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final control in _controls.values) {
      control.pause();
    }
    for (final engine in _engines) {
      if (engine is HttpTransferEngine) engine.close();
      if (engine is TusTransferEngine) engine.close();
    }
    await storage.close();
    for (final task in _tasks.values) {
      await task._events.close();
    }
  }

  void _schedule() {
    if (!_initialized || _closed) return;
    var madeProgress = true;
    while (_running < configuration.maxConcurrentTasks && madeProgress) {
      madeProgress = false;
      for (final id in List<String>.of(_ready)) {
        final record = _records[id]!;
        if (_canRun(record)) {
          _ready.remove(id);
          _start(record);
          madeProgress = true;
          break;
        }
      }
    }
  }

  bool _canRun(TransferRecord record) {
    final host = record.request.remoteUri.host;
    if ((_runningByHost[host] ?? 0) >=
        configuration.maxConcurrentTasksPerHost) {
      return false;
    }
    return switch (record.request.type) {
      TransferType.upload =>
        _runningUploads < configuration.maxConcurrentUploads,
      TransferType.download =>
        _runningDownloads < configuration.maxConcurrentDownloads,
    };
  }

  void _start(TransferRecord record) {
    _running++;
    final host = record.request.remoteUri.host;
    _runningByHost[host] = (_runningByHost[host] ?? 0) + 1;
    if (record.request.type == TransferType.upload) {
      _runningUploads++;
    } else {
      _runningDownloads++;
    }
    unawaited(
      _execute(record).whenComplete(() {
        _running--;
        _runningByHost.update(host, (value) => value - 1);
        if (_runningByHost[host] == 0) _runningByHost.remove(host);
        if (record.request.type == TransferType.upload) {
          _runningUploads--;
        } else {
          _runningDownloads--;
        }
        _controls.remove(record.id);
        _schedule();
      }),
    );
  }

  Future<void> _execute(TransferRecord record) async {
    final engine = _engines.cast<TransferEngine?>().firstWhere(
      (candidate) => candidate!.supports(record.request),
      orElse: () => null,
    );
    if (engine == null) {
      await _fail(
        record,
        TransferProtocolException(
          'No engine supports ${record.request.protocol}',
        ),
      );
      return;
    }
    final control = TransferControl();
    _controls[record.id] = control;
    var lastUpdate = DateTime.fromMillisecondsSinceEpoch(0);
    var lastBytes = record.bytesTransferred;
    var speed = 0.0;

    try {
      await _transition(record, TransferState.preparing);
      await _transition(record, TransferState.running);
      await engine.execute(
        TransferExecutionContext(
          record: record,
          control: control,
          authProvider: authProvider,
          onProgress: (bytes, total) async {
            final now = DateTime.now();
            final elapsed = now.difference(lastUpdate);
            if (lastUpdate.millisecondsSinceEpoch > 0 &&
                elapsed.inMicroseconds > 0) {
              final sample =
                  (bytes - lastBytes) * 1000000 / elapsed.inMicroseconds;
              speed = speed == 0 ? sample : speed * 0.8 + sample * 0.2;
            }
            record.bytesTransferred = bytes;
            record.totalBytes = total;
            record.updatedAt = now.toUtc();
            if (elapsed >= configuration.progressInterval || total == bytes) {
              lastUpdate = now;
              lastBytes = bytes;
              await storage.save(record);
              _emit(record, speed: speed);
            }
          },
        ),
      );
      await _transition(record, TransferState.verifying);
      await _transition(record, TransferState.completed);
    } on TransferCancelledException {
      await _transition(record, TransferState.cancelled);
    } catch (error) {
      if (isTransferPausedSignal(error)) {
        await _transition(record, TransferState.paused);
        return;
      }
      final normalized = _normalize(error);
      final policy =
          record.request.retryPolicy ?? configuration.defaultRetryPolicy;
      if (normalized.retryable &&
          record.retryAttempts + 1 < policy.maxAttempts) {
        record.retryAttempts++;
        record.error = normalized;
        await _transition(record, TransferState.retryWaiting);
        final delay = policy.delayForAttempt(
          record.retryAttempts,
          random: _random,
        );
        await Future<void>.delayed(delay);
        if (record.state == TransferState.retryWaiting && !_closed) {
          await _transition(record, TransferState.queued);
          _insertReady(record.id);
        }
      } else {
        await _fail(record, normalized);
      }
    }
  }

  TransferException _normalize(Object error) {
    if (error is TransferException) return error;
    return TransferNetworkException(error.toString(), cause: error);
  }

  Future<void> _fail(TransferRecord record, Object error) async {
    record.error = error;
    await _transition(record, TransferState.failed);
  }

  Future<void> _transition(TransferRecord record, TransferState next) async {
    if (!_validTransition(record.state, next)) {
      throw StateError('Invalid transition ${record.state} → $next');
    }
    record.state = next;
    record.updatedAt = DateTime.now().toUtc();
    await storage.save(record);
    _emit(record);
  }

  void _emit(TransferRecord record, {double speed = 0}) {
    final remaining = record.totalBytes == null || speed <= 0
        ? null
        : Duration(
            microseconds:
                ((record.totalBytes! - record.bytesTransferred) /
                        speed *
                        1000000)
                    .round(),
          );
    _tasks[record.id]?._events.add(
      TransferEvent(
        taskId: record.id,
        state: record.state,
        progress: TransferProgress(
          bytesTransferred: record.bytesTransferred,
          totalBytes: record.totalBytes,
          smoothedBytesPerSecond: speed,
          estimatedRemaining: remaining,
        ),
        error: record.error,
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  void _insertReady(String id) {
    final priority = _records[id]!.request.priority.index;
    final entries = _ready.toList();
    final position = entries.indexWhere(
      (other) => _records[other]!.request.priority.index < priority,
    );
    if (position < 0) {
      _ready.add(id);
    } else {
      entries.insert(position, id);
      _ready
        ..clear()
        ..addAll(entries);
    }
  }

  TransferRecord _require(String id) {
    _ensureUsable();
    final record = _records[id];
    if (record == null) throw ArgumentError.value(id, 'id', 'Unknown task');
    return record;
  }

  void _ensureUsable() {
    if (!_initialized) {
      throw StateError('Call initialize() before using TransferManager');
    }
    if (_closed) throw StateError('TransferManager is closed');
  }
}

final class TransferTask {
  TransferTask._(this._manager, this.id);

  final TransferManager _manager;
  final String id;
  final StreamController<TransferEvent> _events =
      StreamController<TransferEvent>.broadcast();

  Stream<TransferEvent> get events => _events.stream;
  TransferState get state => _manager._records[id]!.state;
  TransferProgress get progress {
    final record = _manager._records[id]!;
    return TransferProgress(
      bytesTransferred: record.bytesTransferred,
      totalBytes: record.totalBytes,
    );
  }

  Object? get error => _manager._records[id]!.error;
  Future<void> pause() => _manager.pause(id);
  Future<void> resume() => _manager.resume(id);
  Future<void> cancel() => _manager.cancel(id);
  Future<void> retry() => _manager.retry(id);
}

bool _isRecoverable(TransferState state) => switch (state) {
  TransferState.queued ||
  TransferState.preparing ||
  TransferState.running ||
  TransferState.retryWaiting ||
  TransferState.verifying => true,
  _ => false,
};

bool _terminal(TransferState state) =>
    state == TransferState.completed ||
    state == TransferState.failed ||
    state == TransferState.cancelled;

bool _validTransition(TransferState from, TransferState to) {
  if (from == to) return true;
  if (!_terminal(from) &&
      (to == TransferState.cancelled || to == TransferState.failed)) {
    return true;
  }
  return switch (from) {
    TransferState.created => to == TransferState.queued,
    TransferState.queued =>
      to == TransferState.preparing || to == TransferState.paused,
    TransferState.preparing =>
      to == TransferState.running || to == TransferState.paused,
    TransferState.running =>
      to == TransferState.paused ||
          to == TransferState.retryWaiting ||
          to == TransferState.verifying,
    TransferState.paused => to == TransferState.queued,
    TransferState.retryWaiting =>
      to == TransferState.queued || to == TransferState.paused,
    TransferState.verifying =>
      to == TransferState.completed || to == TransferState.retryWaiting,
    TransferState.failed => to == TransferState.queued,
    TransferState.completed || TransferState.cancelled => false,
  };
}
