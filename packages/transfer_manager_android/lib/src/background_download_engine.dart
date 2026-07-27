import 'dart:async';

import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

import 'method_channel_platform.dart';

/// Bridges core [DownloadRequest] tasks to Android WorkManager.
///
/// Add this before [HttpTransferEngine] in `TransferManager.engines` when
/// background execution is desired on Android.
final class AndroidBackgroundDownloadEngine implements TransferEngine {
  AndroidBackgroundDownloadEngine({TransferManagerPlatform? platform})
    : platform = platform ?? TransferManagerAndroid();

  final TransferManagerPlatform platform;

  @override
  bool supports(TransferRequest request) => request is DownloadRequest;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    final request = context.record.request;
    if (request is! DownloadRequest) {
      throw TransferProtocolException(
        'Android background engine cannot execute ${request.runtimeType}',
      );
    }
    final capabilities = await platform.capabilities();
    if (!capabilities.backgroundDownloads) {
      throw const TransferProtocolException(
        'Android background downloads are unavailable',
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
      final workId = await platform.enqueueDownload(
        PlatformDownloadRequest(
          taskId: context.record.id,
          source: request.source,
          destinationPath: request.destinationPath,
          headers: request.headers,
          networkPolicy: (request.networkPolicy ?? NetworkPolicy.any).name,
          notificationTitle: request.notification?.title ?? 'Downloading file',
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
          // WorkManager pause/resume is intentionally not advertised yet.
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
          snapshot.error ?? 'Android background download failed',
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
