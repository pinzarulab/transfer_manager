import 'dart:math' as math;

enum TransferState {
  created,
  queued,
  preparing,
  running,
  paused,
  retryWaiting,
  verifying,
  completed,
  failed,
  cancelled,
}

enum TransferPriority { background, low, normal, high, immediate }

enum TransferType { upload, download }

enum ResumeMode { never, whenSupported, required }

enum ExistingFilePolicy { fail, replace, keepExisting, resume, rename }

enum TransferDestinationKind { file, downloads }

/// Platform-neutral destination for a downloaded artifact.
sealed class TransferDestination {
  const TransferDestination();

  const factory TransferDestination.file(String path) = FileTransferDestination;
  const factory TransferDestination.downloads(String fileName) =
      DownloadsTransferDestination;

  TransferDestinationKind get kind;
  String get value;

  String get fileName => switch (this) {
    FileTransferDestination(:final path) => Uri.file(path).pathSegments.last,
    DownloadsTransferDestination(:final fileName) => fileName,
  };

  Map<String, Object?> toJson() => {'kind': kind.name, 'value': value};

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

final class FileTransferDestination extends TransferDestination {
  const FileTransferDestination(this.path) : assert(path != '');

  final String path;

  @override
  TransferDestinationKind get kind => TransferDestinationKind.file;

  @override
  String get value => path;
}

final class DownloadsTransferDestination extends TransferDestination {
  const DownloadsTransferDestination(this.fileName) : assert(fileName != '');

  @override
  final String fileName;

  @override
  TransferDestinationKind get kind => TransferDestinationKind.downloads;

  @override
  String get value => fileName;
}

enum NetworkPolicy { any, unmetered, wifiOnly }

enum UploadSourcePolicy { reference, copyToManagedStorage }

enum ChecksumAlgorithm { sha256, sha512, md5 }

final class Checksum {
  const Checksum(this.algorithm);

  final ChecksumAlgorithm algorithm;

  static const sha256 = Checksum(ChecksumAlgorithm.sha256);
  static const sha512 = Checksum(ChecksumAlgorithm.sha512);

  @Deprecated('MD5 is provided only for compatibility.')
  static const md5 = Checksum(ChecksumAlgorithm.md5);
}

final class RetryPolicy {
  const RetryPolicy.exponential({
    this.maxAttempts = 5,
    this.initialDelay = const Duration(seconds: 1),
    this.maximumDelay = const Duration(minutes: 2),
    this.jitter = true,
  });

  final int maxAttempts;
  final Duration initialDelay;
  final Duration maximumDelay;
  final bool jitter;

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

final class TransferConfiguration {
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

  final int maxConcurrentTasks;
  final int maxConcurrentUploads;
  final int maxConcurrentDownloads;
  final int maxConcurrentTasksPerHost;
  final NetworkPolicy networkPolicy;
  final RetryPolicy defaultRetryPolicy;
  final Duration progressInterval;

  /// Root directory used by [UploadSourcePolicy.copyToManagedStorage].
  final String? managedStoragePath;
  final bool removeManagedSourceOnCompletion;
  final bool removeManagedSourceOnCancellation;
}

final class TransferNotification {
  const TransferNotification({
    required this.title,
    this.showProgress = true,
    this.allowPause = false,
    this.allowCancel = true,
  });

  final String title;
  final bool showProgress;
  final bool allowPause;
  final bool allowCancel;

  Map<String, Object?> toJson() => {
    'title': title,
    'showProgress': showProgress,
    'allowPause': allowPause,
    'allowCancel': allowCancel,
  };

  factory TransferNotification.fromJson(Map<String, Object?> json) =>
      TransferNotification(
        title: json['title']! as String,
        showProgress: json['showProgress'] as bool? ?? true,
        allowPause: json['allowPause'] as bool? ?? false,
        allowCancel: json['allowCancel'] as bool? ?? true,
      );
}

sealed class TransferRequest {
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

  TransferType get type;
  Uri get remoteUri;
  String get protocol;
  final Map<String, String> headers;
  final String? authScope;
  final String? groupId;
  final TransferPriority priority;
  final RetryPolicy? retryPolicy;
  final NetworkPolicy? networkPolicy;
  final TransferNotification? notification;
  final Checksum? checksum;
  final String? expectedChecksum;
}

final class UploadRequest extends TransferRequest {
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

  final String sourcePath;
  final Uri destination;
  final String method;
  final String fieldName;
  final UploadSourcePolicy sourcePolicy;

  @override
  TransferType get type => TransferType.upload;
  @override
  Uri get remoteUri => destination;
  @override
  String get protocol => 'http-multipart';

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

  final String sourcePath;
  final Uri endpoint;
  final int chunkSize;

  /// Values are encoded as Base64 when sent in `Upload-Metadata`.
  final Map<String, String> metadata;
  final UploadSourcePolicy sourcePolicy;

  @override
  TransferType get type => TransferType.upload;
  @override
  Uri get remoteUri => endpoint;
  @override
  String get protocol => 'tus-1.0';

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

final class DownloadRequest extends TransferRequest {
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

  final Uri source;
  final TransferDestination destination;

  final ResumeMode resumeMode;
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
  const TransferNotificationTap({required this.taskId, this.destination});

  final String taskId;
  final TransferDestination? destination;
}

final class TransferProgress {
  const TransferProgress({
    required this.bytesTransferred,
    this.totalBytes,
    this.smoothedBytesPerSecond = 0,
    this.estimatedRemaining,
    this.currentChunk,
    this.totalChunks,
  });

  static const zero = TransferProgress(bytesTransferred: 0);

  final int bytesTransferred;
  final int? totalBytes;
  final double smoothedBytesPerSecond;
  final Duration? estimatedRemaining;
  final int? currentChunk;
  final int? totalChunks;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (bytesTransferred / totalBytes!).clamp(0, 1);
}

final class TransferEvent {
  const TransferEvent({
    required this.taskId,
    required this.state,
    required this.progress,
    this.error,
    required this.timestamp,
  });

  final String taskId;
  final TransferState state;
  final TransferProgress progress;
  final Object? error;
  final DateTime timestamp;
}

final class TransferRecord {
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

  final String id;
  final TransferRequest request;
  TransferState state;
  int bytesTransferred;
  int? totalBytes;
  int retryAttempts;
  String? nativeTaskId;
  final Map<String, Object?> protocolMetadata;
  final DateTime createdAt;
  DateTime updatedAt;
  Object? error;

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

final class TransferCapabilities {
  const TransferCapabilities({
    this.backgroundExecution = false,
    this.pauseResume = true,
    this.notifications = false,
    this.notificationActions = false,
  });

  final bool backgroundExecution;
  final bool pauseResume;
  final bool notifications;
  final bool notificationActions;
}
