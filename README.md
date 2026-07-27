# transfer_manager

A protocol-aware transfer engine for Dart and Flutter. It provides one task
model for uploads and downloads, a persistent queue, retries, progress and ETA,
authentication renewal, integrity verification, and pluggable execution
engines.

This repository contains the **0.5 transfer core** and the first federated
Android packages. Android background downloads, multipart uploads, and
resumable TUS uploads are available as explicit WorkManager engines.
Pause/resume notification actions, iOS background URLSession, S3 multipart,
and Flutter widgets remain future milestones.

## What works

- Streamed HTTP multipart uploads
- TUS 1.0 uploads with persisted sessions and resumable chunks
- HTTP downloads with `.part` files, `Range` and `If-Range`
- Pause, resume, cancel, manual retry, and exponential automatic retry
- Global, upload/download, and per-host concurrency limits
- Priority ordering with FIFO inside one priority
- Atomic download completion
- SHA-256, SHA-512, and compatibility-only MD5 verification
- Fresh auth headers and single-flight refresh after HTTP 401
- In-memory storage and atomic JSON-file persistence
- Authorization and cookie header redaction in persisted records
- Atomic managed-source staging for uploads that must survive cache eviction
- Throttled progress with exponentially smoothed speed and ETA
- Android WorkManager downloads with foreground progress notifications
- Android WorkManager multipart uploads with managed-source integration
- Android WorkManager TUS uploads with persistent sessions and chunk resumption

## Android background downloads

The Android implementation is split into
`transfer_manager_platform_interface` and `transfer_manager_android`. Add the
Android engine before the foreground HTTP fallback:

```dart
final manager = TransferManager(
  engines: [
    AndroidBackgroundDownloadEngine(),
    AndroidBackgroundTusUploadEngine(),
    AndroidBackgroundUploadEngine(),
    TusTransferEngine(),
    HttpTransferEngine(),
  ],
);
```

The current Android capability set includes persistent background downloads,
unmetered-network constraints, process-restart task reconnection, progress
notifications, notification cancellation, range resumption, and atomic
completion. Persisted `ETag`/`Last-Modified` validators protect resumed files
from remote-resource changes. Successful downloads post a completion
notification—even while the app is visible—and tapping it opens the file using
a temporary `FileProvider` permission. Multipart uploads can also run in
WorkManager; retrying them restarts the request. Native TUS uploads persist the
server-created URL and acknowledged offset, then reconcile and continue in
bounded chunks after retries or process restarts. Native pause/resume is still
unsupported.

On Android 13+, call
`TransferManagerAndroid().requestNotificationPermission()` from a visible
screen before expecting progress or completion notifications.

Authorization and cookie headers are rejected by the Android worker because
WorkManager persists its input. Authenticated background transfers require a
future native credential-provider contract rather than storing access tokens.

## Quick start

```dart
import 'dart:io';
import 'package:transfer_manager/transfer_manager.dart';

Future<void> main() async {
  final manager = TransferManager(
    storage: JsonFileTransferStorage(File('.transfers/tasks.json')),
    configuration: const TransferConfiguration(maxConcurrentTasks: 3),
  );
  await manager.initialize();

  final task = await manager.enqueue(
    DownloadRequest(
      source: Uri.parse('https://example.com/report.pdf'),
      destinationPath: 'downloads/report.pdf',
      checksum: Checksum.sha256,
      expectedChecksum: 'hex digest supplied by the server',
    ),
  );

  task.events.listen((event) {
    print('${event.state}: ${event.progress.fraction}');
  });
}
```

For a resumable upload, point `TusUploadRequest` at the server's TUS creation
endpoint. The engine records the returned upload URL and reconciles
`Upload-Offset` before resuming:

```dart
final task = await manager.enqueue(
  TusUploadRequest(
    sourcePath: 'videos/large.mp4',
    endpoint: Uri.parse('https://uploads.example.com/files'),
    chunkSize: 8 * 1024 * 1024,
    metadata: const {'contentType': 'video/mp4'},
    authScope: 'current-user',
  ),
);
```

Use `authScope` to persist an opaque credential lookup key. Do not put
short-lived credentials in request headers. A `TransferAuthProvider` is asked
for fresh headers immediately before execution and again after a 401.

Uploads selected from a cache or temporary picker location can be staged before
enqueueing. The original remains untouched, while the managed copy is retained
after failure and removed after completion or cancellation:

```dart
final manager = TransferManager(
  configuration: const TransferConfiguration(
    managedStoragePath: '/app-support/transfer_manager',
  ),
);

await manager.enqueue(
  UploadRequest(
    sourcePath: '/temporary-picker/video.mp4',
    destination: Uri.parse('https://example.com/upload'),
    sourcePolicy: UploadSourcePolicy.copyToManagedStorage,
  ),
);
```

## Persistence and recovery

Every meaningful transition is saved before its event is emitted. On
initialization, tasks interrupted in `queued`, `preparing`, `running`,
`retryWaiting`, or `verifying` are returned to the queue. Downloads retain
their `.part` file and continue with an HTTP range request when supported.

The bundled JSON store is intentionally simple and atomically replaces its
database file. Production Flutter integrations can implement `TransferStorage`
with SQLite without changing the manager API.

## Platform boundary

The federated platform interface reports each native engine independently.
Android currently advertises durable background downloads, multipart uploads,
TUS uploads, notifications, and notification cancellation. Future platform
packages should report only the capabilities they actually support.

See [ROADMAP.md](ROADMAP.md) for the staged path to the full federated plugin.
