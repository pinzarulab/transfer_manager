# transfer_manager

A protocol-aware transfer engine for Dart and Flutter. It provides one task
model for uploads and downloads, a persistent queue, retries, progress and ETA,
authentication renewal, integrity verification, and pluggable execution
engines.

This repository currently contains the **0.1 foreground core**. It does not
claim native background execution: Android WorkManager/foreground service,
iOS background URLSession, notifications, TUS, S3 multipart, and Flutter
widgets belong in federated packages built on the contracts exposed here.

## What works

- Streamed HTTP multipart uploads
- HTTP downloads with `.part` files, `Range` and `If-Range`
- Pause, resume, cancel, manual retry, and exponential automatic retry
- Global, upload/download, and per-host concurrency limits
- Priority ordering with FIFO inside one priority
- Atomic download completion
- SHA-256, SHA-512, and compatibility-only MD5 verification
- Fresh auth headers and single-flight refresh after HTTP 401
- In-memory storage and atomic JSON-file persistence
- Authorization and cookie header redaction in persisted records
- Throttled progress with exponentially smoothed speed and ETA

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

Use `authScope` to persist an opaque credential lookup key. Do not put
short-lived credentials in request headers. A `TransferAuthProvider` is asked
for fresh headers immediately before execution and again after a 401.

## Persistence and recovery

Every meaningful transition is saved before its event is emitted. On
initialization, tasks interrupted in `queued`, `preparing`, `running`,
`retryWaiting`, or `verifying` are returned to the queue. Downloads retain
their `.part` file and continue with an HTTP range request when supported.

The bundled JSON store is intentionally simple and atomically replaces its
database file. Production Flutter integrations can implement `TransferStorage`
with SQLite without changing the manager API.

## Platform boundary

`platformCapabilities` currently reports foreground-only behavior. Native
packages should provide durable OS task identifiers, lifecycle reconnection,
network/charging constraints, and notifications, then report only the
capabilities actually supported on that platform.

See [ROADMAP.md](ROADMAP.md) for the staged path to the full federated plugin.

