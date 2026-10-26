import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart' as app;
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_file_viewer.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/ui/pages/page_search.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'support/apple_viewer_probe.dart';
import 'support/iphone_results.dart';
import 'support/native_test_identity.dart';

class _ObservedAppLockViewer extends FileViewerPlatform {
  _ObservedAppLockViewer(this.actual);
  final FileViewerPlatform actual;
  int calls = 0, completions = 0;
  FileViewResult? last;
  void Function(FileViewResult)? onCompleted;
  @override
  Future<FileViewResult> open(String path) async {
    calls++;
    final value = await actual.open(path);
    last = value;
    completions++;
    onCompleted?.call(value);
    return value;
  }

  @override
  Future<void> cancel() => actual.cancel();
}

/// Continues the real Files/session setup from the file-tap journey. Nothing
/// creates a session, grants a bookmark, injects a clock or overrides auth here.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive
    ..shouldPropagateDevicePointerEvents = true;
  recordIphoneResults(binding, 'app-lock-file-viewer-journey');
  const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
  const contents = 'FiFe iOS file-tap verification. Synthetic content only.\n';
  const textName = 'FiFe-tap-text-as0pgk65.txt';
  final checks = <String, bool>{};
  final metrics = <String, int>{};
  final trace = <Map<String, Object?>>[];
  var phase = 'starting';
  late File progress;
  AppLockController? lock;
  _ObservedAppLockViewer? observedViewer;

  Future<void> checkpoint(String next) async {
    phase = next;
    final pending = File('${progress.path}.partial');
    await pending.writeAsString(
        jsonEncode({
          'runId': runId,
          'phase': phase,
          'checks': checks,
          'metrics': metrics,
          'trace': trace,
          'viewer': observedViewer == null
              ? null
              : {
                  'calls': observedViewer!.calls,
                  'completions': observedViewer!.completions,
                  'last': observedViewer!.last?.name,
                },
          'policy': lock == null
              ? null
              : {
                  'ready': lock!.ready,
                  'enabled': lock!.enabled,
                  'minutes': lock!.minutes,
                  'locked': lock!.locked,
                  'foreground': lock!.foreground,
                  'busy': lock!.busy,
                },
          'screens': {
            'explorer': find.byType(FilePane).evaluate().isNotEmpty,
            'settings': find.byType(SettingsPage).evaluate().isNotEmpty,
            'search': find.byType(SearchScreen).evaluate().isNotEmpty,
          },
          'nativeState': appleViewerProbe(),
          'flutterLifecycle': binding.lifecycleState?.name,
          'time': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true);
    await pending.rename(progress.path);
  }

  Future<void> until(FutureOr<bool> Function() ready,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final watch = Stopwatch()..start();
    while (!await ready()) {
      if (watch.elapsed >= timeout) {
        final waiting = phase;
        await checkpoint('timed_out_$waiting');
        throw StateError('Timed out at $waiting');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      'real scene inactivity protects native reading and restores policy',
      (tester) async {
    expect(Platform.isIOS, isTrue);
    expect(const bool.fromEnvironment('FIFE_RUN_APP_LOCK_JOURNEY'), isTrue);
    expect(AppEnv.localTestingBuild, isFalse);
    expect(
        isIsolatedNativeTestBundle(
            (await PackageInfo.fromPlatform()).packageName),
        isTrue);
    progress = File(
        '${(await getApplicationDocumentsDirectory()).path}/fife-app-lock-journey.json');
    await checkpoint('normal_main');
    await app.main();
    await until(() => find.byType(AppLockGate).evaluate().isNotEmpty);
    lock = tester.widget<AppLockGate>(find.byType(AppLockGate)).controller;
    await checkpoint('owner_startup_unlock_if_required');
    await until(
        () =>
            lock!.ready &&
            !lock!.concealed &&
            find.byType(FilePane).evaluate().isNotEmpty,
        timeout: const Duration(minutes: 10));
    expect((await ModelProfile.get())?.email?.toLowerCase(),
        'tojeevansingh@gmail.com');
    final loc = AppLocalizations.of(tester.element(find.byType(FilePane)))!;
    final db = await StorageSqlite.instance.database;
    final rows = await db.query('items',
        where: 'name = ? AND archived_at = 0', whereArgs: [textName]);
    final locals = <ModelItem>[];
    for (final row in rows) {
      final item = await ModelItem.fromMap(row);
      if (await ModelItem.isLocalPath(item.id)) locals.add(item);
    }
    expect(locals, hasLength(1),
        reason:
            'Use only the real granted synthetic source from the file-tap journey');
    final local = locals.single;
    expect(
        await LocalItemAccess.withAccess(
            local.id, (path) => File(path).readAsString()),
        contents);
    checks['normalSavedOwnerAndRealSource'] = true;

    Future<void> ready(Finder target, String label) async {
      await checkpoint('${label}_waiting');
      await until(() =>
          binding.lifecycleState == AppLifecycleState.resumed &&
          appleViewerProbe()['nativeReady'] == true &&
          !lock!.concealed);
      await binding.endOfFrame.timeout(const Duration(seconds: 10));
      await until(() => target.evaluate().length == 1);
      await tester.ensureVisible(target);
      await until(() {
        final matches = target.hitTestable().evaluate();
        if (matches.length != 1) return false;
        final route = ModalRoute.of(matches.single);
        return (route?.isCurrent ?? true) &&
            (route?.animation?.isCompleted ?? true);
      });
      await checkpoint('${label}_ready');
    }

    Future<void> tap(Finder target, String label) async {
      await ready(target, label);
      await tester.tap(target);
    }

    Future<void> settings() async {
      await tap(find.byIcon(LucideIcons.moreVertical), 'open_settings_menu');
      await tap(find.text(loc.settings), 'select_settings');
      await until(() => find.byType(SettingsPage).evaluate().isNotEmpty);
    }

    Future<void> backFromSettings() async {
      await tap(
          find.descendant(
              of: find.byType(SettingsPage),
              matching: find.byIcon(LucideIcons.arrowLeft)),
          'settings_back');
      await until(() => find.byType(SettingsPage).evaluate().isEmpty);
    }

    Future<void> timeoutMinutes(int value) async {
      final slider = find.byKey(const ValueKey('app-lock-timeout'));
      await ready(slider, 'timeout_${value}_gesture');
      final rect = tester.getRect(slider);
      final index = [1, 5, 10, 15, 20, 25, 30].indexOf(value);
      await tester.tapAt(Offset(
          rect.left + 24 + (rect.width - 48) * index / 6, rect.center.dy));
      await checkpoint('timeout_${value}_persisting');
      await until(() => lock!.minutes == value && !lock!.busy);
      await checkpoint('timeout_${value}_persisted');
    }

    await settings();
    if (!lock!.enabled) {
      await tap(
          find.byKey(const ValueKey('app-lock-switch')), 'enable_app_lock');
      await checkpoint('owner_enable_app_lock');
      await until(() => lock!.enabled && !lock!.busy && !lock!.locked,
          timeout: const Duration(minutes: 10));
    }
    checks['realEnabledPolicy'] = true;
    await checkpoint('enabled_policy_verified');
    await timeoutMinutes(1);
    await backFromSettings();
    // Search avoids a redundant same-root folder tap/access check. Every
    // navigation action waits for its actual route and resulting screen.
    await tap(find.byIcon(LucideIcons.moreVertical), 'open_search_menu');
    await tap(find.text(loc.search), 'select_search');
    await until(() => find.byType(SearchScreen).evaluate().isNotEmpty);
    final field = find.byType(TextField);
    await tap(field, 'search_input');
    final input = tester.state<EditableTextState>(
        find.descendant(of: field, matching: find.byType(EditableText)));
    await until(() => input.widget.focusNode.hasFocus);
    input.updateEditingValue(const TextEditingValue(
        text: 'as0pgk65', selection: TextSelection.collapsed(offset: 8)));
    final row = find.byKey(ValueKey(local.id));
    await ready(row, 'source_search_result');
    final actual = FileViewerPlatform.instance;
    expect(actual, isA<NativeFileViewer>());
    final viewer = _ObservedAppLockViewer(actual);
    observedViewer = viewer;
    void traceState(String event) {
      if (trace.length == 64) trace.removeAt(0);
      trace.add({
        'event': event,
        'time': DateTime.now().toUtc().toIso8601String(),
        'foreground': lock!.foreground,
        'locked': lock!.locked,
        'ready': lock!.ready,
        'busy': lock!.busy,
        'native': appleViewerProbe(),
      });
    }

    void controllerChanged() => traceState('controller');
    lock!.addListener(controllerChanged);
    viewer.onCompleted = (result) => traceState('viewer_${result.name}');
    FileViewerPlatform.instance = viewer;
    DateTime? leftAt, returnedAt;
    var authRequested = false;
    void sceneChanged() {
      if (leftAt == null && !lock!.foreground) leftAt = DateTime.now().toUtc();
      if (leftAt != null && returnedAt == null && lock!.foreground) {
        returnedAt = DateTime.now().toUtc();
      }
      if (leftAt != null && lock!.locked && lock!.busy) authRequested = true;
    }

    var readingAssertion = 'opening';
    final readingElapsed = Stopwatch();
    try {
      await tester.tap(row);
      await until(
          () => appleViewerProbe()['hostClass'] != 'FlutterViewController');
      await checkpoint('hold_reading_preview_65_seconds');
      final watch = Stopwatch()..start();
      readingElapsed.start();
      while (watch.elapsed < const Duration(seconds: 65)) {
        readingAssertion = 'foreground';
        expect(lock!.foreground, isTrue);
        readingAssertion = 'locked';
        expect(lock!.locked, isFalse);
        readingAssertion = 'native_completion';
        expect(viewer.completions, 0,
            reason:
                'The native preview must remain open for the full reading check');
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      metrics['nativeReadingMilliseconds'] = watch.elapsedMilliseconds;
      await checkpoint('owner_dismiss_reading_preview');
      await until(() => viewer.completions == 1,
          timeout: const Duration(minutes: 10));
      expect(viewer.last, FileViewResult.opened);
      expect(lock!.locked, isFalse);
      checks['nativeReadingBeyondTimeoutRemainsAuthorized'] = true;
      lock!.addListener(sceneChanged);
      await tap(row, 'background_source_open');
      await until(
          () => appleViewerProbe()['hostClass'] != 'FlutterViewController');
      await checkpoint('owner_background_preview_65_seconds');
      await until(() => leftAt != null, timeout: const Duration(minutes: 10));
      await until(
          () =>
              returnedAt != null &&
              authRequested &&
              lock!.foreground &&
              !lock!.locked &&
              !lock!.busy,
          timeout: const Duration(minutes: 10));
      metrics['nativeSceneAwayMilliseconds'] =
          returnedAt!.difference(leftAt!).inMilliseconds;
      expect(
          metrics['nativeSceneAwayMilliseconds'], greaterThanOrEqualTo(60000));
      expect(viewer.completions, 2);
      expect(viewer.last, FileViewResult.cancelled);
      expect(
          await LocalItemAccess.withAccess(
              local.id, (path) => File(path).readAsString()),
          contents);
      checks['realSceneTimeoutAuthenticatesAndClosesNativePreview'] = true;
      await checkpoint('native_app_lock_return_verified');
    } catch (_) {
      metrics['readingElapsedAtFailureMilliseconds'] =
          readingElapsed.elapsedMilliseconds;
      await checkpoint('failed_${phase}_$readingAssertion');
      rethrow;
    } finally {
      lock!.removeListener(controllerChanged);
      lock!.removeListener(sceneChanged);
      await viewer.cancel();
      FileViewerPlatform.instance = actual;
    }
    await tap(
        find.descendant(
            of: find.byType(SearchScreen),
            matching: find.byIcon(LucideIcons.arrowLeft)),
        'search_back');
    await until(() => find.byType(SearchScreen).evaluate().isEmpty);
    await settings();
    await timeoutMinutes(5);
    await tap(
        find.byKey(const ValueKey('app-lock-switch')), 'restore_app_lock_off');
    await checkpoint('owner_restore_app_lock_off');
    await until(() => !lock!.enabled && !lock!.busy,
        timeout: const Duration(minutes: 10));
    final restored = await ModelAppLockStore().read();
    expect(restored.enabled, isFalse);
    expect(restored.minutes, 5);
    checks['appLockPolicyRestored'] = true;
    await backFromSettings();
    await checkpoint('complete');
  }, timeout: const Timeout(Duration(minutes: 45)));
}
