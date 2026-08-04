import 'dart:math';

import 'package:test/test.dart';
import 'package:transfer_manager/transfer_manager.dart';

void main() {
  test('exponential retry delay caps at maximum', () {
    const policy = RetryPolicy.exponential(
      initialDelay: Duration(seconds: 2),
      maximumDelay: Duration(seconds: 5),
      jitter: false,
    );

    expect(policy.delayForAttempt(1), const Duration(seconds: 2));
    expect(policy.delayForAttempt(2), const Duration(seconds: 4));
    expect(policy.delayForAttempt(3), const Duration(seconds: 5));
  });

  test('jitter stays in the lower half-to-full delay interval', () {
    const policy = RetryPolicy.exponential(initialDelay: Duration(seconds: 10));
    final delay = policy.delayForAttempt(1, random: Random(1));
    expect(delay, greaterThanOrEqualTo(const Duration(seconds: 5)));
    expect(delay, lessThanOrEqualTo(const Duration(seconds: 10)));
  });

  test('progress fraction is bounded', () {
    expect(
      const TransferProgress(bytesTransferred: 120, totalBytes: 100).fraction,
      1,
    );
    expect(TransferProgress.zero.fraction, isNull);
  });

  test('platform-neutral destinations round trip JSON', () {
    const destination = TransferDestination.downloads('report 1.pdf');

    final restored = TransferDestination.fromJson(destination.toJson());

    expect(restored.kind, TransferDestinationKind.downloads);
    expect(restored.value, 'report 1.pdf');
    expect(restored.fileName, 'report 1.pdf');
  });
}
