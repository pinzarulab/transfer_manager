## 2.1.1

- Perform notification `open` and `reveal` actions directly in Android.
- Keep Dart tap delivery informational after native action succeeds.
- Remove Flutter lifecycle timing dependency from completion notification taps.

## 2.1.0

- Added completion-notification suppression for downloads.
- Forwarded the facade's simplified notification preferences to WorkManager.

## 2.0.2

- Keep notification taps pending until Dart confirms live delivery.
- Prevent notification taps from requiring a hot restart.

## 2.0.1

- Deferred method-channel callback registration until Flutter bindings exist.

## 2.0.0

- Added platform-neutral destination decoding.
- Added warm/cold notification-tap persistence and delivery.
- Added native open and Downloads reveal actions.

## 1.0.0

- Added persistent pause/resume actions to active transfer notifications.
- Added cooperative pause support across download, multipart, and TUS workers.
- Added preflight low-storage protection for downloads.
- Added physical-device persistence and low-storage instrumentation tests.
- Added scoped-storage-safe publishing to the user-visible Downloads
  collection on Android 10 and newer.

## 0.2.0

- Added resumable TUS uploads backed by WorkManager.
- Persisted upload URLs, acknowledged offsets, and source fingerprints.
- Added bounded chunk streaming, offset reconciliation, session recreation,
  progress/completion notifications, and the core TUS engine adapter.

## 0.1.0

- Initial WorkManager-backed background downloads.
- Added foreground notifications, progress events, task queries, network
  constraints, cancellation, and process-restart reconnection.
- Added completion notifications that securely open downloaded files.
- Added streamed multipart background uploads and core `UploadRequest`
  integration.
