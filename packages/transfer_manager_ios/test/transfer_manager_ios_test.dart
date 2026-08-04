import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager_ios/transfer_manager_ios.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test.transfer_manager_ios');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('maps iOS capabilities', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      return {
        'backgroundDownloads': true,
        'backgroundUploads': true,
        'backgroundTusUploads': false,
        'pauseResume': true,
        'notifications': true,
        'notificationCancellation': false,
      };
    });

    final capabilities = await TransferManagerIos(
      methodChannel: channel,
    ).capabilities();

    expect(capabilities.backgroundDownloads, isTrue);
    expect(capabilities.backgroundUploads, isTrue);
    expect(capabilities.backgroundTusUploads, isFalse);
    expect(capabilities.pauseResume, isTrue);
  });

  test('encodes download and upload requests', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return '42';
    });
    final platform = TransferManagerIos(methodChannel: channel);

    await platform.enqueueDownload(
      PlatformDownloadRequest(
        taskId: 'download',
        source: Uri.parse('https://example.com/file'),
        destination: const PlatformTransferDestination(
          kind: 'file',
          value: '/files/file',
        ),
      ),
    );
    await platform.enqueueUpload(
      PlatformUploadRequest(
        taskId: 'upload',
        sourcePath: '/files/video.mp4',
        destination: Uri.parse('https://example.com/upload'),
      ),
    );

    expect(calls.map((call) => call.method), [
      'enqueueDownload',
      'enqueueUpload',
    ]);
    expect(
      ((calls.first.arguments! as Map<Object?, Object?>)['destination']!
          as Map<Object?, Object?>)['value'],
      '/files/file',
    );
  });

  test('forwards native transfer controls', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    final platform = TransferManagerIos(methodChannel: channel);

    await platform.pause('one');
    await platform.resume('one');
    await platform.cancel('one');

    expect(methods, ['pause', 'resume', 'cancel']);
  });

  test('forwards artifact open and reveal actions', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    final platform = TransferManagerIos(methodChannel: channel);
    const destination = PlatformTransferDestination(
      kind: 'downloads',
      value: 'report.pdf',
    );

    await platform.open('one', destination);
    await platform.reveal('one', destination);

    expect(methods, ['open', 'reveal']);
  });

  test('returns the notification that launched the app', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'takeInitialNotificationResponse');
      return {
        'taskId': 'download-1',
        'filePath': '/Documents/downloads/report.pdf',
      };
    });
    final platform = TransferManagerIos(methodChannel: channel);

    final response = await platform.takeInitialNotificationResponse();

    expect(response?.taskId, 'download-1');
    expect(response?.destination?.value, '/Documents/downloads/report.pdf');
  });

  test('rejects native TUS because iOS uses foreground fallback', () {
    final platform = TransferManagerIos(methodChannel: channel);

    expect(
      () => platform.enqueueTusUpload(
        PlatformTusUploadRequest(
          taskId: 'tus',
          sourcePath: '/file',
          endpoint: Uri.parse('https://example.com/tus'),
        ),
      ),
      throwsUnsupportedError,
    );
  });
}
