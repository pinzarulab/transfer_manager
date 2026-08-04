import 'package:flutter_test/flutter_test.dart';
import 'package:transfer_manager_flutter/transfer_manager_flutter.dart';

void main() {
  test('exports platform-neutral download destinations', () {
    const destination = TransferDestination.downloads('report.pdf');

    expect(destination.kind, TransferDestinationKind.downloads);
    expect(destination.fileName, 'report.pdf');
  });
}
