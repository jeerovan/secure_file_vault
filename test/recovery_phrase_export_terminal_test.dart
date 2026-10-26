import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/recovery_phrase_export_ios_runner.dart';

void main() {
  for (final passed in [false, true]) {
    testWidgets('native test renders a clear result when passed=$passed',
        (tester) async {
      await tester.pumpWidget(RecoveryExportTestResult(passed: passed));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.text(passed ? 'Test completed' : 'Test stopped'),
          findsOneWidget);
      expect(find.textContaining('separate test app'), findsOneWidget);
      expect(find.textContaining('Home screen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
