import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_file_viewer.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'support/iphone_results.dart';
import 'support/apple_viewer_probe.dart';
import 'support/native_test_identity.dart';
import 'support/native_test_install.dart';

/// The actual default Dart transport and AppDelegate registration are used.
/// These sandbox files test UIKit presentation, independently of authentication
/// and the external Files-picker/bookmark journey.
void main() {
  const privacyOnly = bool.fromEnvironment('FIFE_VIEWER_PRIVACY_ONLY');
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  recordIphoneResults(binding, 'file-viewer');
  late Directory directory;
  late File text;
  late File binary;
  late File progress;
  var activeCase = 'setup';
  final observations = <String, String>{};
  Future<void> checkpoint(String phase) async {
    final next = File('${progress.path}.partial');
    await next.writeAsString(
        jsonEncode({
          'runId': const String.fromEnvironment('FIFE_NATIVE_RUN_ID'),
          'case': activeCase,
          'phase': phase,
          'observations': observations,
          'nativeState': appleViewerProbe(),
          'flutterLifecycle': binding.lifecycleState?.name,
          'time': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true);
    await next.rename(progress.path);
  }

  setUpAll(() async {
    expect(Platform.isIOS, isTrue);
    expect(const bool.fromEnvironment('FIFE_RUN_FILE_VIEWER_TESTS'), isTrue);
    final bundle = (await PackageInfo.fromPlatform()).packageName;
    expect(isIsolatedNativeTestBundle(bundle), isTrue);
    await verifyNativeTestStorageIsolation(bundle);
    progress = File(
        '${(await getApplicationDocumentsDirectory()).path}/fife-file-viewer-stage.json');
    await checkpoint('setup');
    expect(FileViewerPlatform.instance, isA<NativeFileViewer>());
    directory = await Directory.systemTemp.createTemp('fife-viewer-');
    text = await File('${directory.path}/FiFe-viewer-test.txt')
        .writeAsString('FiFe synthetic file viewer check. No private data.');
    binary = await File('${directory.path}/FiFe-viewer-test.fifeunsupported')
        .writeAsBytes(List.generate(4096, (i) => (i * 173 + i ~/ 7) % 256));
    await checkpoint('setup_complete');
  });
  tearDownAll(() async {
    await FileViewerPlatform.instance.cancel();
    if (await directory.exists()) await directory.delete(recursive: true);
  });
  // A failed owner-assisted case must not leave its presentation pending in
  // the next independent case. This cleans test-owned UI, not app setup.
  tearDown(() => FileViewerPlatform.instance.cancel());

  Future<void> show(WidgetTester tester, String instruction) async {
    await checkpoint('rendering_instructions');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: Text(instruction))),
    ));
    await checkpoint('settling_instructions');
    await tester.pumpAndSettle();
    await checkpoint('instructions_ready');
    final elapsed = Stopwatch()..start();
    while (appleViewerProbe()['nativeReady'] != true &&
        elapsed.elapsed < const Duration(seconds: 20)) {
      await checkpoint('waiting_for_active_presenter');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(appleViewerProbe()['nativeReady'], isTrue,
        reason:
            'A native viewer needs the app activated with an attached stable presenter');
    await checkpoint('presenter_ready');
  }

  Future<FileViewResult> openNative(String path, String phase) async {
    await checkpoint(phase);
    var completed = false;
    final opening = FileViewerPlatform.instance
        .open(path)
        .timeout(const Duration(minutes: 10))
        .whenComplete(() => completed = true);
    try {
      await Future.any<Object?>([
        opening,
        Future<void>.delayed(const Duration(milliseconds: 300)),
      ]);
      if (!completed) await checkpoint(phase);
      return await opening;
    } catch (_) {
      // Close before the live binding tries its final frame; a native preview
      // can otherwise keep Flutter inactive and prevent test teardown itself.
      await FileViewerPlatform.instance.cancel();
      rethrow;
    }
  }

  testWidgets(
      'default registered channel opens text and completes on dismissal',
      (tester) async {
    activeCase = 'supported_text';
    await show(
        tester, 'Synthetic text viewer test: dismiss the preview with Done.');
    final result = await openNative(text.path, 'native_open_pending');
    observations[activeCase] = result.name;
    await checkpoint('native_open_completed');
    expect(result, FileViewResult.opened);
    expect(await text.readAsString(), contains('No private data.'));
  }, skip: privacyOnly);

  testWidgets(
      'unknown binary reports unsupported without an empty native screen',
      (tester) async {
    activeCase = 'unknown_type';
    await show(tester,
        'Unknown-type viewer test: dismiss any Open In menu without sharing.');
    final result = await openNative(binary.path, 'native_open_pending');
    observations[activeCase] = result.name;
    await checkpoint('native_open_completed');
    expect(result, FileViewResult.unsupported);
    expect(await binary.length(), 4096);
    binding.reportData = {
      ...?binding.reportData,
      'unknownTypeResult': result.name,
    };
  }, skip: privacyOnly);

  testWidgets('default native channel classifies missing paths and directories',
      (tester) async {
    activeCase = 'missing_and_directory';
    await show(tester, 'Checking unavailable files.');
    await checkpoint('native_open_pending');
    expect(await FileViewerPlatform.instance.open('${text.path}.missing'),
        FileViewResult.missing);
    expect(await FileViewerPlatform.instance.open(directory.path),
        FileViewResult.denied);
    await checkpoint('native_checks_complete');
  }, skip: privacyOnly);

  testWidgets(
      'native cancellation resolves the request and allows another open',
      (tester) async {
    activeCase = 'cancel_and_reopen';
    await show(tester,
        'Cancellation and reopen test: dismiss the final text preview with Done.');
    await checkpoint('native_cancellation_pending');
    final first = FileViewerPlatform.instance.open(text.path);
    // Both calls traverse the same real platform channel in FIFO order. There
    // is no fake viewer or extra native registration supplied by this fixture.
    await FileViewerPlatform.instance.cancel();
    expect(await first, FileViewResult.cancelled);
    await checkpoint('settling_after_cancellation');
    await tester.pumpAndSettle();
    final second = await openNative(text.path, 'native_reopen_pending');
    observations[activeCase] = second.name;
    await checkpoint('complete');
    expect(second, FileViewResult.opened);
  }, skip: privacyOnly);

  testWidgets('a locked resumed frame closes the native document',
      (tester) async {
    activeCase = 'locked_native_preview';
    await show(
        tester, 'Automatic native-preview privacy check. No action needed.');
    final nativeActivity = <AppLifecycleState>[];
    final stopLifecycle =
        await const SystemAppLockPrivacy().watchLifecycle(nativeActivity.add);
    FileViewResult? observed;
    final opening = FileViewerPlatform.instance.open(text.path).then((value) {
      observed = value;
      return value;
    });
    try {
      final elapsed = Stopwatch()..start();
      while (appleViewerProbe()['hostClass'] == 'FlutterViewController' &&
          observed == null &&
          elapsed.elapsed < const Duration(seconds: 10)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(observed, isNull, reason: 'The actual text preview must be open');
      expect(appleViewerProbe()['hostClass'], isNot('FlutterViewController'));
      expect(nativeActivity.last, AppLifecycleState.resumed,
          reason: 'A native preview is still active application use');
      observations['native_application_activity'] = nativeActivity.last.name;
      await const MethodChannel('com.jeerovan.fife/app_lock_privacy')
          .invokeMethod<void>('frameReady', {'allowNativeDocuments': false});
      await Future.any<Object?>([
        opening,
        Future<void>.delayed(const Duration(seconds: 3)),
      ]);
      observations[activeCase] = observed?.name ?? 'remained_presented';
      await checkpoint('locked_frame_result');
      expect(observed, FileViewResult.cancelled,
          reason:
              'A safe Flutter lock frame must not reveal a native document');
      final closed = Stopwatch()..start();
      while (appleViewerProbe()['hostClass'] != 'FlutterViewController' &&
          closed.elapsed < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(appleViewerProbe()['hostClass'], 'FlutterViewController');
      await checkpoint('locked_frame_closed');
      expect(await text.readAsString(), contains('No private data.'));
    } finally {
      stopLifecycle();
      await FileViewerPlatform.instance.cancel();
      await opening;
    }
  });
}
