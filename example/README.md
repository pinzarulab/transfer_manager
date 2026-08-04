# transfer_manager example

A Flutter example for durable background downloads on Android and iOS.

The app provides three Cloudflare test downloads:

- 1 MB
- 10 MB
- 50 MB

It demonstrates:

- Android WorkManager and iOS background URLSession engines
- persistent task restoration
- progress, pause, resume, retry, and cancel controls
- Android 13+ and iOS notification permission requests
- Android progress notifications
- Android and iOS completion notifications, including while the app is visible
- one-call `FlutterTransferManager.create()` setup
- notification-tap delivery plus `task.open()` and `task.reveal()`

Run it from this directory:

```sh
flutter pub get
flutter run
```

On Android 10 and newer, files are published through MediaStore into the
system Downloads folder, where the user and other apps can access them.
Completion-notification taps open the downloaded file. On iOS, files are
stored in the app's Documents directory and are exposed in the Files app under
On My iPhone (or On My iPad) > Transfer Manager; tapping a completion
notification opens the downloaded document preview.

The public sample payloads come from Cloudflare's documented speed-test
download endpoint and contain generated binary data.
