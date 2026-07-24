# transfer_manager_android

Android implementation of the `transfer_manager` platform contract.

The initial native milestone supports durable HTTP downloads through
WorkManager, foreground progress notifications, network constraints, task
reconnection, atomic `.part` completion, and cancellation. Capabilities report
background uploads and pause/resume as unsupported until those paths are
implemented.

## Core integration

```dart
final manager = TransferManager(
  engines: [
    AndroidBackgroundDownloadEngine(),
    TusTransferEngine(),
    HttpTransferEngine(),
  ],
);
await manager.initialize();
```

The engine maps the existing `DownloadRequest` and task identifier to durable
native work, reconnects after Dart or Android process recreation, and forwards
native progress into the core task event stream.

Partial files are resumed with `Range` and a persisted `ETag` or
`Last-Modified` validator in `If-Range`, preventing a changed remote resource
from being appended to stale bytes.

After a successful download, Android posts a separate completion notification
even when the Flutter application is currently visible. Tapping it opens the
downloaded file through a non-exported `FileProvider` with a temporary
read-only URI grant. Destinations must be within app storage or shared external
storage so they can be exposed safely.

On Android 13 and newer, the host application must request
`POST_NOTIFICATIONS` at runtime. The permission is declared by this plugin, but
Android does not allow a library to display notifications after the user has
denied that permission.

```dart
final android = TransferManagerAndroid();
if (!await android.notificationsEnabled()) {
  final granted = await android.requestNotificationPermission();
  // Continue without notifications if the user declines.
}
```

Short-lived authorization and cookie headers are rejected because WorkManager
persists its input data. Public or presigned download URLs are supported in
this milestone.
