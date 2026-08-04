import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';
import 'package:transfer_manager_ios/transfer_manager_ios.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

/// Ready-to-use Android/iOS transfer manager with durable storage and native
/// background engines.
final class FlutterTransferManager {
  FlutterTransferManager._(this.manager, this._platform);

  final TransferManager manager;
  final TransferManagerPlatform _platform;

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
      _platform.notificationTaps.map(_mapTap);

  Future<TransferNotificationTap?> takeInitialNotificationTap() async {
    final tap = await _platform.takeInitialNotificationTap();
    return tap == null ? null : _mapTap(tap);
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

  Future<void> close() => manager.close();

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
    if (record.state != TransferState.completed) {
      throw StateError('Transfer must be completed before opening it');
    }
    return PlatformTransferDestination(
      kind: request.destination.kind.name,
      value: request.destination.value,
    );
  }
}
