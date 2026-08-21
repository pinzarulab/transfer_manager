enum PlatformTaskState {
  enqueued,
  running,
  paused,
  succeeded,
  failed,
  cancelled,
  blocked,
  unknown,
}

final class PlatformTransferDestination {
  const PlatformTransferDestination({required this.kind, required this.value});

  final String kind;
  final String value;

  Map<String, Object?> toMap() => {'kind': kind, 'value': value};

  factory PlatformTransferDestination.fromMap(Map<Object?, Object?> map) =>
      PlatformTransferDestination(
        kind: map['kind']! as String,
        value: map['value']! as String,
      );
}

final class PlatformNotificationTap {
  const PlatformNotificationTap({
    required this.taskId,
    this.destination,
    this.actionHandled = false,
  });

  final String taskId;
  final PlatformTransferDestination? destination;

  /// Whether native code already performed the requested artifact action.
  final bool actionHandled;

  factory PlatformNotificationTap.fromMap(Map<Object?, Object?> map) =>
      PlatformNotificationTap(
        taskId: map['taskId']! as String,
        actionHandled: map['actionHandled'] as bool? ?? false,
        destination: map['destination'] is Map<Object?, Object?>
            ? PlatformTransferDestination.fromMap(
                map['destination']! as Map<Object?, Object?>,
              )
            : map['filePath'] is String
            ? PlatformTransferDestination(
                kind: 'file',
                value: map['filePath']! as String,
              )
            : null,
      );
}

final class PlatformTransferCapabilities {
  const PlatformTransferCapabilities({
    required this.backgroundDownloads,
    required this.backgroundUploads,
    this.backgroundTusUploads = false,
    required this.pauseResume,
    required this.notifications,
    required this.notificationCancellation,
    this.notificationTaps = false,
    this.openArtifacts = false,
    this.revealArtifacts = false,
  });

  final bool backgroundDownloads;
  final bool backgroundUploads;
  final bool backgroundTusUploads;
  final bool pauseResume;
  final bool notifications;
  final bool notificationCancellation;
  final bool notificationTaps;
  final bool openArtifacts;
  final bool revealArtifacts;

  factory PlatformTransferCapabilities.fromMap(Map<Object?, Object?> map) =>
      PlatformTransferCapabilities(
        backgroundDownloads: map['backgroundDownloads'] as bool? ?? false,
        backgroundUploads: map['backgroundUploads'] as bool? ?? false,
        backgroundTusUploads: map['backgroundTusUploads'] as bool? ?? false,
        pauseResume: map['pauseResume'] as bool? ?? false,
        notifications: map['notifications'] as bool? ?? false,
        notificationCancellation:
            map['notificationCancellation'] as bool? ?? false,
        notificationTaps: map['notificationTaps'] as bool? ?? false,
        openArtifacts: map['openArtifacts'] as bool? ?? false,
        revealArtifacts: map['revealArtifacts'] as bool? ?? false,
      );
}

final class PlatformDownloadRequest {
  PlatformDownloadRequest({
    required this.taskId,
    required this.source,
    required this.destination,
    this.headers = const {},
    this.networkPolicy = 'any',
    this.notificationTitle = 'Downloading file',
    this.showNotification = true,
    this.notificationOpenType = 'open',
    this.maxAttempts = 5,
  });

  final String taskId;
  final Uri source;
  final PlatformTransferDestination destination;

  final Map<String, String> headers;
  final String networkPolicy;
  final String notificationTitle;

  /// Whether native code should show a completion notification.
  final bool showNotification;

  /// Native action requested when completion notification is tapped.
  final String notificationOpenType;
  final int maxAttempts;

  Map<String, Object?> toMap() => {
    'taskId': taskId,
    'source': source.toString(),
    'destination': destination.toMap(),
    'headers': headers,
    'networkPolicy': networkPolicy,
    'notificationTitle': notificationTitle,
    'showNotification': showNotification,
    'notificationOpenType': notificationOpenType,
    'maxAttempts': maxAttempts,
  };
}

final class PlatformUploadRequest {
  const PlatformUploadRequest({
    required this.taskId,
    required this.sourcePath,
    required this.destination,
    this.method = 'POST',
    this.fieldName = 'file',
    this.headers = const {},
    this.networkPolicy = 'any',
    this.notificationTitle = 'Uploading file',
    this.maxAttempts = 5,
  });

  final String taskId;
  final String sourcePath;
  final Uri destination;
  final String method;
  final String fieldName;
  final Map<String, String> headers;
  final String networkPolicy;
  final String notificationTitle;
  final int maxAttempts;

  Map<String, Object?> toMap() => {
    'taskId': taskId,
    'sourcePath': sourcePath,
    'destination': destination.toString(),
    'method': method,
    'fieldName': fieldName,
    'headers': headers,
    'networkPolicy': networkPolicy,
    'notificationTitle': notificationTitle,
    'maxAttempts': maxAttempts,
  };
}

final class PlatformTusUploadRequest {
  const PlatformTusUploadRequest({
    required this.taskId,
    required this.sourcePath,
    required this.endpoint,
    this.chunkSize = 5 * 1024 * 1024,
    this.metadata = const {},
    this.headers = const {},
    this.networkPolicy = 'any',
    this.notificationTitle = 'Uploading file',
    this.maxAttempts = 5,
  });

  final String taskId;
  final String sourcePath;
  final Uri endpoint;
  final int chunkSize;
  final Map<String, String> metadata;
  final Map<String, String> headers;
  final String networkPolicy;
  final String notificationTitle;
  final int maxAttempts;

  Map<String, Object?> toMap() => {
    'taskId': taskId,
    'sourcePath': sourcePath,
    'endpoint': endpoint.toString(),
    'chunkSize': chunkSize,
    'metadata': metadata,
    'headers': headers,
    'networkPolicy': networkPolicy,
    'notificationTitle': notificationTitle,
    'maxAttempts': maxAttempts,
  };
}

final class PlatformTaskSnapshot {
  const PlatformTaskSnapshot({
    required this.taskId,
    required this.state,
    required this.bytesTransferred,
    this.totalBytes,
    this.error,
  });

  final String taskId;
  final PlatformTaskState state;
  final int bytesTransferred;
  final int? totalBytes;
  final String? error;

  double? get fraction => totalBytes == null || totalBytes == 0
      ? null
      : (bytesTransferred / totalBytes!).clamp(0, 1);

  factory PlatformTaskSnapshot.fromMap(Map<Object?, Object?> map) {
    final stateName = map['state'] as String? ?? 'unknown';
    return PlatformTaskSnapshot(
      taskId: map['taskId']! as String,
      state: PlatformTaskState.values.firstWhere(
        (state) => state.name == stateName,
        orElse: () => PlatformTaskState.unknown,
      ),
      bytesTransferred: map['bytesTransferred'] as int? ?? 0,
      totalBytes: map['totalBytes'] as int?,
      error: map['error'] as String?,
    );
  }
}
