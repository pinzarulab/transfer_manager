import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  test('bridges a core download through the native platform', () async {
    final platform = _FakePlatform();
    final engine = AndroidBackgroundDownloadEngine(platform: platform);
    final record = TransferRecord(
      id: 'task-1',
      request: DownloadRequest(
        source: Uri.parse('https://example.com/file'),
        destinationPath: '/downloads/file',
        networkPolicy: NetworkPolicy.unmetered,
      ),
      state: TransferState.running,
    );
    final progress = <int>[];

    final execution = engine.execute(
      TransferExecutionContext(
        record: record,
        control: TransferControl(),
        onProgress: (bytes, total) => progress.add(bytes),
      ),
    );
    await platform.enqueued.future;
    await platform.listening.future;
    platform.emit(
      const PlatformTaskSnapshot(
        taskId: 'task-1',
        state: PlatformTaskState.succeeded,
        bytesTransferred: 10,
        totalBytes: 10,
      ),
    );
    await execution;

    expect(record.nativeTaskId, 'work-1');
    expect(platform.request!.networkPolicy, 'unmetered');
    expect(progress, contains(10));
  });
}

final class _FakePlatform extends TransferManagerPlatform {
  _FakePlatform() {
    _snapshots = StreamController.broadcast(onListen: listening.complete);
  }

  late final StreamController<PlatformTaskSnapshot> _snapshots;
  final Completer<void> enqueued = Completer<void>();
  final Completer<void> listening = Completer<void>();
  PlatformDownloadRequest? request;

  void emit(PlatformTaskSnapshot snapshot) => _snapshots.add(snapshot);

  @override
  Future<PlatformTransferCapabilities> capabilities() async =>
      const PlatformTransferCapabilities(
        backgroundDownloads: true,
        backgroundUploads: false,
        pauseResume: false,
        notifications: true,
        notificationCancellation: true,
      );

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;

  @override
  Stream<PlatformTaskSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<String> enqueueDownload(PlatformDownloadRequest request) async {
    this.request = request;
    enqueued.complete();
    return 'work-1';
  }

  @override
  Future<String> enqueueUpload(PlatformUploadRequest request) async =>
      throw UnimplementedError();

  @override
  Future<String> enqueueTusUpload(PlatformTusUploadRequest request) async =>
      throw UnimplementedError();

  @override
  Future<PlatformTaskSnapshot?> task(String taskId) async => request == null
      ? null
      : PlatformTaskSnapshot(
          taskId: taskId,
          state: PlatformTaskState.enqueued,
          bytesTransferred: 0,
        );

  @override
  Future<void> cancel(String taskId) async {}
}
