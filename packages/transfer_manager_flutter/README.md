# transfer_manager_flutter

Zero-configuration Android/iOS facade for `transfer_manager`. It configures
durable storage, Android WorkManager, iOS background URLSession, retry
fallbacks, completion notifications, notification taps, and artifact actions.

## Installation

```yaml
dependencies:
  transfer_manager_flutter: ^2.1.2
```

## Setup

Initialize Flutter before creating the manager. Keep one manager for the app
lifetime.

```dart
import 'package:flutter/widgets.dart';
import 'package:transfer_manager_flutter/transfer_manager_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final transfers = await FlutterTransferManager.create(
    requestNotificationPermission: true,
  );

  runApp(MyApp(transfers: transfers));
}
```

Request notification permission from visible UI if you do not request it
during creation:

```dart
if (!await transfers.notificationsEnabled()) {
  await transfers.requestNotificationPermission();
}
```

## Download with completion notification

```dart
final task = await transfers.download(
  Uri.parse('https://example.com/report.pdf'),
  fileName: 'report.pdf',
  showNotification: true,
  openFromNotification: NotificationOpenType.open,
);
```

`NotificationOpenType.open` performs `task.open()` after the user taps the
notification. Use `NotificationOpenType.reveal` to perform `task.reveal()`.
No tap listener or initial-tap handling is needed.

Android performs this action directly from the notification, without waiting
for Flutter application startup. iOS performs it after the UI resumes.
Set `showNotification: false` to suppress the completion notification. Android
may still show required foreground progress while a background download runs.

Default downloads use Android MediaStore Downloads and iOS Documents exposed
through Files. Use `TransferDestination.file(path)` for an explicit path.

Notification taps remain available for optional app-specific handling:

```dart
final tapSubscription = transfers.notificationTaps.listen((tap) {
  appRouter.go('/downloads/${tap.taskId}');
});
```

Completed download tasks can also be opened or revealed directly:

```dart
await task.open();
await task.reveal();
```

Call `close()` when the application-owned manager is no longer needed:

```dart
await tapSubscription.cancel();
await transfers.close();
```
