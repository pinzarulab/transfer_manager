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
