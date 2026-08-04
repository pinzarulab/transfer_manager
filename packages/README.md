# Federated packages

- `transfer_manager_platform_interface` defines native capabilities, durable
  download requests, task snapshots, event streaming, querying, and
  cancellation.
- `transfer_manager_android` implements that contract with Android WorkManager
  and provides background download, multipart, and TUS engines.
- `transfer_manager_ios` implements background URLSession downloads and
  file-backed multipart uploads with relaunch reconciliation.
- `transfer_manager_flutter` provides one-call Android/iOS setup, durable
  storage, destinations, notification taps, and artifact actions.

The core package remains usable without Flutter. Platform implementations are
separate so future desktop and web packages can evolve without importing
their dependencies into the pure-Dart engine.
