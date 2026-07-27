import 'package:flutter/material.dart';
import 'package:transfer_manager/transfer_manager.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TransferManagerAndroid.registerWith();
  final manager = TransferManager(
    engines: [
      AndroidBackgroundDownloadEngine(),
      AndroidBackgroundUploadEngine(),
      TusTransferEngine(),
      HttpTransferEngine(),
    ],
  );
  await manager.initialize();
  runApp(TransferExample(manager: manager));
}

class TransferExample extends StatelessWidget {
  const TransferExample({required this.manager, super.key});

  final TransferManager manager;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: const Center(
          child: Text('transfer_manager Android integration example'),
        ),
      ),
    );
  }
}
