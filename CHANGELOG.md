## 0.2.0

- Added TUS 1.0 resumable uploads.
- Persisted upload session URLs and acknowledged offsets.
- Added server-offset reconciliation across retries and restored tasks.
- Added chunk-level progress, auth refresh, and integrity verification for TUS.

## 0.1.0

- Initial foreground transfer engine.
- Added persistent scheduling, HTTP range downloads, multipart uploads,
  authentication refresh, checksum verification, progress, retry, and tests.
