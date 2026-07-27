import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  test('bridges a core TUS upload through WorkManager', () async {
    final platform = _TusPlatform();
    final engine = AndroidBackgroundTusUploadEngine(platform: platform);
    final record = TransferRecord(
      id: 'tus-1',
      request: TusUploadRequest(
        sourcePath: '/files/video.mp4',
        endpoint: Uri.parse('https://example.com/files'),
        chunkSize: 1024,
        metadata: const {'filename': 'video.mp4'},
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
        taskId: 'tus-1',
        state: PlatformTaskState.succeeded,
        bytesTransferred: 20,
        totalBytes: 20,
      ),
    );
    await execution;

    expect(record.nativeTaskId, 'tus-work-1');
    expect(platform.request!.chunkSize, 1024);
    expect(platform.request!.metadata, {'filename': 'video.mp4'});
    expect(platform.request!.networkPolicy, 'unmetered');
    expect(progress, contains(20));
  });

  test(
    'consumes restored native success without creating another upload',
    () async {
      final platform = _TusPlatform(
        existingSnapshot: const PlatformTaskSnapshot(
          taskId: 'restored-tus',
          state: PlatformTaskState.succeeded,
          bytesTransferred: 20,
          totalBytes: 20,
        ),
      );
      final record = TransferRecord(
        id: 'restored-tus',
        request: TusUploadRequest(
          sourcePath: '/files/video.mp4',
          endpoint: Uri.parse('https://example.com/files'),
        ),
        state: TransferState.running,
        nativeTaskId: 'existing-work',
      );

      await AndroidBackgroundTusUploadEngine(platform: platform).execute(
        TransferExecutionContext(
          record: record,
          control: TransferControl(),
          onProgress: (_, _) {},
        ),
      );

      expect(platform.request, isNull);
      expect(record.nativeTaskId, 'existing-work');
    },
  );
}

final class _TusPlatform extends TransferManagerPlatform {
  _TusPlatform({this.existingSnapshot}) {
    _snapshots = StreamController.broadcast(onListen: listening.complete);
  }

  late final StreamController<PlatformTaskSnapshot> _snapshots;
  final Completer<void> enqueued = Completer<void>();
  final Completer<void> listening = Completer<void>();
  final PlatformTaskSnapshot? existingSnapshot;
  PlatformTusUploadRequest? request;

  void emit(PlatformTaskSnapshot snapshot) => _snapshots.add(snapshot);

  @override
  Future<PlatformTransferCapabilities> capabilities() async =>
      const PlatformTransferCapabilities(
        backgroundDownloads: true,
        backgroundUploads: true,
        backgroundTusUploads: true,
        pauseResume: false,
        notifications: true,
        notificationCancellation: true,
      );

  @override
  Stream<PlatformTaskSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<String> enqueueTusUpload(PlatformTusUploadRequest request) async {
    this.request = request;
    enqueued.complete();
    return 'tus-work-1';
  }

  @override
  Future<String> enqueueUpload(PlatformUploadRequest request) async =>
      throw UnimplementedError();

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
