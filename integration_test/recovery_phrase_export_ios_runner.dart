import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'recovery_phrase_export_native_test.dart' as suite;
import 'support/native_test_install.dart';

/// Keep the interactive device fixture understandable after its cleanup runs.
/// The normal application never imports this test entry point.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  var verifiedIsolatedInstall = false;
  // This guard uses test assertions and must run in a live test zone, not in
  // the completion callback registered by main(). Keep every native side
  // effect below conditional on successful verification.
  setUpAll(() async {
    await verifyNativeTestInstall();
    verifiedIsolatedInstall = true;
  });
  if (const bool.fromEnvironment('FIFE_NATIVE_RESULT_ONLY')) {
    testWidgets('native completion callback renders after test teardown',
        (tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
    });
  } else {
    suite.main();
  }
  unawaited(binding.allTestsPassed.future.then((passed) async {
    if (!verifiedIsolatedInstall) return;
    await const SystemAppLockPrivacy().setEnabled(false);
    runApp(RecoveryExportTestResult(passed: passed));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final documents = await getApplicationDocumentsDirectory();
      await File('${documents.path}/fife-recovery-export-terminal.json')
          .writeAsString(jsonEncode({
        'runId': const String.fromEnvironment('FIFE_NATIVE_RUN_ID'),
        'passed': passed,
        'resultUiFrameBuilt': true,
        'at': DateTime.now().millisecondsSinceEpoch,
      }));
    });
  }));
}

class RecoveryExportTestResult extends StatelessWidget {
  const RecoveryExportTestResult({super.key, required this.passed});

  final bool passed;

  @override
  Widget build(BuildContext context) => MaterialApp(
      home: Scaffold(
          appBar: AppBar(title: const Text('Recovery export test')),
          body: SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                            liveRegion: true,
                            child: Text(
                                passed ? 'Test completed' : 'Test stopped',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium)),
                        const SizedBox(height: 16),
                        Text(passed
                            ? 'The test finished successfully.'
                            : 'The test did not finish successfully. Check the test result before retrying.'),
                        const SizedBox(height: 16),
                        const Text(
                            'This is the separate test app. You can return to the iPhone Home screen.'),
                      ])))));
}
