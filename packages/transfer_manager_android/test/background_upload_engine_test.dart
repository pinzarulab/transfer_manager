import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  test('bridges a core multipart upload through WorkManager', () async {
    final platform = _UploadPlatform();
    final engine = AndroidBackgroundUploadEngine(platform: platform);
    final record = TransferRecord(
      id: 'upload-1',
      request: UploadRequest(
        sourcePath: '/files/video.mp4',
        destination: Uri.parse('https://example.com/upload'),
        fieldName: 'media',
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
        taskId: 'upload-1',
        state: PlatformTaskState.succeeded,
        bytesTransferred: 20,
        totalBytes: 20,
      ),
    );
    await execution;

    expect(record.nativeTaskId, 'upload-work-1');
    expect(platform.request!.fieldName, 'media');
    expect(platform.request!.networkPolicy, 'unmetered');
    expect(progress, contains(20));
  });

  test('consumes restored native success without uploading twice', () async {
    final platform = _UploadPlatform(
      existingSnapshot: const PlatformTaskSnapshot(
        taskId: 'restored-upload',
        state: PlatformTaskState.succeeded,
        bytesTransferred: 20,
        totalBytes: 20,
      ),
    );
    final record = TransferRecord(
      id: 'restored-upload',
      request: UploadRequest(
        sourcePath: '/files/video.mp4',
        destination: Uri.parse('https://example.com/upload'),
      ),
      state: TransferState.running,
      nativeTaskId: 'existing-work',
    );

    await AndroidBackgroundUploadEngine(platform: platform).execute(
      TransferExecutionContext(
        record: record,
        control: TransferControl(),
        onProgress: (_, _) {},
      ),
    );

    expect(platform.request, isNull);
    expect(record.nativeTaskId, 'existing-work');
  });
}

final class _UploadPlatform extends TransferManagerPlatform {
  _UploadPlatform({this.existingSnapshot}) {
    _snapshots = StreamController.broadcast(onListen: listening.complete);
  }

  late final StreamController<PlatformTaskSnapshot> _snapshots;
  final Completer<void> enqueued = Completer<void>();
  final Completer<void> listening = Completer<void>();
  final PlatformTaskSnapshot? existingSnapshot;
  PlatformUploadRequest? request;

  void emit(PlatformTaskSnapshot snapshot) => _snapshots.add(snapshot);

  @override
  Future<PlatformTransferCapabilities> capabilities() async =>
      const PlatformTransferCapabilities(
        backgroundDownloads: true,
        backgroundUploads: true,
        pauseResume: false,
        notifications: true,
        notificationCancellation: true,
      );

  @override
  Stream<PlatformTaskSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<String> enqueueUpload(PlatformUploadRequest request) async {
    this.request = request;
    enqueued.complete();
    return 'upload-work-1';
  }

  @override
  Future<String> enqueueDownload(PlatformDownloadRequest request) async =>
      throw UnimplementedError();

  @override
  Future<PlatformTaskSnapshot?> task(String taskId) async =>
      existingSnapshot ??
      (request == null
          ? null
          : PlatformTaskSnapshot(
              taskId: taskId,
              state: PlatformTaskState.enqueued,
              bytesTransferred: 0,
            ));

  @override
  Future<void> cancel(String taskId) async {}

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;
}
