import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'models.dart';

abstract class TransferManagerPlatform extends PlatformInterface {
  TransferManagerPlatform() : super(token: _token);

  static final Object _token = Object();
  static TransferManagerPlatform _instance = _UnsupportedPlatform();

  static TransferManagerPlatform get instance => _instance;

  static set instance(TransferManagerPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<PlatformTransferCapabilities> capabilities();

  Future<bool> notificationsEnabled();

  Future<bool> requestNotificationPermission();

  Stream<PlatformTaskSnapshot> get snapshots;

  Future<String> enqueueDownload(PlatformDownloadRequest request);

  Future<String> enqueueUpload(PlatformUploadRequest request);

  Future<String> enqueueTusUpload(PlatformTusUploadRequest request);

  Future<PlatformTaskSnapshot?> task(String taskId);

  Future<void> cancel(String taskId);
}

final class _UnsupportedPlatform extends TransferManagerPlatform {
  Never _unsupported() => throw UnsupportedError(
    'No native transfer_manager implementation is registered',
  );

  @override
  Future<PlatformTransferCapabilities> capabilities() async => _unsupported();

  @override
  Future<bool> notificationsEnabled() async => _unsupported();

  @override
  Future<bool> requestNotificationPermission() async => _unsupported();

  @override
  Stream<PlatformTaskSnapshot> get snapshots => const Stream.empty();

  @override
  Future<String> enqueueDownload(PlatformDownloadRequest request) async =>
      _unsupported();

  @override
  Future<String> enqueueUpload(PlatformUploadRequest request) async =>
      _unsupported();

  @override
  Future<String> enqueueTusUpload(PlatformTusUploadRequest request) async =>
      _unsupported();

  @override
  Future<PlatformTaskSnapshot?> task(String taskId) async => _unsupported();

  @override
  Future<void> cancel(String taskId) async => _unsupported();
}
