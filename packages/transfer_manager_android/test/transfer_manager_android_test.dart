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
      };
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    final capabilities = await platform.capabilities();

    expect(capabilities.backgroundDownloads, isTrue);
    expect(capabilities.backgroundUploads, isFalse);
    expect(capabilities.backgroundTusUploads, isTrue);
    expect(capabilities.pauseResume, isTrue);
    expect(capabilities.notificationCancellation, isTrue);
  });

  test('encodes a durable download request', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'enqueueDownload');
      final arguments = call.arguments! as Map<Object?, Object?>;
      expect(arguments['taskId'], 'task-1');
      expect(arguments['networkPolicy'], 'unmetered');
      return 'work-1';
    });
    final platform = TransferManagerAndroid(methodChannel: channel);

    final workId = await platform.enqueueDownload(
      PlatformDownloadRequest(
        taskId: 'task-1',
        source: Uri.parse('https://example.com/file'),
        destinationPath: '/files/file',
        networkPolicy: 'unmetered',
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
