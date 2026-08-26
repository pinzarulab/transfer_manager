import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';
import 'package:transfer_manager_ios/transfer_manager_ios.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

/// Ready-to-use Android/iOS transfer manager with durable storage and native
/// background engines.
final class FlutterTransferManager with WidgetsBindingObserver {
  FlutterTransferManager._(this.manager, this._platform) {
    _notificationTapController =
        StreamController<TransferNotificationTap>.broadcast(
          onListen: _scheduleNotificationTapFlush,
        );
    WidgetsBinding.instance.addObserver(this);
    _platformTapSubscription = _platform.notificationTaps.listen(
      _receiveNotificationTap,
    );
    _initialNotificationTapFuture = _loadInitialNotificationTap();
  }

  final TransferManager manager;
  final TransferManagerPlatform _platform;
  late final StreamController<TransferNotificationTap>
  _notificationTapController;
  late final StreamSubscription<PlatformNotificationTap>
  _platformTapSubscription;
  late final Future<TransferNotificationTap?> _initialNotificationTapFuture;
  final List<TransferNotificationTap> _pendingNotificationTaps = [];
  final Set<String> _pendingNotificationTapIds = {};
  final Set<String> _handledNotificationTapIds = {};
  final Set<String> _platformHandledNotificationTapIds = {};
  Future<TransferNotificationTap?>? _notificationTapRecovery;
  Completer<void>? _resumedCompleter;
  bool _notificationTapFlushScheduled = false;
  bool _initialNotificationTapTaken = false;
  bool _closed = false;

  static Future<FlutterTransferManager> create({
    TransferConfiguration configuration = const TransferConfiguration(),
    TransferAuthProvider? authProvider,
    bool requestNotificationPermission = false,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('FlutterTransferManager supports Android and iOS');
    }
    final support = await getApplicationSupportDirectory();
    final platform = Platform.isAndroid
        ? TransferManagerAndroid()
        : TransferManagerIos();
    final manager = TransferManager(
      storage: JsonFileTransferStorage(
        File(
          '${support.path}${Platform.pathSeparator}'
          'transfer_manager${Platform.pathSeparator}tasks.json',
        ),
      ),
      authProvider: authProvider,
      configuration: TransferConfiguration(
        maxConcurrentTasks: configuration.maxConcurrentTasks,
        maxConcurrentUploads: configuration.maxConcurrentUploads,
        maxConcurrentDownloads: configuration.maxConcurrentDownloads,
        maxConcurrentTasksPerHost: configuration.maxConcurrentTasksPerHost,
        networkPolicy: configuration.networkPolicy,
        defaultRetryPolicy: configuration.defaultRetryPolicy,
        progressInterval: configuration.progressInterval,
        managedStoragePath:
            configuration.managedStoragePath ??
            '${support.path}${Platform.pathSeparator}transfer_manager'
                '${Platform.pathSeparator}managed',
        removeManagedSourceOnCompletion:
            configuration.removeManagedSourceOnCompletion,
        removeManagedSourceOnCancellation:
            configuration.removeManagedSourceOnCancellation,
      ),
      engines: [
        if (Platform.isAndroid) ...[
          AndroidBackgroundDownloadEngine(platform: platform),
          AndroidBackgroundTusUploadEngine(platform: platform),
          AndroidBackgroundUploadEngine(platform: platform),
        ],
        if (Platform.isIOS) ...[
          IosBackgroundDownloadEngine(platform: platform),
          IosBackgroundUploadEngine(platform: platform),
        ],
        TusTransferEngine(),
        HttpTransferEngine(),
      ],
      taskActions: _FlutterTaskActions(platform),
    );
    await manager.initialize();
    if (requestNotificationPermission &&
        !await platform.notificationsEnabled()) {
      await platform.requestNotificationPermission();
    }
    return FlutterTransferManager._(manager, platform);
  }

  /// Notification taps for custom in-app routing.
  Stream<TransferNotificationTap> get notificationTaps =>
      _notificationTapController.stream;

  /// Returns the cold-start tap once, when manual handling is needed.
  Future<TransferNotificationTap?> takeInitialNotificationTap() async {
    if (_initialNotificationTapTaken) return null;
    _initialNotificationTapTaken = true;
    final tap = await _initialNotificationTapFuture;
    if (tap == null) return null;
    await _waitUntilUiReady();
    return tap;
  }

  Future<bool> notificationsEnabled() => _platform.notificationsEnabled();

  Future<bool> requestNotificationPermission() =>
      _platform.requestNotificationPermission();

  Future<PlatformTransferCapabilities> get platformCapabilities =>
      _platform.capabilities();

  TransferTask? task(String taskId) => manager.task(taskId);

  Future<List<TransferTask>> tasks({Set<TransferState>? states}) =>
      manager.tasks(states: states);

  /// Queues a download with optional completion notification behavior.
  ///
  /// [showNotification] suppresses completion alerts when false.
  /// [openFromNotification] applies to the generated notification. If
  /// [notification] is supplied, its own [TransferNotification.openType] wins.
  /// [showLiveActivity] and [liveActivityStyle] configure iOS 16.1+ after the
  /// host app adds the package's Live Activity Widget Extension.
  Future<TransferTask> download(
    Uri source, {
    required String fileName,
    TransferDestination? destination,
    bool showNotification = true,
    NotificationOpenType openFromNotification = NotificationOpenType.open,
    bool showLiveActivity = false,
    LiveActivityStyle liveActivityStyle = LiveActivityStyle.system,
    bool allowPauseFromLiveActivity = true,
    bool allowCancelFromLiveActivity = true,
    TransferNotification? notification,
    Map<String, String> headers = const {},
    NetworkPolicy? networkPolicy,
    RetryPolicy? retryPolicy,
    ExistingFilePolicy existingFilePolicy = ExistingFilePolicy.replace,
  }) => manager.enqueue(
    DownloadRequest(
      source: source,
      destination: destination ?? TransferDestination.downloads(fileName),
      headers: headers,
      networkPolicy: networkPolicy,
      retryPolicy: retryPolicy,
      existingFilePolicy: existingFilePolicy,
      notification: showNotification
          ? notification ??
                TransferNotification(
                  title: fileName,
                  openType: openFromNotification,
                  allowPause: allowPauseFromLiveActivity,
                  allowCancel: allowCancelFromLiveActivity,
                  showLiveActivity: showLiveActivity,
                  liveActivityStyle: liveActivityStyle,
                )
          : null,
    ),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumedCompleter?.complete();
      _resumedCompleter = null;
      unawaited(_recoverNotificationTap());
      _scheduleNotificationTapFlush();
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _resumedCompleter?.complete();
    _resumedCompleter = null;
    WidgetsBinding.instance.removeObserver(this);
    await _platformTapSubscription.cancel();
    await _notificationTapController.close();
    await manager.close();
  }

  void _receiveNotificationTap(PlatformNotificationTap tap) {
    if (tap.actionHandled) {
      _platformHandledNotificationTapIds.add(tap.taskId);
    }
    _enqueueNotificationTap(_mapTap(tap));
  }

  Future<TransferNotificationTap?> _loadInitialNotificationTap() =>
      _recoverNotificationTap();

  Future<TransferNotificationTap?> _recoverNotificationTap() {
    final active = _notificationTapRecovery;
    if (active != null) return active;
    final recovery = _takeAndQueueNotificationTap();
    _notificationTapRecovery = recovery;
    unawaited(
      recovery.whenComplete(() {
        if (identical(_notificationTapRecovery, recovery)) {
          _notificationTapRecovery = null;
        }
      }),
    );
    return recovery;
  }

  Future<TransferNotificationTap?> _takeAndQueueNotificationTap() async {
    try {
      final platformTap = await _platform.takeInitialNotificationTap();
      if (platformTap == null || _closed) return null;
      if (platformTap.actionHandled) {
        _platformHandledNotificationTapIds.add(platformTap.taskId);
      }
      final tap = _mapTap(platformTap);
      _enqueueNotificationTap(tap);
      return tap;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'transfer_manager_flutter',
          context: ErrorDescription('recovering a notification tap'),
        ),
      );
      return null;
    }
  }

  void _enqueueNotificationTap(TransferNotificationTap tap) {
    if (_closed ||
        _handledNotificationTapIds.contains(tap.taskId) ||
        !_pendingNotificationTapIds.add(tap.taskId)) {
      return;
    }
    _pendingNotificationTaps.add(tap);
    _scheduleNotificationTapFlush();
  }

  Future<void> _waitUntilUiReady() async {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      _resumedCompleter ??= Completer<void>();
      await _resumedCompleter!.future;
    }
    if (_closed) return;
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
  }

  void _scheduleNotificationTapFlush() {
    if (_closed ||
        _notificationTapFlushScheduled ||
        _pendingNotificationTaps.isEmpty ||
        (!_notificationTapController.hasListener &&
            !_pendingNotificationTaps.any(_hasAutomaticAction)) ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _notificationTapFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationTapFlushScheduled = false;
      if (_closed ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final taps = List<TransferNotificationTap>.of(_pendingNotificationTaps);
      _pendingNotificationTaps.clear();
      for (final tap in taps) {
        final hasAutomaticAction = _hasAutomaticAction(tap);
        if (_notificationTapController.hasListener) {
          _notificationTapController.add(tap);
          if (!hasAutomaticAction) {
            _pendingNotificationTapIds.remove(tap.taskId);
            _markNotificationTapHandled(tap.taskId);
          }
        } else if (!hasAutomaticAction) {
          _pendingNotificationTaps.add(tap);
        }
        if (hasAutomaticAction) unawaited(_actFromNotification(tap));
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  bool _hasAutomaticAction(TransferNotificationTap tap) {
    final request = manager.task(tap.taskId)?.request;
    return !_platformHandledNotificationTapIds.contains(tap.taskId) &&
        request is DownloadRequest &&
        request.notification != null;
  }

  Future<void> _actFromNotification(TransferNotificationTap tap) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    try {
      await _waitUntilUiReady();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final task = manager.task(tap.taskId);
      final request = task?.request;
      if (task == null || request is! DownloadRequest) return;
      final action = request.notification?.openType;
      if (action == null) return;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          if (action == NotificationOpenType.open) {
            await task.open();
          } else {
            await task.reveal();
          }
          _pendingNotificationTapIds.remove(tap.taskId);
          _markNotificationTapHandled(tap.taskId);
          return;
        } catch (error, stackTrace) {
          lastError = error;
          lastStackTrace = stackTrace;
          if (attempt < 2) {
            await Future<void>.delayed(
              Duration(milliseconds: 400 * (attempt + 1)),
            );
          }
        }
      }
    } finally {
      if (!_handledNotificationTapIds.contains(tap.taskId) && !_closed) {
        _pendingNotificationTaps.add(tap);
      }
    }
    if (lastError != null) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: lastError,
          stack: lastStackTrace,
          library: 'transfer_manager_flutter',
          context: ErrorDescription('handling a download notification tap'),
        ),
      );
    }
  }

  void _markNotificationTapHandled(String taskId) {
    _platformHandledNotificationTapIds.remove(taskId);
    _handledNotificationTapIds.add(taskId);
    if (_handledNotificationTapIds.length > 256) {
      _handledNotificationTapIds.remove(_handledNotificationTapIds.first);
    }
  }

  TransferNotificationTap _mapTap(PlatformNotificationTap tap) {
    final request = manager.task(tap.taskId)?.request;
    if (request is DownloadRequest) {
      return TransferNotificationTap(
        taskId: tap.taskId,
        destination: request.destination,
      );
    }
    final destination = tap.destination;
    return TransferNotificationTap(
      taskId: tap.taskId,
      destination: destination == null
          ? null
          : destination.kind == TransferDestinationKind.downloads.name
          ? TransferDestination.downloads(destination.value)
          : TransferDestination.file(destination.value),
    );
  }
}

final class _FlutterTaskActions implements TransferTaskActions {
  const _FlutterTaskActions(this.platform);

  final TransferManagerPlatform platform;

  @override
  Future<void> open(TransferRecord record) =>
      platform.open(record.id, _destination(record));

  @override
  Future<void> reveal(TransferRecord record) =>
      platform.reveal(record.id, _destination(record));

  PlatformTransferDestination _destination(TransferRecord record) {
    final request = record.request;
    if (request is! DownloadRequest) {
      throw UnsupportedError('Only downloaded artifacts can be opened');
    }
    return PlatformTransferDestination(
      kind: request.destination.kind.name,
      value: request.destination.value,
    );
  }
}
