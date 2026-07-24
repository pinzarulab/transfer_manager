import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_manager/transfer_manager.dart';

void main() {
  test('JSON storage round trips records and redacts secrets', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-store-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/tasks.json');
    final storage = JsonFileTransferStorage(file);
    await storage.initialize();
    await storage.save(
      TransferRecord(
        id: 'one',
        request: DownloadRequest(
          source: Uri.parse('https://example.com/file'),
          destinationPath: '${directory.path}/file',
          authScope: 'account-42',
          headers: const {
            'X-Safe': 'yes',
            'Authorization': 'Bearer secret',
            'Cookie': 'session=secret',
          },
        ),
        state: TransferState.running,
        bytesTransferred: 12,
      ),
    );

    final raw = jsonDecode(await file.readAsString()) as List<Object?>;
    final request =
        (raw.single! as Map<String, Object?>)['request']!
            as Map<String, Object?>;
    expect(request['headers'], {'X-Safe': 'yes'});

    final reopened = JsonFileTransferStorage(file);
    await reopened.initialize();
    final restored = (await reopened.loadAll()).single;
    expect(restored.state, TransferState.running);
    expect(restored.bytesTransferred, 12);
    expect(restored.request.authScope, 'account-42');
  });

  test('JSON storage round trips a TUS request and session metadata', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-tus-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/tasks.json');
    final storage = JsonFileTransferStorage(file);
    await storage.initialize();
    await storage.save(
      TransferRecord(
        id: 'tus-one',
        request: TusUploadRequest(
          sourcePath: '${directory.path}/video.mp4',
          endpoint: Uri.parse('https://uploads.example.com/files'),
          chunkSize: 1024,
          metadata: const {'kind': 'video'},
        ),
        state: TransferState.paused,
        protocolMetadata: const {
          'tus.sessionUrl': 'https://uploads.example.com/files/42',
          'tus.offset': 2048,
        },
      ),
    );

    final reopened = JsonFileTransferStorage(file);
    await reopened.initialize();
    final record = (await reopened.loadAll()).single;
    final request = record.request as TusUploadRequest;

    expect(request.chunkSize, 1024);
    expect(request.metadata, {'kind': 'video'});
    expect(record.protocolMetadata['tus.offset'], 2048);
  });
}
