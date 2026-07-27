enum PlatformTaskState {
  enqueued,
  running,
  succeeded,
  failed,
  cancelled,
  blocked,
  unknown,
}

final class PlatformTransferCapabilities {
  const PlatformTransferCapabilities({
    required this.backgroundDownloads,
    required this.backgroundUploads,
    required this.pauseResume,
    required this.notifications,
    required this.notificationCancellation,
  });

  final bool backgroundDownloads;
  final bool backgroundUploads;
  final bool pauseResume;
  final bool notifications;
  final bool notificationCancellation;

  factory PlatformTransferCapabilities.fromMap(Map<Object?, Object?> map) =>
      PlatformTransferCapabilities(
        backgroundDownloads: map['backgroundDownloads'] as bool? ?? false,
        backgroundUploads: map['backgroundUploads'] as bool? ?? false,
        pauseResume: map['pauseResume'] as bool? ?? false,
        notifications: map['notifications'] as bool? ?? false,
        notificationCancellation:
            map['notificationCancellation'] as bool? ?? false,
      );
}

final class PlatformDownloadRequest {
  const PlatformDownloadRequest({
    required this.taskId,
    required this.source,
    required this.destinationPath,
    this.headers = const {},
    this.networkPolicy = 'any',
    this.notificationTitle = 'Downloading file',
    this.maxAttempts = 5,
  });

  final String taskId;
  final Uri source;
  final String destinationPath;
  final Map<String, String> headers;
  final String networkPolicy;
  final String notificationTitle;
  final int maxAttempts;

  Map<String, Object?> toMap() => {
    'taskId': taskId,
    'source': source.toString(),
    'destinationPath': destinationPath,
    'headers': headers,
    'networkPolicy': networkPolicy,
    'notificationTitle': notificationTitle,
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
