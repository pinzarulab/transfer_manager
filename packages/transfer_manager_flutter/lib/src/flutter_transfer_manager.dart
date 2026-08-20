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
  }

  final TransferManager manager;
  final TransferManagerPlatform _platform;
  late final StreamController<TransferNotificationTap>
  _notificationTapController;
  late final StreamSubscription<PlatformNotificationTap>
  _platformTapSubscription;
  final List<TransferNotificationTap> _pendingNotificationTaps = [];
  Completer<void>? _resumedCompleter;
  bool _notificationTapFlushScheduled = false;
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

  Stream<TransferNotificationTap> get notificationTaps =>
      _notificationTapController.stream;

  Future<TransferNotificationTap?> takeInitialNotificationTap() async {
    final tap = await _platform.takeInitialNotificationTap();
    if (tap == null) return null;
    await _waitUntilUiReady();
    return _mapTap(tap);
  }

  Future<bool> notificationsEnabled() => _platform.notificationsEnabled();

  Future<bool> requestNotificationPermission() =>
      _platform.requestNotificationPermission();

  Future<PlatformTransferCapabilities> get platformCapabilities =>
      _platform.capabilities();

  TransferTask? task(String taskId) => manager.task(taskId);

  Future<List<TransferTask>> tasks({Set<TransferState>? states}) =>
      manager.tasks(states: states);

  Future<TransferTask> download(
    Uri source, {
    required String fileName,
    TransferDestination? destination,
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
      notification: notification ?? TransferNotification(title: fileName),
    ),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resumedCompleter?.complete();
      _resumedCompleter = null;
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
    _pendingNotificationTaps.add(_mapTap(tap));
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
        !_notificationTapController.hasListener ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _notificationTapFlushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationTapFlushScheduled = false;
      if (_closed ||
          !_notificationTapController.hasListener ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final taps = List<TransferNotificationTap>.of(_pendingNotificationTaps);
      _pendingNotificationTaps.clear();
      for (final tap in taps) {
        _notificationTapController.add(tap);
      }
    });
    WidgetsBinding.instance.scheduleFrame();
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
