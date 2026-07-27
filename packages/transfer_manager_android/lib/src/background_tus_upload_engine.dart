import 'dart:async';

import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

import 'method_channel_platform.dart';

/// Bridges resumable [TusUploadRequest] tasks to Android WorkManager.
///
/// The native worker persists the server-created upload URL and acknowledged
/// offset so retries and process restarts continue the same TUS resource.
final class AndroidBackgroundTusUploadEngine implements TransferEngine {
  AndroidBackgroundTusUploadEngine({TransferManagerPlatform? platform})
    : platform = platform ?? TransferManagerAndroid();

  final TransferManagerPlatform platform;

  @override
  bool supports(TransferRequest request) => request is TusUploadRequest;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    final request = context.record.request;
    if (request is! TusUploadRequest) {
      throw TransferProtocolException(
        'Android background TUS upload engine cannot execute '
        '${request.runtimeType}',
      );
    }
    final capabilities = await platform.capabilities();
    if (!capabilities.backgroundTusUploads) {
      throw const TransferProtocolException(
        'Android background TUS uploads are unavailable',
      );
    }

    var snapshot = await platform.task(context.record.id);
    if (context.record.nativeTaskId == null) snapshot = null;
    if (snapshot == null) {
      final workId = await platform.enqueueTusUpload(
        PlatformTusUploadRequest(
          taskId: context.record.id,
          sourcePath: request.sourcePath,
          endpoint: request.endpoint,
          chunkSize: request.chunkSize,
          metadata: request.metadata,
          headers: request.headers,
          networkPolicy: (request.networkPolicy ?? NetworkPolicy.any).name,
          notificationTitle: request.notification?.title ?? 'Uploading file',
          maxAttempts: (request.retryPolicy ?? const RetryPolicy.exponential())
              .maxAttempts,
        ),
      );
      context.record.nativeTaskId = workId;
      await context.onProgress(
        context.record.bytesTransferred,
        context.record.totalBytes,
      );
      snapshot = await platform.task(context.record.id);
    }

    if (snapshot != null && await _apply(snapshot, context)) return;

    final controller = StreamController<PlatformTaskSnapshot?>.broadcast();
    final subscription = platform.snapshots
        .where((event) => event.taskId == context.record.id)
        .listen(controller.add, onError: controller.addError);
    final timer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => controller.add(null),
    );
    try {
      await for (final event in controller.stream) {
        if (context.control.cancelRequested) {
          await platform.cancel(context.record.id);
          throw const TransferCancelledException();
        }
        if (context.control.pauseRequested) {
          await platform.cancel(context.record.id);
          throw const TransferPausedException();
        }
        if (event != null && await _apply(event, context)) return;
      }
    } finally {
      timer.cancel();
      await subscription.cancel();
      await controller.close();
    }
  }

  Future<bool> _apply(
    PlatformTaskSnapshot snapshot,
    TransferExecutionContext context,
  ) async {
    await context.onProgress(snapshot.bytesTransferred, snapshot.totalBytes);
    switch (snapshot.state) {
      case PlatformTaskState.succeeded:
        return true;
      case PlatformTaskState.failed:
        throw TransferNetworkException(
          snapshot.error ?? 'Android background TUS upload failed',
          retryable: false,
        );
      case PlatformTaskState.cancelled:
        throw const TransferCancelledException();
      case PlatformTaskState.enqueued:
      case PlatformTaskState.running:
      case PlatformTaskState.blocked:
      case PlatformTaskState.unknown:
        return false;
    }
  }
}
