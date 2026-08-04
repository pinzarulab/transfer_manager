import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

final class TransferManagerAndroid extends TransferManagerPlatform {
  TransferManagerAndroid({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : methodChannel =
           methodChannel ??
           const MethodChannel('pinzarulab.com/transfer_manager/methods'),
       eventChannel =
           eventChannel ??
           const EventChannel('pinzarulab.com/transfer_manager/events');

  @visibleForTesting
  final MethodChannel methodChannel;

  @visibleForTesting
  final EventChannel eventChannel;

  Stream<PlatformTaskSnapshot>? _snapshots;
  final StreamController<PlatformNotificationTap> _notificationTaps =
      StreamController<PlatformNotificationTap>.broadcast();
  bool _methodHandlerInstalled = false;

  @override
  Stream<PlatformNotificationTap> get notificationTaps {
    _ensureMethodHandler();
    return _notificationTaps.stream;
  }

  @override
  Future<PlatformNotificationTap?> takeInitialNotificationTap() async {
    _ensureMethodHandler();
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'takeInitialNotificationTap',
    );
    return value == null ? null : PlatformNotificationTap.fromMap(value);
  }

  Future<Object?> _handleNativeMethod(MethodCall call) async {
    if (call.method != 'notificationTapped') {
      throw MissingPluginException('Unknown native method ${call.method}');
    }
    _notificationTaps.add(
      PlatformNotificationTap.fromMap(call.arguments! as Map<Object?, Object?>),
    );
    return null;
  }

  void _ensureMethodHandler() {
    if (_methodHandlerInstalled) return;
    methodChannel.setMethodCallHandler(_handleNativeMethod);
    _methodHandlerInstalled = true;
  }

  static void registerWith() {
    TransferManagerPlatform.instance = TransferManagerAndroid();
  }

  @override
  Future<PlatformTransferCapabilities> capabilities() async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'capabilities',
    );
    return PlatformTransferCapabilities.fromMap(result ?? const {});
  }

  @override
  Future<bool> notificationsEnabled() async =>
      await methodChannel.invokeMethod<bool>('notificationsEnabled') ?? false;

  @override
  Future<bool> requestNotificationPermission() async =>
      await methodChannel.invokeMethod<bool>('requestNotificationPermission') ??
      false;

  @override
  Stream<PlatformTaskSnapshot> get snapshots =>
      _snapshots ??= eventChannel.receiveBroadcastStream().map((event) {
        return PlatformTaskSnapshot.fromMap(event! as Map<Object?, Object?>);
      }).asBroadcastStream();

  @override
  Future<String> enqueueDownload(PlatformDownloadRequest request) async {
    final workId = await methodChannel.invokeMethod<String>(
      'enqueueDownload',
      request.toMap(),
    );
    if (workId == null) {
      throw PlatformException(
        code: 'missing_work_id',
        message: 'Android did not return a WorkManager identifier',
      );
    }
    return workId;
  }

  @override
  Future<String> enqueueUpload(PlatformUploadRequest request) async {
    final workId = await methodChannel.invokeMethod<String>(
      'enqueueUpload',
      request.toMap(),
    );
    if (workId == null) {
      throw PlatformException(
        code: 'missing_work_id',
        message: 'Android did not return a WorkManager identifier',
      );
    }
    return workId;
  }

  @override
  Future<String> enqueueTusUpload(PlatformTusUploadRequest request) async {
    final workId = await methodChannel.invokeMethod<String>(
      'enqueueTusUpload',
      request.toMap(),
    );
    if (workId == null) {
      throw PlatformException(
        code: 'missing_work_id',
        message: 'Android did not return a WorkManager identifier',
      );
    }
    return workId;
  }

  @override
  Future<PlatformTaskSnapshot?> task(String taskId) async {
    final result = await methodChannel.invokeMapMethod<Object?, Object?>(
      'task',
      {'taskId': taskId},
    );
    return result == null ? null : PlatformTaskSnapshot.fromMap(result);
  }

  @override
  Future<void> cancel(String taskId) =>
      methodChannel.invokeMethod<void>('cancel', {'taskId': taskId});

  @override
  Future<void> pause(String taskId) =>
      methodChannel.invokeMethod<void>('pause', {'taskId': taskId});

  @override
  Future<void> resume(String taskId) =>
      methodChannel.invokeMethod<void>('resume', {'taskId': taskId});

  @override
  Future<void> open(String taskId, PlatformTransferDestination destination) =>
      methodChannel.invokeMethod<void>('open', {
        'taskId': taskId,
        'destination': destination.toMap(),
      });

  @override
  Future<void> reveal(String taskId, PlatformTransferDestination destination) =>
      methodChannel.invokeMethod<void>('reveal', {
        'taskId': taskId,
        'destination': destination.toMap(),
      });
}
