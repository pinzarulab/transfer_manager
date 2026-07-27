import 'dart:async';

import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

import 'method_channel_platform.dart';

/// Bridges multipart [UploadRequest] tasks to an iOS background URLSession.
final class IosBackgroundUploadEngine implements TransferEngine {
  IosBackgroundUploadEngine({TransferManagerPlatform? platform})
    : platform = platform ?? TransferManagerIos();

  final TransferManagerPlatform platform;

  @override
  bool supports(TransferRequest request) => request is UploadRequest;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    final request = context.record.request;
    if (request is! UploadRequest) {
      throw TransferProtocolException(
        'iOS background upload engine cannot execute ${request.runtimeType}',
      );
    }
    if (!(await platform.capabilities()).backgroundUploads) {
      throw const TransferProtocolException(
        'iOS background uploads are unavailable',
      );
    }

    var snapshot = await platform.task(context.record.id);
    if (context.record.nativeTaskId == null) snapshot = null;
    if (context.record.nativeTaskId != null &&
        snapshot != null &&
        !_terminal(snapshot.state)) {
      await platform.resume(context.record.id);
    }
    if (snapshot == null) {
      context.record.nativeTaskId = await platform.enqueueUpload(
        PlatformUploadRequest(
          taskId: context.record.id,
          sourcePath: request.sourcePath,
          destination: request.destination,
          method: request.method,
          fieldName: request.fieldName,
          headers: request.headers,
          networkPolicy: (request.networkPolicy ?? NetworkPolicy.any).name,
          notificationTitle: request.notification?.title ?? 'Upload complete',
          maxAttempts: (request.retryPolicy ?? const RetryPolicy.exponential())
              .maxAttempts,
        ),
      );
      await context.onProgress(
        context.record.bytesTransferred,
        context.record.totalBytes,
      );
      snapshot = await platform.task(context.record.id);
    }
    if (snapshot != null && await _apply(snapshot, context)) return;
    await _observe(context);
  }

  Future<void> _observe(TransferExecutionContext context) async {
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
          snapshot.error ?? 'iOS background upload failed',
          retryable: false,
        );
      case PlatformTaskState.cancelled:
        throw const TransferCancelledException();
      case PlatformTaskState.paused:
      case PlatformTaskState.enqueued:
      case PlatformTaskState.running:
      case PlatformTaskState.blocked:
      case PlatformTaskState.unknown:
        return false;
    }
  }

  bool _terminal(PlatformTaskState state) =>
      state == PlatformTaskState.succeeded ||
      state == PlatformTaskState.failed ||
      state == PlatformTaskState.cancelled;
}
