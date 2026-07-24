import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:transfer_manager/transfer_manager.dart';

void main() {
  late HttpServer server;
  late Uri baseUri;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUri = Uri.parse('http://${server.address.host}:${server.port}');
  });

  tearDown(() => server.close(force: true));

  test('reconciles offset and retries only the failed TUS chunk', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-tus-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/payload.bin');
    final payload = utf8.encode('abcdefghijkl');
    await source.writeAsBytes(payload);

    var offset = 0;
    var creations = 0;
    var patchCalls = 0;
    final received = <int>[];

    server.listen((request) async {
      if (request.method == 'POST' && request.uri.path == '/files') {
        creations++;
        expect(request.headers.value('Tus-Resumable'), '1.0.0');
        expect(request.headers.value('Upload-Length'), '${payload.length}');
        request.response
          ..statusCode = HttpStatus.created
          ..headers.set(HttpHeaders.locationHeader, '/uploads/one')
          ..headers.set('Upload-Offset', '0');
      } else if (request.method == 'HEAD') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set('Tus-Resumable', '1.0.0')
          ..headers.set('Upload-Offset', '$offset');
      } else if (request.method == 'PATCH') {
        patchCalls++;
        expect(request.headers.value('Upload-Offset'), '$offset');
        final body = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        if (patchCalls == 2) {
          request.response.statusCode = HttpStatus.internalServerError;
        } else {
          received.addAll(body);
          offset += body.length;
          request.response
            ..statusCode = HttpStatus.noContent
            ..headers.set('Upload-Offset', '$offset');
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    final manager = TransferManager(
      configuration: const TransferConfiguration(
        defaultRetryPolicy: RetryPolicy.exponential(
          maxAttempts: 2,
          initialDelay: Duration.zero,
          maximumDelay: Duration.zero,
          jitter: false,
        ),
      ),
    );
    addTearDown(manager.close);
    await manager.initialize();
    final task = await manager.enqueue(
      TusUploadRequest(
        sourcePath: source.path,
        endpoint: baseUri.resolve('/files'),
        chunkSize: 4,
      ),
    );
    await _completed(task);

    expect(creations, 1);
    expect(patchCalls, 4);
    expect(offset, payload.length);
    expect(received, payload);
  });

  test('refreshes authentication when TUS creation returns 401', () async {
    final directory = await Directory.systemTemp.createTemp('transfer-auth-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/small.bin');
    await source.writeAsString('data');
    var offset = 0;
    var unauthorized = 0;

    server.listen((request) async {
      final authorization = request.headers.value(
        HttpHeaders.authorizationHeader,
      );
      if (authorization != 'Bearer fresh') {
        unauthorized++;
        request.response.statusCode = HttpStatus.unauthorized;
      } else if (request.method == 'POST') {
        request.response
          ..statusCode = HttpStatus.created
          ..headers.set(HttpHeaders.locationHeader, '/uploads/auth')
          ..headers.set('Upload-Offset', '0');
      } else if (request.method == 'HEAD') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set('Upload-Offset', '$offset');
      } else if (request.method == 'PATCH') {
        final body = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        offset += body.length;
        request.response
          ..statusCode = HttpStatus.noContent
          ..headers.set('Upload-Offset', '$offset');
      }
      await request.response.close();
    });

    final auth = _AuthProvider();
    final manager = TransferManager(authProvider: auth);
    addTearDown(manager.close);
    await manager.initialize();
    final task = await manager.enqueue(
      TusUploadRequest(
        sourcePath: source.path,
        endpoint: baseUri.resolve('/files'),
        authScope: 'user',
        chunkSize: 2,
      ),
    );
    await _completed(task);

    expect(unauthorized, 1);
    expect(auth.refreshes, 1);
    expect(offset, 4);
  });

  test('restores a persisted TUS session without creating a new one', () async {
    final directory = await Directory.systemTemp.createTemp(
      'transfer-restore-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/restore.bin');
    final payload = utf8.encode('abcdefghijkl');
    await source.writeAsBytes(payload);
    var offset = 4;
    var creations = 0;
    final received = <int>[];

    server.listen((request) async {
      if (request.method == 'POST') {
        creations++;
        request.response.statusCode = HttpStatus.created;
      } else if (request.method == 'HEAD') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.set('Upload-Offset', '$offset');
      } else if (request.method == 'PATCH') {
        expect(request.headers.value('Upload-Offset'), '$offset');
        final body = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        received.addAll(body);
        offset += body.length;
        request.response
          ..statusCode = HttpStatus.noContent
          ..headers.set('Upload-Offset', '$offset');
      }
      await request.response.close();
    });

    final storage = InMemoryTransferStorage();
    await storage.save(
      TransferRecord(
        id: 'restored-tus',
        request: TusUploadRequest(
          sourcePath: source.path,
          endpoint: baseUri.resolve('/files'),
          chunkSize: 4,
        ),
        state: TransferState.running,
        bytesTransferred: 4,
        totalBytes: payload.length,
        protocolMetadata: {
          'tus.sessionUrl': baseUri.resolve('/uploads/restored').toString(),
          'tus.offset': 4,
        },
      ),
    );

    final manager = TransferManager(storage: storage);
    addTearDown(manager.close);
    await manager.initialize();
    await _completed(manager.task('restored-tus')!);

    expect(creations, 0);
    expect(received, payload.skip(4));
    expect(offset, payload.length);
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

final class _AuthProvider implements TransferAuthProvider {
  int refreshes = 0;
  bool refreshed = false;

  @override
  Future<Map<String, String>> headersFor(TransferAuthContext context) async => {
    HttpHeaders.authorizationHeader: refreshed ? 'Bearer fresh' : 'Bearer old',
  };

  @override
  Future<Map<String, String>> refreshHeaders(
    TransferAuthContext context,
  ) async {
    refreshes++;
    refreshed = true;
    return {HttpHeaders.authorizationHeader: 'Bearer fresh'};
  }
}
