# transfer_manager_ios

iOS background `URLSession` implementation for `transfer_manager`.

It supports durable downloads and file-backed multipart uploads, native task
reconnection after relaunch, progress events, pause/resume, cancellation, and
completion notifications.

```dart
final manager = TransferManager(
  engines: [
    IosBackgroundDownloadEngine(),
    IosBackgroundUploadEngine(),
    TusTransferEngine(),
    HttpTransferEngine(),
  ],
);
```

Call `TransferManagerIos().requestNotificationPermission()` from visible UI
before relying on completion notifications.

Notification taps are exposed for both a running application and a cold
launch:

```dart
final ios = TransferManagerIos();

ios.notificationResponses.listen((response) {
  // Navigate to response.filePath.
});

final initial = await ios.takeInitialNotificationResponse();
if (initial != null) {
  // The notification launched the application.
}
```

iOS does not provide a supported deep link that reveals an arbitrary folder
inside the Files app. Applications should navigate to their own file browser
or present the file with Quick Look.

Native background TUS is not advertised; `TusTransferEngine` remains the
foreground fallback on iOS.
