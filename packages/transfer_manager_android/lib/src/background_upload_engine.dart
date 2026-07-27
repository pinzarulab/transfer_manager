import 'dart:async';

import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

import 'method_channel_platform.dart';

/// Bridges simple multipart [UploadRequest] tasks to Android WorkManager.
///
/// A retry restarts the multipart request. Use the foreground TUS engine when
/// chunk-level resumability is required.
final class AndroidBackgroundUploadEngine implements TransferEngine {
  AndroidBackgroundUploadEngine({TransferManagerPlatform? platform})
    : platform = platform ?? TransferManagerAndroid();

  final TransferManagerPlatform platform;

  @override
  bool supports(TransferRequest request) => request is UploadRequest;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    final request = context.record.request;
    if (request is! UploadRequest) {
      throw TransferProtocolException(
        'Android background upload engine cannot execute '
        '${request.runtimeType}',
      );
    }
    final capabilities = await platform.capabilities();
    if (!capabilities.backgroundUploads) {
      throw const TransferProtocolException(
        'Android background uploads are unavailable',
      );
    }

    var snapshot = await platform.task(context.record.id);
    if (context.record.nativeTaskId == null) snapshot = null;
    if (context.record.nativeTaskId != null &&
        snapshot != null &&
        snapshot.state != PlatformTaskState.succeeded &&
        snapshot.state != PlatformTaskState.failed &&
        snapshot.state != PlatformTaskState.cancelled) {
      await platform.resume(context.record.id);
    }
    if (snapshot == null) {
      final workId = await platform.enqueueUpload(
        PlatformUploadRequest(
          taskId: context.record.id,
          sourcePath: request.sourcePath,
          destination: request.destination,
          method: request.method,
          fieldName: request.fieldName,
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
          await platform.pause(context.record.id);
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
          snapshot.error ?? 'Android background upload failed',
          retryable: false,
        );
      case PlatformTaskState.cancelled:
        throw const TransferCancelledException();
      case PlatformTaskState.paused:
        return false;
      case PlatformTaskState.enqueued:
      case PlatformTaskState.running:
      case PlatformTaskState.blocked:
      case PlatformTaskState.unknown:
        return false;
    }
  }
}
