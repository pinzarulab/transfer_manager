import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

final class TransferManagerIos extends TransferManagerPlatform {
  TransferManagerIos({MethodChannel? methodChannel, EventChannel? eventChannel})
    : methodChannel =
          methodChannel ??
          const MethodChannel('pinzarulab.com/transfer_manager_ios/methods'),
      eventChannel =
          eventChannel ??
          const EventChannel('pinzarulab.com/transfer_manager_ios/events');

  @visibleForTesting
  final MethodChannel methodChannel;
  @visibleForTesting
  final EventChannel eventChannel;

  Stream<PlatformTaskSnapshot>? _snapshots;
  final StreamController<PlatformNotificationTap> _notificationResponses =
      StreamController<PlatformNotificationTap>.broadcast(sync: true);
  bool _methodHandlerInstalled = false;

  /// Notification taps delivered while the Flutter engine is running.
  Stream<IosTransferNotificationResponse> get notificationResponses {
    _ensureMethodHandler();
    return _notificationResponses.stream;
  }

  @override
  Stream<PlatformNotificationTap> get notificationTaps {
    _ensureMethodHandler();
    return _notificationResponses.stream;
  }

  /// Returns and clears a notification tap that launched the application.
  Future<IosTransferNotificationResponse?>
  takeInitialNotificationResponse() async {
    _ensureMethodHandler();
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'takeInitialNotificationResponse',
    );
    return value == null ? null : PlatformNotificationTap.fromMap(value);
  }

  @override
  Future<PlatformNotificationTap?> takeInitialNotificationTap() =>
      takeInitialNotificationResponse();

  Future<Object?> _handleNativeMethod(MethodCall call) async {
    if (call.method != 'notificationTapped') {
      throw MissingPluginException('Unknown native method ${call.method}');
    }
    final response = PlatformNotificationTap.fromMap(
      call.arguments! as Map<Object?, Object?>,
    );
    _notificationResponses.add(response);
    return null;
  }

  void _ensureMethodHandler() {
    if (_methodHandlerInstalled) return;
    methodChannel.setMethodCallHandler(_handleNativeMethod);
    _methodHandlerInstalled = true;
  }

  static void registerWith() {
    TransferManagerPlatform.instance = TransferManagerIos();
  }

  @override
  Future<PlatformTransferCapabilities> capabilities() async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'capabilities',
    );
    return PlatformTransferCapabilities.fromMap(value ?? const {});
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
  Future<String> enqueueDownload(PlatformDownloadRequest request) =>
      _enqueue('enqueueDownload', request.toMap());

  @override
  Future<String> enqueueUpload(PlatformUploadRequest request) =>
      _enqueue('enqueueUpload', request.toMap());

  @override
  Future<String> enqueueTusUpload(PlatformTusUploadRequest request) =>
      throw UnsupportedError('Native background TUS is unavailable on iOS');

  Future<String> _enqueue(String method, Map<String, Object?> arguments) async {
    final identifier = await methodChannel.invokeMethod<String>(
      method,
      arguments,
    );
    if (identifier == null) {
      throw PlatformException(
        code: 'missing_task_id',
        message: 'iOS did not return a URLSession task identifier',
      );
    }
    return identifier;
  }

  @override
  Future<PlatformTaskSnapshot?> task(String taskId) async {
    final value = await methodChannel.invokeMapMethod<Object?, Object?>(
      'task',
      {'taskId': taskId},
    );
    return value == null ? null : PlatformTaskSnapshot.fromMap(value);
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

typedef IosTransferNotificationResponse = PlatformNotificationTap;
