import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;

import 'auth.dart';
import 'exceptions.dart';
import 'models.dart';

typedef ProgressCallback =
    FutureOr<void> Function(int bytesTransferred, int? totalBytes);

final class TransferControl {
  bool _pauseRequested = false;
  bool _cancelRequested = false;

  bool get pauseRequested => _pauseRequested;
  bool get cancelRequested => _cancelRequested;

  void pause() => _pauseRequested = true;
  void cancel() => _cancelRequested = true;
}

final class TransferExecutionContext {
  const TransferExecutionContext({
    required this.record,
    required this.control,
    required this.onProgress,
    this.authProvider,
  });

  final TransferRecord record;
  final TransferControl control;
  final ProgressCallback onProgress;
  final TransferAuthProvider? authProvider;
}

abstract interface class TransferEngine {
  bool supports(TransferRequest request);
  Future<void> execute(TransferExecutionContext context);
}

/// Foreground HTTP engine with range downloads and streamed multipart uploads.
final class HttpTransferEngine implements TransferEngine {
  HttpTransferEngine({HttpClient? client}) : _client = client ?? HttpClient();

  final HttpClient _client;

  @override
  bool supports(TransferRequest request) =>
      request is DownloadRequest || request is UploadRequest;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    final request = context.record.request;
    if (request is DownloadRequest) {
      await _download(request, context);
    } else if (request is UploadRequest) {
      await _upload(request, context);
    } else {
      throw TransferProtocolException(
        'No HTTP implementation for ${request.runtimeType}',
      );
    }
  }

  Future<Map<String, String>> _headers(
    TransferExecutionContext context, {
    bool refresh = false,
  }) async {
    final request = context.record.request;
    final headers = Map<String, String>.of(request.headers);
    final provider = context.authProvider;
    if (provider != null) {
      final authContext = TransferAuthContext(
        taskId: context.record.id,
        uri: request.remoteUri,
        type: request.type,
        scope: request.authScope,
      );
      headers.addAll(
        refresh
            ? await provider.refreshHeaders(authContext)
            : await provider.headersFor(authContext),
      );
    }
    return headers;
  }

  Future<HttpClientResponse> _send(
    TransferExecutionContext context,
    Future<HttpClientRequest> Function(Map<String, String> headers) build,
  ) async {
    var response = await (await build(await _headers(context))).close();
    if (response.statusCode == HttpStatus.unauthorized &&
        context.authProvider != null) {
      await response.drain<void>();
      response = await (await build(
        await _headers(context, refresh: true),
      )).close();
    }
    return response;
  }

  Future<void> _download(
    DownloadRequest request,
    TransferExecutionContext context,
  ) async {
    final destination = File(request.destinationPath);
    final partial = File('${request.destinationPath}.part');
    await destination.parent.create(recursive: true);

    if (await destination.exists()) {
      switch (request.existingFilePolicy) {
        case ExistingFilePolicy.fail:
          throw TransferStorageException(
            'Destination already exists: ${destination.path}',
          );
        case ExistingFilePolicy.keepExisting:
          await context.onProgress(
            await destination.length(),
            await destination.length(),
          );
          return;
        case ExistingFilePolicy.rename:
          throw const TransferStorageException(
            'Rename policy requires destination selection by the caller',
          );
        case ExistingFilePolicy.replace:
          await destination.delete();
        case ExistingFilePolicy.resume:
          await destination.delete();
      }
    }

    var offset =
        request.resumeMode == ResumeMode.never || !await partial.exists()
        ? 0
        : await partial.length();
    final savedEtag = context.record.protocolMetadata['etag'] as String?;

    Future<HttpClientRequest> build(Map<String, String> headers) async {
      final outbound = await _client.getUrl(request.source);
      headers.forEach(outbound.headers.set);
      if (offset > 0) {
        outbound.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        if (savedEtag != null) {
          outbound.headers.set(HttpHeaders.ifRangeHeader, savedEtag);
        }
      }
      return outbound;
    }

    final response = await _send(context, build);
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw _httpFailure(response.statusCode, request.source);
    }
    final resumed = response.statusCode == HttpStatus.partialContent;
    if (offset > 0 && !resumed) {
      if (request.resumeMode == ResumeMode.required) {
        await response.drain<void>();
        throw const TransferProtocolException(
          'Server does not support the required ranged download',
        );
      }
      offset = 0;
    }

    final etag = response.headers.value(HttpHeaders.etagHeader);
    if (etag != null) context.record.protocolMetadata['etag'] = etag;
    final responseLength = response.contentLength;
    final total = responseLength < 0 ? null : offset + responseLength;
    final sink = partial.openWrite(
      mode: resumed ? FileMode.append : FileMode.write,
    );
    var received = offset;
    try {
      await for (final chunk in response) {
        _checkControl(context.control);
        sink.add(chunk);
        received += chunk.length;
        await context.onProgress(received, total);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    _checkControl(context.control);

    if (total != null && received != total) {
      throw TransferNetworkException(
        'Download ended at $received of $total bytes',
      );
    }
    await _verify(partial, request.checksum, request.expectedChecksum);
    await partial.rename(destination.path);
  }

  Future<void> _upload(
    UploadRequest request,
    TransferExecutionContext context,
  ) async {
    final source = File(request.sourcePath);
    if (!await source.exists()) {
      throw TransferSourceMissingException(
        'Upload source does not exist: ${source.path}',
      );
    }
    final length = await source.length();
    final boundary =
        'transfer-manager-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    final name = Uri.file(source.path).pathSegments.last;
    final prefix = utf8.encode(
      '--$boundary\r\n'
      'Content-Disposition: form-data; name="${request.fieldName}"; '
      'filename="$name"\r\n'
      'Content-Type: application/octet-stream\r\n\r\n',
    );
    final suffix = utf8.encode('\r\n--$boundary--\r\n');

    Future<HttpClientRequest> build(Map<String, String> headers) async {
      final outbound = await _client.openUrl(
        request.method,
        request.destination,
      );
      headers.forEach(outbound.headers.set);
      outbound.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      outbound.contentLength = prefix.length + length + suffix.length;
      outbound.add(prefix);
      var sent = 0;
      await for (final chunk in source.openRead()) {
        _checkControl(context.control);
        outbound.add(chunk);
        sent += chunk.length;
        await context.onProgress(sent, length);
      }
      outbound.add(suffix);
      return outbound;
    }

    final response = await _send(context, build);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw _httpFailure(response.statusCode, request.destination);
    }
    await response.drain<void>();
    _checkControl(context.control);
    if (request.expectedChecksum != null) {
      await _verify(source, request.checksum, request.expectedChecksum);
    }
  }

  TransferException _httpFailure(int status, Uri uri) {
    if (status == HttpStatus.requestTimeout ||
        status == HttpStatus.tooManyRequests ||
        status >= 500) {
      return TransferServerException(
        'HTTP $status from ${uri.host}',
        statusCode: status,
        retryable: true,
      );
    }
    if (status == HttpStatus.unauthorized) {
      return const TransferAuthenticationException(
        'Authentication failed after credential refresh',
      );
    }
    return TransferServerException(
      'HTTP $status from ${uri.host}',
      statusCode: status,
    );
  }

  Future<void> _verify(File file, Checksum? checksum, String? expected) async {
    if (expected == null) return;
    final algorithm = checksum?.algorithm ?? ChecksumAlgorithm.sha256;
    final digest = switch (algorithm) {
      ChecksumAlgorithm.sha256 =>
        await crypto.sha256.bind(file.openRead()).first,
      ChecksumAlgorithm.sha512 =>
        await crypto.sha512.bind(file.openRead()).first,
      ChecksumAlgorithm.md5 => await crypto.md5.bind(file.openRead()).first,
    };
    if (digest.toString().toLowerCase() != expected.toLowerCase()) {
      throw TransferIntegrityException(
        'Expected $expected but received $digest',
      );
    }
  }

  void close() => _client.close(force: true);
}

/// TUS 1.0 client with persisted session URLs and server-offset reconciliation.
final class TusTransferEngine implements TransferEngine {
  TusTransferEngine({HttpClient? client}) : _client = client ?? HttpClient();

  static const _version = '1.0.0';
  static const _sessionUrlKey = 'tus.sessionUrl';
  static const _offsetKey = 'tus.offset';
  static const _sourceLengthKey = 'tus.sourceLength';
  static const _sourceModifiedKey = 'tus.sourceModified';

  final HttpClient _client;

  @override
  bool supports(TransferRequest request) => request is TusUploadRequest;

  @override
  Future<void> execute(TransferExecutionContext context) async {
    final request = context.record.request;
    if (request is! TusUploadRequest) {
      throw TransferProtocolException(
        'TUS engine cannot execute ${request.runtimeType}',
      );
    }
    final source = File(request.sourcePath);
    if (!await source.exists()) {
      throw TransferSourceMissingException(
        'Upload source does not exist: ${source.path}',
      );
    }
    final length = await source.length();
    final modified = (await source.lastModified()).toUtc().toIso8601String();
    final storedLength =
        context.record.protocolMetadata[_sourceLengthKey] as int?;
    final storedModified =
        context.record.protocolMetadata[_sourceModifiedKey] as String?;
    if (context.record.protocolMetadata.containsKey(_sessionUrlKey) &&
        ((storedLength != null && storedLength != length) ||
            (storedModified != null && storedModified != modified))) {
      throw const TransferIntegrityException(
        'Upload source changed after the TUS session was created',
      );
    }
    context.record.protocolMetadata[_sourceLengthKey] = length;
    context.record.protocolMetadata[_sourceModifiedKey] = modified;
    var session = await _restoreSession(context, request);
    session ??= await _createSession(context, request, source, length);
    final serverOffset = await _serverOffset(
      context,
      session,
      allowMissing: false,
    );
    if (serverOffset == null) {
      throw const TransferProtocolException(
        'TUS session disappeared before upload',
      );
    }
    var offset = serverOffset;
    if (offset < 0 || offset > length) {
      throw TransferProtocolException(
        'Server reported invalid TUS offset $offset for $length bytes',
      );
    }
    context.record.protocolMetadata[_offsetKey] = offset;
    await context.onProgress(offset, length);

    while (offset < length) {
      _checkControl(context.control);
      final end = min(offset + request.chunkSize, length);
      final acknowledged = await _patch(
        context,
        session,
        source,
        offset,
        end,
        length,
      );
      if (acknowledged != end) {
        throw TransferProtocolException(
          'TUS server acknowledged offset $acknowledged; expected $end',
          retryable: acknowledged >= offset && acknowledged <= length,
        );
      }
      offset = acknowledged;
      context.record.protocolMetadata[_offsetKey] = offset;
      await context.onProgress(offset, length);
    }

    if (request.expectedChecksum != null) {
      await _verify(source, request.checksum, request.expectedChecksum);
    }
  }

  Future<Uri?> _restoreSession(
    TransferExecutionContext context,
    TusUploadRequest request,
  ) async {
    final stored = context.record.protocolMetadata[_sessionUrlKey] as String?;
    if (stored == null) return null;
    final session = Uri.tryParse(stored);
    if (session == null) {
      context.record.protocolMetadata.remove(_sessionUrlKey);
      context.record.protocolMetadata.remove(_offsetKey);
      return null;
    }
    final offset = await _serverOffset(context, session, allowMissing: true);
    if (offset == null) {
      context.record.protocolMetadata.remove(_sessionUrlKey);
      context.record.protocolMetadata.remove(_offsetKey);
      await context.onProgress(0, await File(request.sourcePath).length());
      return null;
    }
    context.record.protocolMetadata[_offsetKey] = offset;
    return session;
  }

  Future<Uri> _createSession(
    TransferExecutionContext context,
    TusUploadRequest request,
    File source,
    int length,
  ) async {
    final metadata = Map<String, String>.of(request.metadata);
    metadata.putIfAbsent(
      'filename',
      () => Uri.file(source.path).pathSegments.last,
    );
    for (final key in metadata.keys) {
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) {
        throw TransferProtocolException('Invalid TUS metadata key: $key');
      }
    }

    Future<HttpClientRequest> build(Map<String, String> headers) async {
      final outbound = await _client.postUrl(request.endpoint);
      headers.forEach(outbound.headers.set);
      outbound.headers
        ..set('Tus-Resumable', _version)
        ..set('Upload-Length', length.toString());
      if (metadata.isNotEmpty) {
        outbound.headers.set(
          'Upload-Metadata',
          metadata.entries
              .map(
                (entry) =>
                    '${entry.key} ${base64.encode(utf8.encode(entry.value))}',
              )
              .join(','),
        );
      }
      outbound.contentLength = 0;
      return outbound;
    }

    final response = await _send(context, request.endpoint, build);
    if (response.statusCode != HttpStatus.created) {
      await response.drain<void>();
      throw _httpFailure(response.statusCode, request.endpoint);
    }
    final location = response.headers.value(HttpHeaders.locationHeader);
    final offset =
        int.tryParse(response.headers.value('Upload-Offset') ?? '') ?? 0;
    await response.drain<void>();
    if (location == null || location.isEmpty) {
      throw const TransferProtocolException(
        'TUS creation response did not include Location',
      );
    }
    final session = request.endpoint.resolve(location);
    context.record.protocolMetadata[_sessionUrlKey] = session.toString();
    context.record.protocolMetadata[_offsetKey] = offset;
    await context.onProgress(offset, length);
    return session;
  }

  Future<int?> _serverOffset(
    TransferExecutionContext context,
    Uri session, {
    required bool allowMissing,
  }) async {
    Future<HttpClientRequest> build(Map<String, String> headers) async {
      final outbound = await _client.openUrl('HEAD', session);
      headers.forEach(outbound.headers.set);
      outbound.headers.set('Tus-Resumable', _version);
      return outbound;
    }

    final response = await _send(context, session, build);
    if (allowMissing &&
        (response.statusCode == HttpStatus.notFound ||
            response.statusCode == HttpStatus.gone)) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.noContent) {
      await response.drain<void>();
      throw _httpFailure(response.statusCode, session);
    }
    final value = response.headers.value('Upload-Offset');
    await response.drain<void>();
    final offset = value == null ? null : int.tryParse(value);
    if (offset == null) {
      throw const TransferProtocolException(
        'TUS response did not include a valid Upload-Offset',
      );
    }
    return offset;
  }

  Future<int> _patch(
    TransferExecutionContext context,
    Uri session,
    File source,
    int offset,
    int end,
    int total,
  ) async {
    Future<HttpClientRequest> build(Map<String, String> headers) async {
      final outbound = await _client.openUrl('PATCH', session);
      headers.forEach(outbound.headers.set);
      outbound.headers
        ..set('Tus-Resumable', _version)
        ..set('Upload-Offset', offset.toString())
        ..contentType = ContentType('application', 'offset+octet-stream');
      outbound.contentLength = end - offset;
      var sent = offset;
      await for (final chunk in source.openRead(offset, end)) {
        _checkControl(context.control);
        outbound.add(chunk);
        sent += chunk.length;
        await context.onProgress(sent, total);
      }
      return outbound;
    }

    final response = await _send(context, session, build);
    if (response.statusCode != HttpStatus.noContent) {
      await response.drain<void>();
      throw _httpFailure(response.statusCode, session);
    }
    final value = response.headers.value('Upload-Offset');
    await response.drain<void>();
    final acknowledged = value == null ? null : int.tryParse(value);
    if (acknowledged == null) {
      throw const TransferProtocolException(
        'TUS PATCH response did not include a valid Upload-Offset',
      );
    }
    return acknowledged;
  }

  Future<HttpClientResponse> _send(
    TransferExecutionContext context,
    Uri uri,
    Future<HttpClientRequest> Function(Map<String, String> headers) build,
  ) async {
    var response = await (await build(await _headers(context, uri))).close();
    if (response.statusCode == HttpStatus.unauthorized &&
        context.authProvider != null) {
      await response.drain<void>();
      response = await (await build(
        await _headers(context, uri, refresh: true),
      )).close();
    }
    return response;
  }

  Future<Map<String, String>> _headers(
    TransferExecutionContext context,
    Uri uri, {
    bool refresh = false,
  }) async {
    final request = context.record.request;
    final headers = Map<String, String>.of(request.headers);
    final provider = context.authProvider;
    if (provider == null) return headers;
    final authContext = TransferAuthContext(
      taskId: context.record.id,
      uri: uri,
      type: request.type,
      scope: request.authScope,
    );
    headers.addAll(
      refresh
          ? await provider.refreshHeaders(authContext)
          : await provider.headersFor(authContext),
    );
    return headers;
  }

  TransferException _httpFailure(int status, Uri uri) {
    if (status == HttpStatus.requestTimeout ||
        status == HttpStatus.conflict ||
        status == HttpStatus.locked ||
        status == HttpStatus.tooManyRequests ||
        status >= 500) {
      return TransferServerException(
        'HTTP $status from ${uri.host}',
        statusCode: status,
        retryable: true,
      );
    }
    if (status == HttpStatus.unauthorized) {
      return const TransferAuthenticationException(
        'Authentication failed after credential refresh',
      );
    }
    return TransferServerException(
      'HTTP $status from ${uri.host}',
      statusCode: status,
    );
  }

  Future<void> _verify(File file, Checksum? checksum, String? expected) async {
    if (expected == null) return;
    final algorithm = checksum?.algorithm ?? ChecksumAlgorithm.sha256;
    final digest = switch (algorithm) {
      ChecksumAlgorithm.sha256 =>
        await crypto.sha256.bind(file.openRead()).first,
      ChecksumAlgorithm.sha512 =>
        await crypto.sha512.bind(file.openRead()).first,
      ChecksumAlgorithm.md5 => await crypto.md5.bind(file.openRead()).first,
    };
    if (digest.toString().toLowerCase() != expected.toLowerCase()) {
      throw TransferIntegrityException(
        'Expected $expected but received $digest',
      );
    }
  }

  void close() => _client.close(force: true);
}

void _checkControl(TransferControl control) {
  if (control.cancelRequested) throw const TransferCancelledException();
  if (control.pauseRequested) throw const _TransferPausedException();
}

final class _TransferPausedException implements Exception {
  const _TransferPausedException();
}

bool isTransferPausedSignal(Object error) => error is _TransferPausedException;
