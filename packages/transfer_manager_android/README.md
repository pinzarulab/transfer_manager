# transfer_manager_android

Android implementation of the `transfer_manager` platform contract.

The native milestone supports durable HTTP downloads, streamed multipart
uploads, and resumable TUS uploads through WorkManager. It also provides
foreground progress notifications, network constraints, task reconnection,
atomic `.part` download completion, cancellation, and persistent pause/resume
actions on active notifications.

## Core integration

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
persists its input data. Public or presigned URLs are supported in this
milestone. Multipart upload retries restart the request; TUS uploads persist
their server-created URL and acknowledged offset so retries resume in bounded
chunks.
