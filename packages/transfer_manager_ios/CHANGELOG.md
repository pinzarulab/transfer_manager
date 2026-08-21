## 2.1.1

- Keep notification taps pending until Dart acknowledges live delivery.
- Recover taps that arrive while Flutter UI is still resuming.

## 2.1.0

- Added completion-notification suppression for downloads.
- Persisted notification visibility across background URLSession retries.

## 2.0.2

- Deliver live notification taps synchronously to the Flutter facade before
  acknowledging the native callback.

## 2.0.1

- Fixed plugin registration before Flutter's binary messenger initializes.
- Deferred notification-tap callback registration until first use.

## 2.0.0

- Added platform-neutral destination decoding and notification taps.
- Added native document preview and reveal actions.

## 1.5.0

- Initial background URLSession implementation for downloads and multipart
  uploads.
- Added relaunch reconciliation, progress events, pause/resume, cancellation,
  and completion notifications.
- Added warm-app and cold-launch completion-notification tap responses.
