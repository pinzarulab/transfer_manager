## 0.4.0

- Added the federated platform-interface and Android implementation packages.
- Added WorkManager background downloads, foreground progress notifications,
  constraints, cancellation, task reconnection, and a core-engine adapter.
- Added completion notifications with secure open-file actions.
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
