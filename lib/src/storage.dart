import 'dart:convert';
import 'dart:io';

import 'models.dart';

abstract interface class TransferStorage {
  Future<void> initialize();
  Future<List<TransferRecord>> loadAll();
  Future<void> save(TransferRecord record);
  Future<void> delete(String taskId);
  Future<void> close();
}

/// Useful for tests and foreground-only applications.
final class InMemoryTransferStorage implements TransferStorage {
  final Map<String, TransferRecord> _records = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<List<TransferRecord>> loadAll() async =>
      _records.values.map((record) => record.copy()).toList();

  @override
  Future<void> save(TransferRecord record) async {
    _records[record.id] = record.copy();
  }

  @override
  Future<void> delete(String taskId) async {
    _records.remove(taskId);
  }

  @override
  Future<void> close() async {}
}

/// A small durable store for Dart applications.
///
/// Writes are atomic (temporary file then rename). Applications with high
/// write volume can provide a SQLite implementation of [TransferStorage].
final class JsonFileTransferStorage implements TransferStorage {
  JsonFileTransferStorage(this.file);

  final File file;
  final Map<String, TransferRecord> _records = {};
  Future<void> _pendingWrite = Future.value();

  @override
  Future<void> initialize() async {
    if (!await file.exists()) return;
    final decoded = jsonDecode(await file.readAsString()) as List<Object?>;
    for (final value in decoded) {
      final record = _recordFromJson(value! as Map<String, Object?>);
      _records[record.id] = record;
    }
  }

  @override
  Future<List<TransferRecord>> loadAll() async =>
      _records.values.map((record) => record.copy()).toList();

  @override
  Future<void> save(TransferRecord record) async {
    _records[record.id] = record.copy();
    await _write();
  }

  @override
  Future<void> delete(String taskId) async {
    _records.remove(taskId);
    await _write();
  }

  Future<void> _write() {
    _pendingWrite = _pendingWrite.then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      final payload = _records.values.map(_recordToJson).toList();
      await temporary.writeAsString(jsonEncode(payload), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
    return _pendingWrite;
  }

  @override
  Future<void> close() => _pendingWrite;
}

Map<String, Object?> _recordToJson(TransferRecord record) => {
  'schemaVersion': 1,
  'id': record.id,
  'request': _requestToJson(record.request),
  'state': record.state.name,
  'bytesTransferred': record.bytesTransferred,
  'totalBytes': record.totalBytes,
  'retryAttempts': record.retryAttempts,
  'nativeTaskId': record.nativeTaskId,
  'protocolMetadata': record.protocolMetadata,
  'createdAt': record.createdAt.toIso8601String(),
  'updatedAt': record.updatedAt.toIso8601String(),
};

TransferRecord _recordFromJson(Map<String, Object?> json) => TransferRecord(
  id: json['id']! as String,
  request: _requestFromJson(json['request']! as Map<String, Object?>),
  state: TransferState.values.byName(json['state']! as String),
  bytesTransferred: json['bytesTransferred']! as int,
  totalBytes: json['totalBytes'] as int?,
  retryAttempts: json['retryAttempts']! as int,
  nativeTaskId: json['nativeTaskId'] as String?,
  protocolMetadata:
      (json['protocolMetadata'] as Map<String, Object?>?) ?? const {},
  createdAt: DateTime.parse(json['createdAt']! as String),
  updatedAt: DateTime.parse(json['updatedAt']! as String),
);

Map<String, Object?> _requestToJson(TransferRequest request) {
  final safeHeaders = Map<String, String>.of(request.headers)
    ..removeWhere(
      (key, _) =>
          key.toLowerCase() == 'authorization' ||
          key.toLowerCase() == 'proxy-authorization' ||
          key.toLowerCase() == 'cookie' ||
          key.toLowerCase() == 'set-cookie',
    );
  final common = <String, Object?>{
    'type': request.type.name,
    'headers': safeHeaders,
    'authScope': request.authScope,
    'groupId': request.groupId,
    'priority': request.priority.name,
    'networkPolicy': request.networkPolicy?.name,
    'notification': request.notification?.toJson(),
    'checksum': request.checksum?.algorithm.name,
    'expectedChecksum': request.expectedChecksum,
  };
  return switch (request) {
    UploadRequest() => {
      ...common,
      'sourcePath': request.sourcePath,
      'destination': request.destination.toString(),
      'method': request.method,
      'fieldName': request.fieldName,
      'sourcePolicy': request.sourcePolicy.name,
    },
    DownloadRequest() => {
      ...common,
      'source': request.source.toString(),
      'destinationPath': request.destinationPath,
      'resumeMode': request.resumeMode.name,
      'existingFilePolicy': request.existingFilePolicy.name,
    },
  };
}

TransferRequest _requestFromJson(Map<String, Object?> json) {
  final headers =
      (json['headers'] as Map<String, Object?>?)?.map(
        (key, value) => MapEntry(key, value! as String),
      ) ??
      const <String, String>{};
  final notificationJson = json['notification'] as Map<String, Object?>?;
  final checksumName = json['checksum'] as String?;
  final checksum = checksumName == null
      ? null
      : Checksum(ChecksumAlgorithm.values.byName(checksumName));
  final priority = TransferPriority.values.byName(json['priority']! as String);
  final networkName = json['networkPolicy'] as String?;
  final network = networkName == null
      ? null
      : NetworkPolicy.values.byName(networkName);
  if (json['type'] == TransferType.upload.name) {
    return UploadRequest(
      sourcePath: json['sourcePath']! as String,
      destination: Uri.parse(json['destination']! as String),
      method: json['method']! as String,
      fieldName: json['fieldName']! as String,
      sourcePolicy: UploadSourcePolicy.values.byName(
        json['sourcePolicy']! as String,
      ),
      headers: headers,
      authScope: json['authScope'] as String?,
      groupId: json['groupId'] as String?,
      priority: priority,
      networkPolicy: network,
      notification: notificationJson == null
          ? null
          : TransferNotification.fromJson(notificationJson),
      checksum: checksum,
      expectedChecksum: json['expectedChecksum'] as String?,
    );
  }
  return DownloadRequest(
    source: Uri.parse(json['source']! as String),
    destinationPath: json['destinationPath']! as String,
    resumeMode: ResumeMode.values.byName(json['resumeMode']! as String),
    existingFilePolicy: ExistingFilePolicy.values.byName(
      json['existingFilePolicy']! as String,
    ),
    headers: headers,
    authScope: json['authScope'] as String?,
    groupId: json['groupId'] as String?,
    priority: priority,
    networkPolicy: network,
    notification: notificationJson == null
        ? null
        : TransferNotification.fromJson(notificationJson),
    checksum: checksum,
    expectedChecksum: json['expectedChecksum'] as String?,
  );
}
