# transfer_manager_ios

iOS background `URLSession` implementation for `transfer_manager`.

It supports durable downloads and file-backed multipart uploads, native task
reconnection after relaunch, progress events, pause/resume, cancellation, and
completion notifications.

## Live Activities

The plugin starts, updates, restores, and ends download Live Activities. The
host app must contain a Widget Extension because iOS does not allow a Flutter
package to add an app-extension target automatically.

Requirements:

- iOS 16.1+ for progress on the Lock Screen and Dynamic Island.
- iOS 17+ for direct Pause/Resume and Cancel controls.
- Xcode 15+ for the interactive Widget Extension.

The complete extension is
[`example/ios/TransferManagerLiveActivity/TransferManagerLiveActivity.swift`](../../example/ios/TransferManagerLiveActivity/TransferManagerLiveActivity.swift).
It includes `system`, `compact`, `detailed`, and `prominent` presets.

### Host-app setup

1. In Xcode, add a **Widget Extension**, enable **Include Live Activity**, and
   set its deployment target to iOS 16.1.
2. Add the package product `transfer-manager-live-activity-support` to the
   extension target. When using CocoaPods, add the support subspec to the
   extension target:

   ```ruby
   target 'TransferManagerLiveActivity' do
     pod 'transfer_manager_ios/LiveActivitySupport',
       :path => '.symlinks/plugins/transfer_manager_ios/ios'
   end
   ```

3. Copy the example extension Swift file, or use it as a template for a custom
   `ActivityConfiguration(for: TransferLiveActivityAttributes.self)`.
4. Add these values to the application `Info.plist`:

   ```xml
   <key>NSSupportsLiveActivities</key>
   <true/>
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array><string>transfer-manager</string></array>
     </dict>
   </array>
   ```

5. Enable the feature for a download:

   ```dart
   notification: const TransferNotification(
     title: 'Downloading report.pdf',
     showLiveActivity: true,
     liveActivityStyle: LiveActivityStyle.detailed,
     allowPause: true,
     allowCancel: true,
   ),
   ```

The native `LiveActivityIntent` controls the background `URLSession` directly;
it does not wait for Dart or require a running Flutter UI. Open and Reveal
foreground the application through the `transfer-manager` URL scheme, then
present the downloaded file natively.

Active transfers show Pause/Resume and Cancel. Successful transfers replace
those controls with Open and Reveal. iOS may coalesce local progress updates
while the application process is suspended or terminated; the system download
continues, and the activity is reconciled when iOS next delivers URLSession
events. Server-driven ActivityKit push updates are not part of this package.

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
