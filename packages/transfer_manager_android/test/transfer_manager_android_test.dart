import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager_android/transfer_manager_android.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.transfer_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('maps capabilities returned by Android', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'capabilities');
      return {
        'backgroundDownloads': true,
        'backgroundUploads': false,
        'backgroundTusUploads': true,
        'pauseResume': true,
        'notifications': true,
        'notificationCancellation': true,
        'notificationTaps': true,
        'openArtifacts': true,
        'revealArtifacts': true,
      };
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    final capabilities = await platform.capabilities();

    expect(capabilities.backgroundDownloads, isTrue);
    expect(capabilities.backgroundUploads, isFalse);
    expect(capabilities.backgroundTusUploads, isTrue);
    expect(capabilities.pauseResume, isTrue);
    expect(capabilities.notificationCancellation, isTrue);
    expect(capabilities.notificationTaps, isTrue);
    expect(capabilities.openArtifacts, isTrue);
    expect(capabilities.revealArtifacts, isTrue);
  });

  test('encodes a durable download request', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'enqueueDownload');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['taskId'], 'task-1');
      expect(arguments['networkPolicy'], 'unmetered');
      expect(arguments['showNotification'], isFalse);
      return 'work-1';
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    final workId = await platform.enqueueDownload(
      PlatformDownloadRequest(
        taskId: 'task-1',
        source: Uri.parse('https://example.com/file'),
        destination: const PlatformTransferDestination(
          kind: 'file',
          value: '/files/file',
        ),
        networkPolicy: 'unmetered',
        showNotification: false,
      ),
    );

    expect(workId, 'work-1');
  });

  test('requests notification permission through Android', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'requestNotificationPermission');
      return true;
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    expect(await platform.requestNotificationPermission(), isTrue);
  });

  test('forwards pause and resume controls to Android', () async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      expect((call.arguments! as Map<Object?, Object?>)['taskId'], 'task-1');
      return null;
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    await platform.pause('task-1');
    await platform.resume('task-1');

    expect(calls, ['pause', 'resume']);
  });

  test('forwards artifact open and reveal actions', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    final platform = TransferManagerAndroid(methodChannel: channel);
    const destination = PlatformTransferDestination(
      kind: 'downloads',
      value: 'report.pdf',
    );

    await platform.open('one', destination);
    await platform.reveal('one', destination);

    expect(methods, ['open', 'reveal']);
  });

  test('maps an initial notification tap', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takeInitialNotificationTap');
      return {
        'taskId': 'task-1',
        'destination': {'kind': 'downloads', 'value': 'report.pdf'},
      };
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    final tap = await platform.takeInitialNotificationTap();

    expect(tap?.taskId, 'task-1');
    expect(tap?.destination?.kind, 'downloads');
    expect(tap?.destination?.value, 'report.pdf');
  });

  test('delivers a live notification tap and acknowledges it', () async {
    final platform = TransferManagerAndroid(methodChannel: channel);
    final tapFuture = platform.notificationTaps.first;
    final response = Completer<ByteData?>();

    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(
        const MethodCall('notificationTapped', {
          'taskId': 'task-live',
          'destination': {'kind': 'downloads', 'value': 'live.pdf'},
        }),
      ),
      response.complete,
    );

    final tap = await tapFuture;
    final acknowledged = channel.codec.decodeEnvelope((await response.future)!);
    expect(tap.taskId, 'task-live');
    expect(tap.destination?.value, 'live.pdf');
    expect(acknowledged, isTrue);
  });

  test('encodes a durable multipart upload request', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'enqueueUpload');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['sourcePath'], '/files/video.mp4');
      expect(arguments['fieldName'], 'media');
      return 'upload-work-1';
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    final workId = await platform.enqueueUpload(
      PlatformUploadRequest(
        taskId: 'upload-1',
        sourcePath: '/files/video.mp4',
        destination: Uri.parse('https://example.com/upload'),
        fieldName: 'media',
      ),
    );

    expect(workId, 'upload-work-1');
  });

  test('encodes a durable TUS upload request', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'enqueueTusUpload');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['sourcePath'], '/files/video.mp4');
      expect(arguments['chunkSize'], 1024);
      expect(arguments['metadata'], {'filename': 'video.mp4'});
      return 'tus-work-1';
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    final workId = await platform.enqueueTusUpload(
      PlatformTusUploadRequest(
        taskId: 'tus-1',
        sourcePath: '/files/video.mp4',
        endpoint: Uri.parse('https://example.com/files'),
        chunkSize: 1024,
        metadata: const {'filename': 'video.mp4'},
      ),
    );

    expect(workId, 'tus-work-1');
  });

  test('registerWith installs the Android implementation', () {
    TransferManagerAndroid.registerWith();
    expect(TransferManagerPlatform.instance, isA<TransferManagerAndroid>());
  });
}
