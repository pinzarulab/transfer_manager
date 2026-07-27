import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_ios/transfer_manager_ios.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  test('bridges a download through background URLSession', () async {
    final platform = _IosPlatform();
    final record = TransferRecord(
      id: 'download',
      request: DownloadRequest(
        source: Uri.parse('https://example.com/file'),
        destinationPath: '/files/file',
      ),
      state: TransferState.running,
    );

    final execution = IosBackgroundDownloadEngine(platform: platform).execute(
      TransferExecutionContext(
        record: record,
        control: TransferControl(),
        onProgress: (_, _) {},
      ),
    );
    await platform.enqueued.future;
    await platform.listening.future;
    platform.emit(
      const PlatformTaskSnapshot(
        taskId: 'download',
        state: PlatformTaskState.succeeded,
        bytesTransferred: 10,
        totalBytes: 10,
      ),
    );
    await execution;

    expect(record.nativeTaskId, 'ios-download');
    expect(platform.download?.destinationPath, '/files/file');
  });

  test('bridges a multipart upload through background URLSession', () async {
    final platform = _IosPlatform();
    final record = TransferRecord(
      id: 'upload',
      request: UploadRequest(
        sourcePath: '/files/video.mp4',
        destination: Uri.parse('https://example.com/upload'),
      ),
      state: TransferState.running,
    );

    final execution = IosBackgroundUploadEngine(platform: platform).execute(
      TransferExecutionContext(
        record: record,
        control: TransferControl(),
        onProgress: (_, _) {},
      ),
    );
    await platform.enqueued.future;
    await platform.listening.future;
    platform.emit(
      const PlatformTaskSnapshot(
        taskId: 'upload',
        state: PlatformTaskState.succeeded,
        bytesTransferred: 20,
        totalBytes: 20,
      ),
    );
    await execution;

    expect(record.nativeTaskId, 'ios-upload');
    expect(platform.upload?.sourcePath, '/files/video.mp4');
  });

  test('consumes restored completion without creating a duplicate', () async {
    final platform = _IosPlatform(
      restored: const PlatformTaskSnapshot(
        taskId: 'restored',
        state: PlatformTaskState.succeeded,
        bytesTransferred: 10,
        totalBytes: 10,
      ),
    );
    final record = TransferRecord(
      id: 'restored',
      request: DownloadRequest(
        source: Uri.parse('https://example.com/file'),
        destinationPath: '/files/file',
      ),
      state: TransferState.running,
      nativeTaskId: '42',
    );

    await IosBackgroundDownloadEngine(platform: platform).execute(
      TransferExecutionContext(
        record: record,
        control: TransferControl(),
        onProgress: (_, _) {},
      ),
    );

    expect(platform.download, isNull);
  });
}

final class _IosPlatform extends TransferManagerPlatform {
  _IosPlatform({this.restored}) {
    controller = StreamController.broadcast(onListen: listening.complete);
  }

  late final StreamController<PlatformTaskSnapshot> controller;
  final Completer<void> enqueued = Completer<void>();
  final Completer<void> listening = Completer<void>();
  final PlatformTaskSnapshot? restored;
  PlatformDownloadRequest? download;
  PlatformUploadRequest? upload;

  void emit(PlatformTaskSnapshot snapshot) => controller.add(snapshot);

  @override
  Future<PlatformTransferCapabilities> capabilities() async =>
      const PlatformTransferCapabilities(
        backgroundDownloads: true,
        backgroundUploads: true,
        pauseResume: true,
        notifications: true,
        notificationCancellation: false,
      );

  @override
  Stream<PlatformTaskSnapshot> get snapshots => controller.stream;

  @override
  Future<String> enqueueDownload(PlatformDownloadRequest request) async {
    download = request;
    enqueued.complete();
    return 'ios-download';
  }

  @override
  Future<String> enqueueUpload(PlatformUploadRequest request) async {
    upload = request;
    enqueued.complete();
    return 'ios-upload';
  }

  @override
  Future<String> enqueueTusUpload(PlatformTusUploadRequest request) async =>
      throw UnimplementedError();

  @override
  Future<PlatformTaskSnapshot?> task(String taskId) async =>
      restored ??
      (download == null && upload == null
          ? null
          : PlatformTaskSnapshot(
              taskId: taskId,
              state: PlatformTaskState.enqueued,
              bytesTransferred: 0,
            ));

  @override
  Future<void> cancel(String taskId) async {}

  @override
  Future<void> pause(String taskId) async {}

  @override
  Future<void> resume(String taskId) async {}

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Future<bool> requestNotificationPermission() async => true;
}
