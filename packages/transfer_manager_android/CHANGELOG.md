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
