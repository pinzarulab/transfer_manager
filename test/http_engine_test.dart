import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';
import 'package:transfer_manager/transfer_manager.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;
  final payload = utf8.encode('a ranged response used by transfer_manager');

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
  });

  tearDown(() => server.close(force: true));

  test('resumes a partial download and atomically completes it', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-http-');
    addTearDown(() => directory.delete(recursive: true));
    final destination = File('${directory.path}/result.bin');
    final partial = File('${destination.path}.part');
    await partial.writeAsBytes(payload.take(8).toList());

    server.listen((request) async {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=8-');
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.etagHeader, '"v1"')
        ..contentLength = payload.length - 8
        ..add(payload.skip(8).toList());
      await request.response.close();
    });

    final manager = TransferManager();
    addTearDown(manager.close);
    await manager.initialize();
    final task = await manager.enqueue(
      DownloadRequest(
        source: baseUri.resolve('/file'),
        destination: TransferDestination.file(destination.path),
        expectedChecksum: sha256.convert(payload).toString(),
      ),
    );
    await _completed(task);

    expect(await destination.readAsBytes(), payload);
    expect(await partial.exists(), isFalse);
  });

  test('streams a multipart upload', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-upload-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/hello.txt');
    await source.writeAsString('hello upload');
    late List<int> body;

    server.listen((request) async {
      expect(request.headers.contentType?.mimeType, 'multipart/form-data');
      body = await request.fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      request.response.statusCode = HttpStatus.created;
      await request.response.close();
    });

    final manager = TransferManager();
    addTearDown(manager.close);
    await manager.initialize();
    final task = await manager.enqueue(
      UploadRequest(
        sourcePath: source.path,
        destination: baseUri.resolve('/upload'),
      ),
    );
    await _completed(task);

    expect(utf8.decode(body), contains('hello upload'));
  });
}

Future<void> _completed(TransferTask task) async {
  if (task.state == TransferState.completed) return;
  final event = await task.events
      .firstWhere(
        (event) =>
            event.state == TransferState.completed ||
            event.state == TransferState.failed,
      )
      .timeout(const Duration(seconds: 3));
  if (event.state == TransferState.failed) throw event.error!;
}
