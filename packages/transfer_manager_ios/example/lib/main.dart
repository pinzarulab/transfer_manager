import 'package:flutter/material.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_ios/transfer_manager_ios.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final manager = TransferManager(
    engines: [
      IosBackgroundDownloadEngine(),
      IosBackgroundUploadEngine(),
      TusTransferEngine(),
      HttpTransferEngine(),
    ],
  );
  await manager.initialize();
  runApp(TransferManagerIosExample(manager: manager));
}

class TransferManagerIosExample extends StatelessWidget {
  const TransferManagerIosExample({required this.manager, super.key});

  final TransferManager manager;

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('transfer_manager iOS integration example')),
      ),
    );
  }
}
