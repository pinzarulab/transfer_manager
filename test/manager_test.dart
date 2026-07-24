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
    await engine.started.first;

    expect(first.state, TransferState.running);
    expect(second.state, TransferState.queued);
    engine.releaseNext();
    await _waitFor(first, TransferState.completed);
    await engine.started.first;
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
}

DownloadRequest _request(String name) => DownloadRequest(
  source: Uri.parse('https://$name.example/file'),
  destinationPath: '/unused/$name',
);

Future<void> _waitFor(TransferTask task, TransferState state) async {
  if (task.state == state) return;
  await task.events
      .firstWhere((event) => event.state == state)
      .timeout(const Duration(seconds: 2));
}

final class _FakeEngine implements TransferEngine {
  _FakeEngine({this.failures = 0, this.block = false});

  int failures;
  final bool block;
  int attempts = 0;
  int active = 0;
  int maximumActive = 0;
  final StreamController<void> _started = StreamController.broadcast();
  final List<Completer<void>> _releases = [];

  Stream<void> get started => _started.stream;

  void releaseNext() => _releases.removeAt(0).complete();

  @override
  bool supports(TransferRequest request) => true;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    attempts++;
    active++;
    if (active > maximumActive) maximumActive = active;
    _started.add(null);
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
