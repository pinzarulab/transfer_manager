import 'dart:io';

import 'package:transfer_manager/transfer_manager.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run example/transfer_manager_example.dart URL FILE',
    );
    exitCode = 64;
    return;
  }

  final manager = TransferManager(
    storage: JsonFileTransferStorage(File('.transfers/tasks.json')),
  );
  await manager.initialize();
  final task = await manager.enqueue(
    DownloadRequest(
      source: Uri.parse(arguments[0]),
      destinationPath: arguments[1],
    ),
  );
  await for (final event in task.events) {
    stdout.writeln(
      '${event.state.name} '
      '${event.progress.bytesTransferred}/${event.progress.totalBytes ?? '?'}',
    );
    if ({
      TransferState.completed,
      TransferState.failed,
      TransferState.cancelled,
    }.contains(event.state)) {
      break;
    }
  }
  await manager.close();
}
