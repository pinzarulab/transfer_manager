# Roadmap

## 0.1 — foreground core (this repository)

- Unified task and state model
- Persistent queue and restart restoration
- HTTP range downloads and multipart uploads
- Retry, auth refresh, checksum verification, progress and ETA

## 0.5 — Android durability

- Managed upload staging
- WorkManager plus foreground service
- Native notification actions
- Connectivity constraints and process-death tests

## 1.0 — mobile background engine

- iOS background URLSession and relaunch reconciliation
- Android/iOS capability adapters
- TUS resumable uploads
- SQLite migrations and retention policies
- Optional Flutter widget package

## Later

- S3 multipart, task groups, bandwidth limits, desktop adapters, reduced web
  support, and optional Live Activities

The 1.0 acceptance bar includes multi-gigabyte streaming, atomic completion,
restart and connectivity recovery, token renewal, chunk-level retry where the
protocol supports it, corruption detection, and zero persisted auth secrets.

