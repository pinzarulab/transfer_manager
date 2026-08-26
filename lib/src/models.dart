import 'dart:math' as math;

/// Lifecycle state of a transfer task.
enum TransferState {
  /// Task exists but has not entered the queue.
  created,

  /// Task is waiting for an execution slot.
  queued,

  /// Task is preparing local resources.
  preparing,

  /// Task is actively transferring data.
  running,

  /// Task was paused and can be resumed.
  paused,

  /// Task is waiting before an automatic retry.
  retryWaiting,

  /// Transferred data is being integrity checked.
  verifying,

  /// Task finished successfully.
  completed,

  /// Task stopped because of an error.
  failed,

  /// Task was cancelled.
  cancelled,
}

/// Scheduling priority used when multiple tasks are queued.
enum TransferPriority { background, low, normal, high, immediate }

/// Direction of a transfer.
enum TransferType { upload, download }

/// Controls whether an interrupted download may resume.
enum ResumeMode { never, whenSupported, required }

/// Behavior when a download destination already exists.
enum ExistingFilePolicy { fail, replace, keepExisting, resume, rename }

/// Storage category represented by a [TransferDestination].
enum TransferDestinationKind { file, downloads }

/// Platform-neutral destination for a downloaded artifact.
sealed class TransferDestination {
  /// Creates a destination base value.
  const TransferDestination();

  /// Stores the artifact at an explicit filesystem [path].
  const factory TransferDestination.file(String path) = FileTransferDestination;

  /// Stores the artifact in the platform-visible Downloads location.
  const factory TransferDestination.downloads(String fileName) =
      DownloadsTransferDestination;

  /// Destination category understood by storage and platform engines.
  TransferDestinationKind get kind;

  /// Serialized path or file-name value.
  String get value;

  /// Name of the destination file.
  String get fileName => switch (this) {
    FileTransferDestination(:final path) => Uri.file(path).pathSegments.last,
    DownloadsTransferDestination(:final fileName) => fileName,
  };

  /// Encodes this destination for durable storage.
  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};

  /// Decodes a destination previously produced by [toJson].
  factory TransferDestination.fromJson(Map<String, Object?> json) =>
      switch (TransferDestinationKind.values.byName(json['kind']! as String)) {
        TransferDestinationKind.file => TransferDestination.file(
          json['value']! as String,
        ),
        TransferDestinationKind.downloads => TransferDestination.downloads(
          json['value']! as String,
        ),
      };
}

/// Download destination backed by an explicit filesystem path.
final class FileTransferDestination extends TransferDestination {
  /// Creates an explicit-path destination.
  const FileTransferDestination(this.path) : assert(path != '');

  /// Absolute or application-relative destination path.
  final String path;

  @override
  TransferDestinationKind get kind => TransferDestinationKind.file;

  @override
  String get value => path;
}

/// Download destination in the user-visible Downloads collection.
final class DownloadsTransferDestination extends TransferDestination {
  /// Creates a public Downloads destination for [fileName].
  const DownloadsTransferDestination(this.fileName) : assert(fileName != '');

  @override
  final String fileName;

  @override
  TransferDestinationKind get kind => TransferDestinationKind.downloads;

  @override
  String get value => fileName;
}

/// Network requirement applied to a transfer.
enum NetworkPolicy { any, unmetered, wifiOnly }

/// Persistence strategy for a local upload source.
enum UploadSourcePolicy { reference, copyToManagedStorage }

/// Supported file-integrity hash algorithms.
enum ChecksumAlgorithm { sha256, sha512, md5 }

/// Describes the hash algorithm used to verify transferred data.
final class Checksum {
  /// Creates a checksum descriptor for [algorithm].
  const Checksum(this.algorithm);

  /// Hash algorithm used during verification.
  final ChecksumAlgorithm algorithm;

  /// SHA-256 checksum descriptor.
  static const sha256 = Checksum(ChecksumAlgorithm.sha256);

  /// SHA-512 checksum descriptor.
  static const sha512 = Checksum(ChecksumAlgorithm.sha512);

  /// MD5 checksum descriptor for compatibility with legacy servers.
  @Deprecated('MD5 is provided only for compatibility.')
  static const md5 = Checksum(ChecksumAlgorithm.md5);
}

/// Exponential retry configuration for recoverable failures.
final class RetryPolicy {
  /// Creates an exponential-backoff retry policy.
  const RetryPolicy.exponential({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.maximumDelay = const Duration(minutes: 2),
    this.jitter = true,
  });

  /// Maximum number of execution attempts, including the first attempt.
  final int maxAttempts;

  /// Delay used before the first retry.
  final Duration initialDelay;

  /// Upper bound for an exponential delay.
  final Duration maximumDelay;

  /// Whether delays include randomized jitter.
  final bool jitter;

  /// Calculates the delay before retry [attempt].
  Duration delayForAttempt(int attempt, {math.Random? random}) {
    final exponent = math.max(0, attempt - 1);
    final raw = initialDelay.inMilliseconds * math.pow(2, exponent);
    var milliseconds = math.min(raw, maximumDelay.inMilliseconds).round();
    if (jitter && milliseconds > 1) {
      milliseconds =
          (milliseconds * (0.5 + (random ?? math.Random()).nextDouble() * 0.5))
              .round();
    }
    return Duration(milliseconds: milliseconds);
  }
}

/// Queue, concurrency, retry, and managed-storage defaults.
final class TransferConfiguration {
  /// Creates transfer-manager configuration.
  const TransferConfiguration({
    this.maxConcurrentTasks = 3,
    this.maxConcurrentUploads = 2,
    this.maxConcurrentDownloads = 2,
    this.maxConcurrentTasksPerHost = 2,
    this.networkPolicy = NetworkPolicy.any,
    this.defaultRetryPolicy = const RetryPolicy.exponential(),
    this.progressInterval = const Duration(milliseconds: 150),
    this.managedStoragePath,
    this.removeManagedSourceOnCompletion = true,
    this.removeManagedSourceOnCancellation = true,
  }) : assert(maxConcurrentTasks > 0),
       assert(maxConcurrentUploads > 0),
       assert(maxConcurrentDownloads > 0),
       assert(maxConcurrentTasksPerHost > 0);

  /// Maximum number of transfers that may run simultaneously.
  final int maxConcurrentTasks;

  /// Maximum number of uploads that may run simultaneously.
  final int maxConcurrentUploads;

  /// Maximum number of downloads that may run simultaneously.
  final int maxConcurrentDownloads;

  /// Maximum number of simultaneous transfers to one remote host.
  final int maxConcurrentTasksPerHost;

  /// Default network requirement for requests without an override.
  final NetworkPolicy networkPolicy;

  /// Default retry behavior for requests without an override.
  final RetryPolicy defaultRetryPolicy;

  /// Minimum interval between emitted progress updates.
  final Duration progressInterval;

  /// Root directory used by [UploadSourcePolicy.copyToManagedStorage].
  final String? managedStoragePath;

  /// Deletes managed upload copies after successful completion.
  final bool removeManagedSourceOnCompletion;

  /// Deletes managed upload copies after cancellation.
  final bool removeManagedSourceOnCancellation;
}

/// Action performed after a user taps a completed-download notification.
enum NotificationOpenType {
  /// Performs the same action as `TransferTask.open()`.
  open,

  /// Performs the same action as `TransferTask.reveal()`.
  reveal,
}

/// Visual preset used by an iOS Live Activity.
///
/// The system still controls the Lock Screen and Dynamic Island presentation;
/// this value selects the package-provided layout inside those surfaces.
enum LiveActivityStyle {
  /// Native materials, restrained color, and standard information density.
  system,

  /// A small progress-first layout for short file names.
  compact,

  /// File name, byte counts, percentage, and the available actions.
  detailed,

  /// A stronger accent treatment with a large progress value.
  prominent,
}

/// Controls native progress and completion notifications for one transfer.
final class TransferNotification {
  /// Creates notification preferences for a transfer.
  const TransferNotification({
    required this.title,
    this.showProgress = true,
    this.allowPause = false,
    this.allowCancel = true,
    this.openType = NotificationOpenType.open,
    this.showLiveActivity = false,
    this.liveActivityStyle = LiveActivityStyle.system,
  });

  /// User-visible notification title.
  final String title;

  /// Whether active notifications show transfer progress.
  final bool showProgress;

  /// Whether a pause action may be displayed.
  final bool allowPause;

  /// Whether a cancel action may be displayed.
  final bool allowCancel;

  /// Action performed after the completion notification is tapped.
  final NotificationOpenType openType;

  /// Whether iOS should display progress as a Live Activity.
  ///
  /// Requires iOS 16.1 or newer and a Live Activity Widget Extension in the
  /// host application. Other platforms ignore this option.
  final bool showLiveActivity;

  /// Package-provided visual preset for the iOS Live Activity.
  final LiveActivityStyle liveActivityStyle;

  /// Encodes these preferences for durable storage.
  Map<String, Object?> toJson() => {
    'title': title,
    'showProgress': showProgress,
    'allowPause': allowPause,
    'allowCancel': allowCancel,
    'openType': openType.name,
    'showLiveActivity': showLiveActivity,
    'liveActivityStyle': liveActivityStyle.name,
  };

  /// Decodes notification preferences from durable storage.
  factory TransferNotification.fromJson(Map<String, Object?> json) =>
      TransferNotification(
        title: json['title']! as String,
        showProgress: json['showProgress'] as bool? ?? true,
        allowPause: json['allowPause'] as bool? ?? false,
        allowCancel: json['allowCancel'] as bool? ?? true,
        openType: NotificationOpenType.values.byName(
          json['openType'] as String? ?? NotificationOpenType.open.name,
        ),
        showLiveActivity: json['showLiveActivity'] as bool? ?? false,
        liveActivityStyle: LiveActivityStyle.values.byName(
          json['liveActivityStyle'] as String? ?? LiveActivityStyle.system.name,
        ),
      );
}

/// Immutable base configuration shared by upload and download requests.
sealed class TransferRequest {
  /// Creates shared request configuration.
  const TransferRequest({
    this.headers = const {},
    this.authScope,
    this.groupId,
    this.priority = TransferPriority.normal,
    this.retryPolicy,
    this.networkPolicy,
    this.notification,
    this.checksum,
    this.expectedChecksum,
  });

  /// Whether this request uploads or downloads data.
  TransferType get type;

  /// Remote endpoint used for scheduling and per-host concurrency.
  Uri get remoteUri;

  /// Protocol identifier used to select an execution engine.
  String get protocol;

  /// Additional HTTP headers sent with the request.
  final Map<String, String> headers;

  /// Opaque key passed to the configured authentication provider.
  final String? authScope;

  /// Optional application-defined grouping identifier.
  final String? groupId;

  /// Queue scheduling priority.
  final TransferPriority priority;

  /// Request-specific retry policy, or `null` to use manager defaults.
  final RetryPolicy? retryPolicy;

  /// Request-specific network policy, or `null` to use manager defaults.
  final NetworkPolicy? networkPolicy;

  /// Native notification preferences.
  final TransferNotification? notification;

  /// Hash algorithm used to verify the local artifact.
  final Checksum? checksum;

  /// Expected lowercase or uppercase hexadecimal checksum.
  final String? expectedChecksum;
}

/// HTTP multipart upload request.
final class UploadRequest extends TransferRequest {
  /// Creates a multipart upload request.
  const UploadRequest({
    required this.sourcePath,
    required this.destination,
    this.method = 'POST',
    this.fieldName = 'file',
    this.sourcePolicy = UploadSourcePolicy.reference,
    super.headers,
    super.authScope,
    super.groupId,
    super.priority,
    super.retryPolicy,
    super.networkPolicy,
    super.notification,
    super.checksum,
    super.expectedChecksum,
  });

  /// Path of the local file to upload.
  final String sourcePath;

  /// Remote upload endpoint.
  final Uri destination;

  /// HTTP method used for the multipart request.
  final String method;

  /// Multipart form field containing the file.
  final String fieldName;

  /// Persistence strategy for the local source file.
  final UploadSourcePolicy sourcePolicy;

  @override
  TransferType get type => TransferType.upload;
  @override
  Uri get remoteUri => destination;
  @override
  String get protocol => 'http-multipart';

  /// Returns an equivalent request that reads from [path].
  UploadRequest withSourcePath(String path) => UploadRequest(
    sourcePath: path,
    destination: destination,
    method: method,
    fieldName: fieldName,
    sourcePolicy: sourcePolicy,
    headers: headers,
    authScope: authScope,
    groupId: groupId,
    priority: priority,
    retryPolicy: retryPolicy,
    networkPolicy: networkPolicy,
    notification: notification,
    checksum: checksum,
    expectedChecksum: expectedChecksum,
  );
}

/// A resumable upload using version 1.0 of the TUS protocol.
///
/// The server-created upload URL and acknowledged offset are persisted in the
/// task's protocol metadata. Retries and restored tasks reconcile the offset
/// with the server before sending another chunk.
final class TusUploadRequest extends TransferRequest {
  /// Creates a resumable TUS upload request.
  const TusUploadRequest({
    required this.sourcePath,
    required this.endpoint,
    this.chunkSize = 5 * 1024 * 1024,
    this.metadata = const {},
    this.sourcePolicy = UploadSourcePolicy.reference,
    super.headers,
    super.authScope,
    super.groupId,
    super.priority,
    super.retryPolicy,
    super.networkPolicy,
    super.notification,
    super.checksum,
    super.expectedChecksum,
  }) : assert(chunkSize > 0);

  /// Path of the local file to upload.
  final String sourcePath;

  /// TUS server creation endpoint.
  final Uri endpoint;

  /// Maximum payload bytes sent in one PATCH request.
  final int chunkSize;

  /// Values are encoded as Base64 when sent in `Upload-Metadata`.
  final Map<String, String> metadata;

  /// Persistence strategy for the local source file.
  final UploadSourcePolicy sourcePolicy;

  @override
  TransferType get type => TransferType.upload;
  @override
  Uri get remoteUri => endpoint;
  @override
  String get protocol => 'tus-1.0';

  /// Returns an equivalent request that reads from [path].
  TusUploadRequest withSourcePath(String path) => TusUploadRequest(
    sourcePath: path,
    endpoint: endpoint,
    chunkSize: chunkSize,
    metadata: metadata,
    sourcePolicy: sourcePolicy,
    headers: headers,
    authScope: authScope,
    groupId: groupId,
    priority: priority,
    retryPolicy: retryPolicy,
    networkPolicy: networkPolicy,
    notification: notification,
    checksum: checksum,
    expectedChecksum: expectedChecksum,
  );
}

/// HTTP download request supporting ranged resumption.
final class DownloadRequest extends TransferRequest {
  /// Creates an HTTP download request.
  const DownloadRequest({
    required this.source,
    required this.destination,
    this.resumeMode = ResumeMode.whenSupported,
    this.existingFilePolicy = ExistingFilePolicy.resume,
    super.headers,
    super.authScope,
    super.groupId,
    super.priority,
    super.retryPolicy,
    super.networkPolicy,
    super.notification,
    super.checksum,
    super.expectedChecksum,
  });

  /// Remote file URL.
  final Uri source;

  /// Platform-neutral destination for the completed artifact.
  final TransferDestination destination;

  /// Whether interrupted partial data may be resumed.
  final ResumeMode resumeMode;

  /// Behavior when the final destination already exists.
  final ExistingFilePolicy existingFilePolicy;

  @override
  TransferType get type => TransferType.download;
  @override
  Uri get remoteUri => source;
  @override
  String get protocol => 'http-range';
}

/// Platform-neutral completion-notification interaction.
final class TransferNotificationTap {
  /// Creates a notification-tap event.
  const TransferNotificationTap({required this.taskId, this.destination});

  /// Identifier of the transfer associated with the notification.
  final String taskId;

  /// Download destination when supplied by the platform.
  final TransferDestination? destination;
}

/// Immutable progress snapshot for a transfer.
final class TransferProgress {
  /// Creates a progress snapshot.
  const TransferProgress({
    required this.bytesTransferred,
    this.totalBytes,
    this.smoothedBytesPerSecond = 0,
    this.estimatedRemaining,
    this.currentChunk,
    this.totalChunks,
  });

  /// Empty progress before any bytes have transferred.
  static const zero = TransferProgress(bytesTransferred: 0);

  /// Number of bytes acknowledged so far.
  final int bytesTransferred;

  /// Expected total bytes, when known.
  final int? totalBytes;

  /// Exponentially smoothed transfer rate in bytes per second.
  final double smoothedBytesPerSecond;

  /// Estimated time until completion, when calculable.
  final Duration? estimatedRemaining;

  /// Current protocol chunk number, when exposed by the engine.
  final int? currentChunk;

  /// Total protocol chunks, when known.
  final int? totalChunks;

  /// Completion ratio from `0` to `1`, or `null` when total size is unknown.
  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (bytesTransferred / totalBytes!).clamp(0, 1);
}

/// State and progress update emitted by a [TransferTask].
final class TransferEvent {
  /// Creates a transfer event.
  const TransferEvent({
    required this.taskId,
    required this.state,
    required this.progress,
    this.error,
    required this.timestamp,
  });

  /// Identifier of the updated task.
  final String taskId;

  /// Task state at [timestamp].
  final TransferState state;

  /// Latest progress snapshot.
  final TransferProgress progress;

  /// Failure associated with this update, if any.
  final Object? error;

  /// UTC time when the event was produced.
  final DateTime timestamp;
}

/// Durable mutable state stored for one transfer task.
final class TransferRecord {
  /// Creates a persisted task record.
  TransferRecord({
    required this.id,
    required this.request,
    this.state = TransferState.created,
    this.bytesTransferred = 0,
    this.totalBytes,
    this.retryAttempts = 0,
    this.nativeTaskId,
    Map<String, Object?>? protocolMetadata,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.error,
  }) : protocolMetadata = protocolMetadata ?? {},
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  /// Stable task identifier.
  final String id;

  /// Immutable transfer request.
  final TransferRequest request;

  /// Current lifecycle state.
  TransferState state;

  /// Number of bytes acknowledged so far.
  int bytesTransferred;

  /// Expected total bytes, when known.
  int? totalBytes;

  /// Number of retry attempts already scheduled.
  int retryAttempts;

  /// Identifier assigned by a native background scheduler.
  String? nativeTaskId;

  /// Protocol-specific durable session data.
  final Map<String, Object?> protocolMetadata;

  /// UTC creation time.
  final DateTime createdAt;

  /// UTC time of the latest record update.
  DateTime updatedAt;

  /// Most recent failure, if any.
  Object? error;

  /// Creates an independent snapshot of this record.
  TransferRecord copy() => TransferRecord(
    id: id,
    request: request,
    state: state,
    bytesTransferred: bytesTransferred,
    totalBytes: totalBytes,
    retryAttempts: retryAttempts,
    nativeTaskId: nativeTaskId,
    protocolMetadata: Map.of(protocolMetadata),
    createdAt: createdAt,
    updatedAt: updatedAt,
    error: error,
  );
}

/// Feature summary exposed by the core transfer manager.
final class TransferCapabilities {
  /// Creates a feature summary.
  const TransferCapabilities({
    this.backgroundExecution = false,
    this.pauseResume = true,
    this.notifications = false,
    this.notificationActions = false,
  });

  /// Whether configured engines can continue in the background.
  final bool backgroundExecution;

  /// Whether tasks expose pause and resume controls.
  final bool pauseResume;

  /// Whether native transfer notifications are available.
  final bool notifications;

  /// Whether native notifications can expose task actions.
  final bool notificationActions;
}
