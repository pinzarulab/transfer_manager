# transfer_manager_flutter

Zero-configuration Android/iOS facade for `transfer_manager`.

```dart
final transfers = await FlutterTransferManager.create();

final task = await transfers.download(
  Uri.parse('https://example.com/report.pdf'),
  fileName: 'report.pdf',
);

await task.open();
await task.reveal();
```

Default downloads use Android MediaStore Downloads and iOS Documents exposed
through Files. Use `TransferDestination.file(path)` for an explicit path.
