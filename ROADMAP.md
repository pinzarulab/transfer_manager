# Roadmap

## 0.1 — foreground core

- Unified task and state model
- Persistent queue and restart restoration
- HTTP range downloads and multipart uploads
- Retry, auth refresh, checksum verification, progress and ETA

## 0.2 — resumable upload protocol

- TUS 1.0 creation and chunk upload
- Persisted session URL and offset reconciliation
- Chunk retry without restarting the file

## 0.3 — managed upload sources

- Atomic copies into package-managed storage
- Restart-safe persisted source paths
- Safe cleanup and retry retention

## 0.4 — initial Android durability

- Federated Android platform contract
- WorkManager background downloads and foreground notifications
- Streamed multipart background uploads
- Cancellation, constraints, range resumption, and process reconnection

## 0.5 — resumable Android uploads

- Native WorkManager TUS uploads
- Persistent upload URLs, offsets, and source fingerprints
- Chunk streaming and server-offset reconciliation
- Expired-session recreation and completion notifications

## 1.0 — Android durability (this repository)

- Persistent pause/resume notification actions
- Cooperative pause across download, multipart, and TUS workers
- Low-storage download preflight protection
- Physical-device persistence and low-storage instrumentation tests

## Future mobile expansion

- iOS background URLSession and relaunch reconciliation
- SQLite migrations and retention policies
- Optional Flutter widget package

## Later

- S3 multipart, task groups, bandwidth limits, desktop adapters, reduced web
  support, and optional Live Activities

The 1.0 acceptance bar includes multi-gigabyte streaming, atomic completion,
restart and connectivity recovery, token renewal, chunk-level retry where the
protocol supports it, corruption detection, and zero persisted auth secrets.
