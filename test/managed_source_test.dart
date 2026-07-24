import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_manager/transfer_manager.dart';

void main() {
  test('stages an upload atomically and cleans it after completion', () async {
    final directory = await Directory.systemTemp.createTemp('managed-source-');
    addTearDown(() => directory.delete(recursive: true));
    final original = File('${directory.path}/picker/video.txt');
    await original.parent.create(recursive: true);
    await original.writeAsString('durable upload');
    final managedRoot = '${directory.path}/managed';
    final engine = _SourceEngine();
    final manager = TransferManager(
      engines: [engine],
      configuration: TransferConfiguration(managedStoragePath: managedRoot),
    );
    addTearDown(manager.close);
    await manager.initialize();

    final task = await manager.enqueue(
      UploadRequest(
        sourcePath: original.path,
        destination: Uri.parse('https://example.com/upload'),
        sourcePolicy: UploadSourcePolicy.copyToManagedStorage,
      ),
    );
    await _waitFor(task, TransferState.completed);

    expect(engine.content, 'durable upload');
    expect(engine.sourcePath, isNot(original.path));
    expect(await original.exists(), isTrue);
    expect(await File(engine.sourcePath!).exists(), isFalse);
  });

  test('retains a managed source after failure for manual retry', () async {
    final directory = await Directory.systemTemp.createTemp('managed-failure-');
    addTearDown(() => directory.delete(recursive: true));
    final original = File('${directory.path}/source.bin');
    await original.writeAsString('retry me');
    final engine = _SourceEngine(fail: true);
    final manager = TransferManager(
      engines: [engine],
      configuration: TransferConfiguration(
        managedStoragePath: '${directory.path}/managed',
      ),
    );
    addTearDown(manager.close);
    await manager.initialize();

    final task = await manager.enqueue(
      TusUploadRequest(
        sourcePath: original.path,
        endpoint: Uri.parse('https://example.com/files'),
        sourcePolicy: UploadSourcePolicy.copyToManagedStorage,
      ),
    );
    await _waitFor(task, TransferState.failed);

    expect(await File(engine.sourcePath!).exists(), isTrue);
  });

  test('restored task uses and then cleans its managed source', () async {
    final directory = await Directory.systemTemp.createTemp('managed-restore-');
    addTearDown(() => directory.delete(recursive: true));
    const id = 'restored-managed';
    final managedRoot = '${directory.path}/managed';
    final staged = File('$managedRoot/$id/source.bin');
    await staged.parent.create(recursive: true);
    await staged.writeAsString('survived restart');
    final storage = InMemoryTransferStorage();
    await storage.save(
      TransferRecord(
        id: id,
        request: UploadRequest(
          sourcePath: staged.path,
          destination: Uri.parse('https://example.com/upload'),
          sourcePolicy: UploadSourcePolicy.copyToManagedStorage,
        ),
        state: TransferState.running,
        protocolMetadata: {'managedSourcePath': staged.path},
      ),
    );
    final engine = _SourceEngine();
    final manager = TransferManager(
      storage: storage,
      engines: [engine],
      configuration: TransferConfiguration(managedStoragePath: managedRoot),
    );
    addTearDown(manager.close);

    await manager.initialize();
    await _waitFor(manager.task(id)!, TransferState.completed);

    expect(engine.content, 'survived restart');
    expect(await staged.exists(), isFalse);
  });

  test('cleans a managed source after cancellation', () async {
    final directory = await Directory.systemTemp.createTemp('managed-cancel-');
    addTearDown(() => directory.delete(recursive: true));
    final original = File('${directory.path}/source.bin');
    await original.writeAsString('cancel me');
    final engine = _CancellableSourceEngine();
    final manager = TransferManager(
      engines: [engine],
      configuration: TransferConfiguration(
        managedStoragePath: '${directory.path}/managed',
      ),
    );
    addTearDown(manager.close);
    await manager.initialize();

    final task = await manager.enqueue(
      UploadRequest(
        sourcePath: original.path,
        destination: Uri.parse('https://example.com/upload'),
        sourcePolicy: UploadSourcePolicy.copyToManagedStorage,
      ),
    );
    await engine.started.future;
    expect(await File(engine.sourcePath!).exists(), isTrue);

    await task.cancel();
    await _waitFor(task, TransferState.cancelled);

    expect(await File(engine.sourcePath!).exists(), isFalse);
    expect(await original.exists(), isTrue);
  });

  test('requires a managed storage path before copying', () async {
    final directory = await Directory.systemTemp.createTemp('managed-config-');
    addTearDown(() => directory.delete(recursive: true));
    final original = File('${directory.path}/source.bin');
    await original.writeAsString('data');
    final manager = TransferManager(engines: [_SourceEngine()]);
    addTearDown(manager.close);
    await manager.initialize();

    expect(
      () => manager.enqueue(
        UploadRequest(
          sourcePath: original.path,
          destination: Uri.parse('https://example.com/upload'),
          sourcePolicy: UploadSourcePolicy.copyToManagedStorage,
        ),
      ),
      throwsStateError,
    );
  });
}

Future<void> _waitFor(TransferTask task, TransferState state) async {
  if (task.state == state) return;
  await task.events
      .firstWhere((event) => event.state == state)
      .timeout(const Duration(seconds: 2));
}

final class _SourceEngine implements TransferEngine {
  _SourceEngine({this.fail = false});

  final bool fail;
  String? sourcePath;
  String? content;

  @override
  bool supports(TransferRequest request) => request.type == TransferType.upload;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    sourcePath = switch (context.record.request) {
      UploadRequest request => request.sourcePath,
      TusUploadRequest request => request.sourcePath,
      DownloadRequest() => throw StateError('Expected upload'),
    };
    content = await File(sourcePath!).readAsString();
    if (fail) {
      throw const TransferProtocolException('permanent failure');
    }
    await context.onProgress(content!.length, content!.length);
  }
}

final class _CancellableSourceEngine implements TransferEngine {
  final Completer<void> started = Completer<void>();
  String? sourcePath;

  @override
  bool supports(TransferRequest request) => request.type == TransferType.upload;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    sourcePath = (context.record.request as UploadRequest).sourcePath;
    started.complete();
    while (!context.control.cancelRequested) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    throw const TransferCancelledException();
  }
}
