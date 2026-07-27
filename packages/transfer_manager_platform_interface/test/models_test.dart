import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager_platform_interface/transfer_manager_platform_interface.dart';

void main() {
  test('decodes capability maps conservatively', () {
    final capabilities = PlatformTransferCapabilities.fromMap({
      'backgroundDownloads': true,
      'notifications': true,
    });

    expect(capabilities.backgroundDownloads, isTrue);
    expect(capabilities.backgroundUploads, isFalse);
    expect(capabilities.pauseResume, isFalse);
    expect(capabilities.notifications, isTrue);
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
}
