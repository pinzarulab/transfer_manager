# Federated packages

- `transfer_manager_platform_interface` defines native capabilities, durable
  download requests, task snapshots, event streaming, querying, and
  cancellation.
- `transfer_manager_android` implements that contract with Android WorkManager
  and provides `AndroidBackgroundDownloadEngine` for the core scheduler.

The core package remains usable without Flutter. Platform implementations are
separate so future iOS, desktop, and web packages can evolve without importing
their dependencies into the pure-Dart engine.

