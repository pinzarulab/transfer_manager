## 2.1.1

- Recover pending notification taps whenever application resumes.
- Deduplicate warm and persisted delivery of same tap.
- Wait for resumed UI and retry automatic `open()` or `reveal()` actions.

## 2.1.0

- Added `showNotification` and `openFromNotification` download options.
- Automatically opens or reveals completed files after notification taps.
- Automatically recovers cold-start notification taps; normal file-opening
  flows no longer need tap listeners or initial-tap handling.

## 2.0.2

- Buffer notification taps while the app is paused and deliver them after the
  Flutter UI resumes.
- Schedule a frame before delivering live taps, removing the hot-restart
  requirement.
- Allow native artifact validation to resolve the completion-state race when
  opening a freshly downloaded file.

## 2.0.1

- Updated federated dependencies for safe pre-binding plugin registration.

## 2.0.0

- Initial convenience facade with automatic platform engines, durable storage,
  notification taps, destinations, and artifact actions.
