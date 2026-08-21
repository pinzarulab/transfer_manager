import 'dart:async';

import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

import 'method_channel_platform.dart';

/// Bridges [DownloadRequest] tasks to an iOS background URLSession.
final class IosBackgroundDownloadEngine implements TransferEngine {
  IosBackgroundDownloadEngine({TransferManagerPlatform? platform})
    : platform = platform ?? TransferManagerIos();

  final TransferManagerPlatform platform;

  @override
  bool supports(TransferRequest request) => request is DownloadRequest;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    final request = context.record.request;
    if (request is! DownloadRequest) {
      throw TransferProtocolException(
        'iOS background download engine cannot execute ${request.runtimeType}',
      );
    }
    if (!(await platform.capabilities()).backgroundDownloads) {
      throw const TransferProtocolException(
        'iOS background downloads are unavailable',
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
      context.record.nativeTaskId = await platform.enqueueDownload(
        PlatformDownloadRequest(
          taskId: context.record.id,
          source: request.source,
          destination: PlatformTransferDestination(
            kind: request.destination.kind.name,
            value: request.destination.value,
          ),
          headers: request.headers,
          networkPolicy: (request.networkPolicy ?? NetworkPolicy.any).name,
          notificationTitle: request.notification?.title ?? 'Download complete',
          showNotification: request.notification != null,
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
          snapshot.error ?? 'iOS background download failed',
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
