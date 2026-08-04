import 'dart:async';

import 'package:test/test.dart';
import 'package:transfer_manager/transfer_manager.dart';

void main() {
  test('automatically retries a retryable failure', () async {
    final engine = _FakeEngine(failures: 1);
    final manager = TransferManager(
      engines: [engine],
      configuration: const TransferConfiguration(
        defaultRetryPolicy: RetryPolicy.exponential(
          maxAttempts: 2,
          initialDelay: Duration.zero,
          maximumDelay: Duration.zero,
          jitter: false,
        ),
      ),
    );
    addTearDown(manager.close);
    await manager.initialize();

    final task = await manager.enqueue(_request('retry'));
    await _waitFor(task, TransferState.completed);

    expect(engine.attempts, 2);
  });

  test('honors the global concurrency limit', () async {
    final engine = _FakeEngine(block: true);
    final manager = TransferManager(
      engines: [engine],
      configuration: const TransferConfiguration(maxConcurrentTasks: 1),
    );
    addTearDown(manager.close);
    await manager.initialize();

    final first = await manager.enqueue(_request('first'));
    final second = await manager.enqueue(_request('second'));
    await _waitUntil(() => engine.active == 1);

    expect(first.state, TransferState.running);
    expect(second.state, TransferState.queued);
    engine.releaseNext();
    await _waitFor(first, TransferState.completed);
    await _waitUntil(() => engine.active == 1);
    engine.releaseNext();
    await _waitFor(second, TransferState.completed);
    expect(engine.maximumActive, 1);
  });

  test('restores interrupted records to the queue', () async {
    final storage = InMemoryTransferStorage();
    await storage.save(
      TransferRecord(
        id: 'restored',
        request: _request('restored'),
        state: TransferState.running,
      ),
    );
    final manager = TransferManager(storage: storage, engines: [_FakeEngine()]);
    addTearDown(manager.close);
    await manager.initialize();

    final task = manager.task('restored')!;
    await _waitFor(task, TransferState.completed);
  });

  test('task open and reveal delegate completed artifact actions', () async {
    final actions = _FakeTaskActions();
    final manager = TransferManager(
      engines: [_FakeEngine()],
      taskActions: actions,
    );
    addTearDown(manager.close);
    await manager.initialize();
    final task = await manager.enqueue(_request('artifact'));
    await _waitFor(task, TransferState.completed);

    await task.open();
    await task.reveal();

    expect(actions.opened, [task.id]);
    expect(actions.revealed, [task.id]);
  });
}

DownloadRequest _request(String name) => DownloadRequest(
  source: Uri.parse('https://$name.example/file'),
  destination: TransferDestination.file('/unused/$name'),
);

Future<void> _waitFor(TransferTask task, TransferState state) async {
  if (task.state == state) return;
  await task.events
      .firstWhere((event) => event.state == state)
      .timeout(const Duration(seconds: 2));
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

final class _FakeEngine implements TransferEngine {
  _FakeEngine({this.failures = 0, this.block = false});

  int failures;
  final bool block;
  int attempts = 0;
  int active = 0;
  int maximumActive = 0;
  final List<Completer<void>> _releases = [];

  void releaseNext() => _releases.removeAt(0).complete();

  @override
  bool supports(TransferRequest request) => true;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    attempts++;
    active++;
    if (active > maximumActive) maximumActive = active;
    try {
      if (failures > 0) {
        failures--;
        throw const TransferNetworkException('temporary');
      }
      if (block) {
        final release = Completer<void>();
        _releases.add(release);
        await release.future;
      }
      await context.onProgress(10, 10);
    } finally {
      active--;
    }
  }
}

final class _FakeTaskActions implements TransferTaskActions {
  final List<String> opened = [];
  final List<String> revealed = [];

  @override
  Future<void> open(TransferRecord record) async => opened.add(record.id);

  @override
  Future<void> reveal(TransferRecord record) async => revealed.add(record.id);
}
