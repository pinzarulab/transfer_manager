## 1.5.0

- Added the federated `transfer_manager_ios` package.
- Added iOS background URLSession downloads and file-backed multipart uploads.
- Added iOS relaunch reconciliation, native pause/resume, cancellation,
  bounded retries, progress events, and completion notifications.
- Added CocoaPods and Swift Package Manager integration with a privacy manifest.
- Added a complete Android/iOS Flutter download example with notification
  permission handling, progress, and task controls.
- Added MediaStore-backed Android Downloads destinations and iOS Files-app
  access for example downloads.
- Added iOS notification-tap delivery for running and cold-launched apps.

## 1.0.0

- Added persistent Android pause/resume controls to active transfer
  notifications for downloads, multipart uploads, and TUS uploads.
- Added native pause/resume methods and paused task snapshots to the federated
  platform contract.
- Added preflight low-storage protection for background downloads.
- Added physical-device instrumentation coverage for persistent restoration
  state and low-storage failures.

## 0.5.0

- Added native Android resumable TUS uploads through WorkManager.
- Persisted native TUS session URLs, acknowledged offsets, and source
  fingerprints across retries and process restarts.
- Added bounded chunk streaming, server-offset reconciliation, expired-session
  recreation, source-change protection, and completion notifications.
- Added the Android background TUS engine adapter and platform capability.

## 0.4.0

- Added the federated platform-interface and Android implementation packages.
- Added WorkManager background downloads, foreground progress notifications,
  constraints, cancellation, task reconnection, and a core-engine adapter.
- Added completion notifications with secure open-file actions.
- Added streamed multipart background uploads through WorkManager.
- Exposed a pause signal for custom transfer engines.

## 0.3.0

- Implemented atomic managed-source staging for persistent uploads.
- Added safe managed-file cleanup after completion or cancellation.
- Retained managed sources after failures so tasks remain retryable.
- Added restart recovery for staged upload sources.

## 0.2.0

- Added TUS 1.0 resumable uploads.
- Persisted upload session URLs and acknowledged offsets.
- Added server-offset reconciliation across retries and restored tasks.
- Added chunk-level progress, auth refresh, and integrity verification for TUS.

## 0.1.0

- Initial foreground transfer engine.
- Added persistent scheduling, HTTP range downloads, multipart uploads,
  authentication refresh, checksum verification, progress, retry, and tests.
