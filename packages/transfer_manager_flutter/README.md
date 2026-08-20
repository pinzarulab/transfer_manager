# transfer_manager_flutter

Zero-configuration Android/iOS facade for `transfer_manager`. It configures
durable storage, Android WorkManager, iOS background URLSession, retry
fallbacks, completion notifications, notification taps, and artifact actions.

## Installation

```yaml
dependencies:
  transfer_manager_flutter: ^2.0.1
```

## Setup

Initialize Flutter before creating the manager. Keep one manager for the app
lifetime.

```dart
import 'dart:async';

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
  notification: const TransferNotification(
    title: 'Report downloaded',
    showProgress: true,
    allowPause: true,
    allowCancel: true,
  ),
);
```

Default downloads use Android MediaStore Downloads and iOS Documents exposed
through Files. Use `TransferDestination.file(path)` for an explicit path.

Listen for notification taps while the app is running and recover the tap that
launched a stopped app:

```dart
final tapSubscription = transfers.notificationTaps.listen((tap) {
  unawaited(transfers.task(tap.taskId)?.open());
});

final initialTap = await transfers.takeInitialNotificationTap();
if (initialTap != null) {
  await transfers.task(initialTap.taskId)?.open();
}
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
