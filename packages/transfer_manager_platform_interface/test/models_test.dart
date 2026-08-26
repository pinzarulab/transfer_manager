import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  test('notification tap decodes destination', () {
    final tap = PlatformNotificationTap.fromMap({
      'taskId': 'one',
      'destination': {'kind': 'downloads', 'value': 'report.pdf'},
      'actionHandled': true,
    });

    expect(tap.taskId, 'one');
    expect(tap.destination?.kind, 'downloads');
    expect(tap.destination?.value, 'report.pdf');
    expect(tap.actionHandled, isTrue);
  });

  test('decodes capability maps conservatively', () {
    final capabilities = PlatformTransferCapabilities.fromMap({
      'backgroundDownloads': true,
      'notifications': true,
    });

    expect(capabilities.backgroundDownloads, isTrue);
    expect(capabilities.backgroundUploads, isFalse);
    expect(capabilities.backgroundTusUploads, isFalse);
    expect(capabilities.pauseResume, isFalse);
    expect(capabilities.notifications, isTrue);
    expect(capabilities.liveActivities, isFalse);
  });

  test('decodes task progress and unknown states', () {
    final snapshot = PlatformTaskSnapshot.fromMap({
      'taskId': 'one',
      'state': 'futureState',
      'bytesTransferred': 5,
      'totalBytes': 10,
    });

    expect(snapshot.state, PlatformTaskState.unknown);
    expect(snapshot.fraction, 0.5);
  });

  test('decodes native paused task state', () {
    final snapshot = PlatformTaskSnapshot.fromMap({
      'taskId': 'paused',
      'state': 'paused',
      'bytesTransferred': 5,
    });

    expect(snapshot.state, PlatformTaskState.paused);
  });

  test('encodes multipart upload requests', () {
    final request = PlatformUploadRequest(
      taskId: 'upload-1',
      sourcePath: '/files/video.mp4',
      destination: Uri.parse('https://example.com/upload'),
      fieldName: 'media',
      maxAttempts: 3,
    );

    expect(request.toMap()['fieldName'], 'media');
    expect(request.toMap()['maxAttempts'], 3);
  });

  test('encodes completion notification preference', () {
    final request = PlatformDownloadRequest(
      taskId: 'download-1',
      source: Uri.parse('https://example.com/file'),
      destination: const PlatformTransferDestination(
        kind: 'downloads',
        value: 'file.bin',
      ),
      showNotification: false,
      notificationOpenType: 'reveal',
      showLiveActivity: true,
      liveActivityStyle: 'detailed',
      allowPause: true,
    );

    expect(request.toMap()['showNotification'], isFalse);
    expect(request.toMap()['notificationOpenType'], 'reveal');
    expect(request.toMap()['showLiveActivity'], isTrue);
    expect(request.toMap()['liveActivityStyle'], 'detailed');
    expect(request.toMap()['allowPause'], isTrue);
  });

  test('encodes TUS upload requests', () {
    final request = PlatformTusUploadRequest(
      taskId: 'tus-1',
      sourcePath: '/files/video.mp4',
      endpoint: Uri.parse('https://example.com/files'),
      chunkSize: 1024,
      metadata: const {'filename': 'video.mp4'},
    );

    expect(request.toMap()['endpoint'], 'https://example.com/files');
    expect(request.toMap()['chunkSize'], 1024);
    expect(request.toMap()['metadata'], {'filename': 'video.mp4'});
  });
}
