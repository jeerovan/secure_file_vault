import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart' as app;
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/services/service_file_viewer.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_notice.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/ui/pages/page_search.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/ui/pages/page_welcome.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/utils_transfer_staging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'support/apple_viewer_probe.dart';
import 'support/iphone_results.dart';
import 'support/native_test_identity.dart';

/// A transparent observer: every request still uses the default native viewer.
/// It records no paths, credentials or document contents and changes no result.
class _ObservedViewer extends FileViewerPlatform {
  _ObservedViewer(this.actual);
  final FileViewerPlatform actual;
  int calls = 0;
  int completions = 0;
  FileViewResult? last;
  @override
  Future<FileViewResult> open(String path) async {
    calls++;
    final result = await actual.open(path);
    last = result;
    completions++;
    return result;
  }

  @override
  Future<void> cancel() => actual.cancel();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive
    ..shouldPropagateDevicePointerEvents = true;
  recordIphoneResults(binding, 'normal-file-tap-journey');
  const runId = String.fromEnvironment('FIFE_NATIVE_RUN_ID');
  const folderName = 'FiFe-file-taps-as0pgk65';
  const textName = 'FiFe-tap-text-as0pgk65.txt';
  const unknownName = 'FiFe-tap-unknown-as0pgk65.fifeunsupported';
  const sourceContents =
      'FiFe iOS file-tap verification. Synthetic content only.\n';
  const account = 'tojeevansingh@gmail.com';
  var phase = 'starting';
  final checks = <String, bool>{};
  final metrics = <String, int>{};
  late File progress;
  Future<void> checkpoint(String next) async {
    phase = next;
    final partial = File('${progress.path}.partial');
    await partial.writeAsString(
        jsonEncode({
          'runId': runId,
          'phase': phase,
          'checks': checks,
          'metrics': metrics,
          'nativeState': appleViewerProbe(),
          'flutterLifecycle': binding.lifecycleState?.name,
          'time': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true);
    await partial.rename(progress.path);
  }

  Future<void> until(FutureOr<bool> Function() ready,
      {Duration timeout = const Duration(seconds: 90)}) async {
    final elapsed = Stopwatch()..start();
    while (!await ready()) {
      if (elapsed.elapsed >= timeout) {
        final waiting = phase;
        await checkpoint('timed_out_$waiting');
        throw StateError('Timed out at $waiting');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  testWidgets('normal startup, real folder grant and local/remote file taps',
      (tester) async {
    Future<void> readyTarget(Finder target) async {
      await until(() => target.evaluate().length == 1);
      await tester.ensureVisible(target);
      await until(() {
        final matches = target.hitTestable().evaluate();
        if (matches.length != 1) return false;
        final route = ModalRoute.of(matches.single);
        return (route?.isCurrent ?? true) &&
            (route?.animation?.isCompleted ?? true);
      });
    }

    Future<void> tapReady(Finder target) async {
      await readyTarget(target);
      await tester.tap(target);
    }

    Future<void> typePublicText(Finder field, String value) async {
      await tapReady(field);
      final editable = tester.state<EditableTextState>(find.descendant(
          of: field, matching: find.byType(EditableText), matchRoot: true));
      await until(() => editable.widget.focusNode.hasFocus);
      // In profile the framework rejects TestTextInput's magic client -1.
      // Supply ordinary characters at the public TextInputClient boundary;
      // validation, onChanged, button actions and all auth remain production.
      editable.updateEditingValue(TextEditingValue(
          text: value,
          selection: TextSelection.collapsed(offset: value.length)));
      await until(() => editable.widget.controller.text == value);
    }

    expect(Platform.isIOS, isTrue);
    expect(const bool.fromEnvironment('FIFE_RUN_FILE_TAP_JOURNEY'), isTrue);
    expect(AppEnv.localTestingBuild, isFalse);
    expect(
        isIsolatedNativeTestBundle(
            (await PackageInfo.fromPlatform()).packageName),
        isTrue);
    expect(runId.isNotEmpty, isTrue);
    progress = File(
        '${(await getApplicationDocumentsDirectory()).path}/fife-file-tap-journey.json');
    final otpInput = File(
        '${progress.parent.parent.path}/Library/Caches/fife-otp-input.json');
    await otpInput.parent.create(recursive: true);
    if (await otpInput.exists()) await otpInput.delete();
    addTearDown(() async {
      if (await otpInput.exists()) await otpInput.delete();
    });
    await checkpoint('normal_main');
    // No injected auth client, seeded setup flags, registration or key writes.
    await app.main();
    var sentOtp = false;
    var freshOtpSent = false;
    final setupDeadline = Stopwatch()..start();
    while (find.byType(FilePane).evaluate().isEmpty) {
      if (setupDeadline.elapsed > const Duration(minutes: 12)) {
        throw StateError('Owner-assisted setup timed out at $phase');
      }
      if (find.byType(FiFeOnboardingScreen).evaluate().isNotEmpty) {
        await checkpoint('onboarding');
        final view = tester.widget<PageView>(find.descendant(
            of: find.byType(FiFeOnboardingScreen),
            matching: find.byType(PageView)));
        final before = view.controller!.page!.round();
        await tester.tap(find.descendant(
            of: find.byType(FiFeOnboardingScreen),
            matching: find.byType(FilledButton)));
        await until(() =>
            find.byType(FiFeOnboardingScreen).evaluate().isEmpty ||
            (view.controller!.hasClients &&
                ((view.controller!.page ?? -1) - (before + 1)).abs() < 0.001));
      } else if (find.byType(PageAccessKeyNotice).evaluate().isNotEmpty) {
        throw StateError(
            'Existing test vault unexpectedly requested key generation; stopped without generating keys');
      } else if (find.byType(PageAccessKeyDecode).evaluate().isNotEmpty) {
        if (phase != 'owner_recovery_phrase') {
          await checkpoint('owner_recovery_phrase');
        }
      } else if (find.byType(PageSignin).evaluate().isNotEmpty) {
        final loc =
            AppLocalizations.of(tester.element(find.byType(PageSignin)))!;
        if (const bool.fromEnvironment('FIFE_FORCE_FRESH_OTP') &&
            !freshOtpSent &&
            find.text(loc.enterOtpLabel).evaluate().isNotEmpty) {
          await checkpoint('request_fresh_email_otp');
          await tester.tap(find.text(loc.useDifferentEmail));
          await until(() => find.text(loc.sendOtp).evaluate().isNotEmpty);
          sentOtp = false;
        }
        if (!sentOtp && find.text(loc.sendOtp).evaluate().isNotEmpty) {
          final button = find.widgetWithText(FilledButton, loc.sendOtp);
          await checkpoint('sign_in_wait_enabled');
          await until(() =>
              button.evaluate().isNotEmpty &&
              tester.widget<FilledButton>(button).onPressed != null &&
              appleViewerProbe()['nativeReady'] == true &&
              (binding.lifecycleState == null ||
                  binding.lifecycleState == AppLifecycleState.resumed));
          await checkpoint('sign_in_enter_email');
          final emailField = find.descendant(
              of: find.byType(PageSignin),
              matching: find.byType(TextFormField));
          await typePublicText(emailField, account);
          expect(
              tester.widget<TextFormField>(emailField).controller?.text ==
                  account,
              isTrue,
              reason: 'The real email field must contain the test account');
          await checkpoint('sign_in_reveal_button');
          await tester.ensureVisible(button);
          await until(() => button.hitTestable().evaluate().isNotEmpty);
          await checkpoint('sign_in_send_otp');
          await tester.tap(button);
          await checkpoint('sign_in_wait_otp');
          await until(
              () =>
                  find.byType(PageSignin).evaluate().isEmpty ||
                  find.text(loc.enterOtpLabel).evaluate().isNotEmpty ||
                  find.text(loc.retrySendingOtp).evaluate().isNotEmpty,
              timeout: const Duration(seconds: 30));
          sentOtp = true;
          freshOtpSent = true;
        }
        if (find.text(loc.enterOtpLabel).evaluate().isNotEmpty &&
            await otpInput.exists()) {
          // The owner-authorized monitor supplies one short-lived OTP over the
          // paired device channel. Never compile, log or retain its contents.
          Map<String, dynamic> input;
          try {
            input = jsonDecode(await otpInput.readAsString())
                as Map<String, dynamic>;
          } finally {
            await otpInput.delete();
          }
          final code = input['otp'];
          if (input['runId'] != runId ||
              code is! String ||
              !RegExp(r'^\d{6}$').hasMatch(code)) {
            throw StateError('Invalid private OTP input');
          }
          expect(find.text(loc.sentSixDigitCodeTo(account)), findsOneWidget);
          await checkpoint('verify_authorized_email_otp');
          await typePublicText(
              find.descendant(
                  of: find.byType(PageSignin),
                  matching: find.byType(TextFormField)),
              code);
          final verify = find.widgetWithText(
              FilledButton,
              find.text(loc.retryVerification).evaluate().isNotEmpty
                  ? loc.retryVerification
                  : loc.verifyOtp);
          await tester.ensureVisible(verify);
          await until(() => verify.hitTestable().evaluate().isNotEmpty);
          await tester.tap(verify);
          checks['authorizedOtpSubmittedThroughUi'] = true;
        }
        final next = find.text(loc.enterOtpLabel).evaluate().isNotEmpty
            ? 'owner_email_otp'
            : 'sign_in';
        if (phase != next) await checkpoint(next);
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    expect((await ModelProfile.get())?.email?.toLowerCase() == account, isTrue,
        reason: 'Only the authorized general-test account may be used');
    checks['normalSetupAndVerifiedOwner'] = true;
    final loc = AppLocalizations.of(tester.element(find.byType(FilePane)))!;
    final device = await getDeviceHash();
    final db = await StorageSqlite.instance.database;
    Future<void> cleanReplicaTransfer(String replicaRun) async {
      expect(replicaRun, matches(RegExp(r'^ios-tap-journey-[A-Za-z0-9-]+$')));
      final replicaId = 'fife-file-tap-remote-$replicaRun-file';
      final task = await ModelItemTask.get(replicaId);
      // Never remove resources from an in-flight transfer, even in a fixture.
      expect(task?.state, isNot(TransferTaskState.running));
      await task?.delete();
      await DownloadStaging(
        baseDirectory: await getAppTempDirectory(),
        itemId: replicaId,
        fileHash: '',
        partCount: 0,
        expectedPlaintextLength: 0,
      ).cleanup();
      final cached = File(
          '${progress.parent.path}/FiFe/FiFe remote taps $replicaRun/$textName');
      if (await cached.exists()) {
        expect(await cached.readAsString(), sourceContents);
        await cached.delete();
      }
      if (await cached.parent.exists() && await cached.parent.list().isEmpty) {
        await cached.parent.delete();
      }
    }

    const previousRun = String.fromEnvironment('FIFE_NATIVE_PREVIOUS_RUN_ID');
    if (previousRun.isNotEmpty) {
      expect(previousRun, startsWith('ios-tap-journey-'));
      final previousReplica = 'fife-file-tap-remote-$previousRun-file';
      expect(await ModelItem.get(previousReplica), isNull);
      // Only residue from this driver's retained, failed synthetic replica.
      await cleanReplicaTransfer(previousRun);
      checks['previousSyntheticTransferCleaned'] = true;
    }
    Future<ModelItem?> itemNamed(String parent, String name) async {
      final rows = await db.query('items',
          where: 'parent_id = ? AND name = ? AND archived_at = 0',
          whereArgs: [parent, name]);
      return rows.isEmpty ? null : await ModelItem.fromMap(rows.single);
    }

    Future<void> vaultRoot() async {
      final crumb = find.descendant(
          of: find.byType(BreadcrumbTrail), matching: find.text('FiFe'));
      await tapReady(crumb);
      await until(() => find.byKey(ValueKey(device)).evaluate().isNotEmpty);
    }

    Future<void> tapItem(String id) async {
      final row = find.byKey(ValueKey(id));
      await tapReady(row);
    }

    await checkpoint('open_current_device');
    await vaultRoot();
    await tapItem(device);
    await until(() => find.byIcon(LucideIcons.plus).evaluate().isNotEmpty);
    var root = await itemNamed(device, folderName);
    if (root == null) {
      await checkpoint('owner_choose_generated_folder');
      await tester.tap(find.byIcon(LucideIcons.plus));
      await until(() => find.byType(AlertDialog).evaluate().isNotEmpty,
          timeout: const Duration(minutes: 4));
      expect(
          find.descendant(
              of: find.byType(AlertDialog), matching: find.text(folderName)),
          findsOneWidget,
          reason: 'Only the generated external test folder may be added');
      await tester.tap(find.descendant(
          of: find.byType(AlertDialog), matching: find.text(loc.confirm)));
      await until(() async => await itemNamed(device, folderName) != null);
      root = await itemNamed(device, folderName);
    }
    checks['realFilesFolderGrant'] = true;
    await checkpoint('scan_and_upload_generated_text');
    await until(
        () async => (await itemNamed(root!.id, textName))?.fileHash != null);
    final local = (await itemNamed(root!.id, textName))!;
    final unknown = (await itemNamed(root.id, unknownName))!;
    await until(
        () async =>
            ((await ModelFile.get(local.fileHash!))?.uploadedAt ?? 0) > 0,
        timeout: const Duration(minutes: 3));
    expect(
        await LocalItemAccess.withAccess(
            local.id, (path) => File(path).readAsString()),
        sourceContents);
    checks['sourceRetainedAfterUpload'] = true;
    final actualViewer = FileViewerPlatform.instance;
    expect(actualViewer, isA<NativeFileViewer>());
    final viewer = _ObservedViewer(actualViewer);
    FileViewerPlatform.instance = viewer;
    final remoteRoot = 'fife-file-tap-remote-$runId';
    final remoteId = '$remoteRoot-file';
    try {
      Future<void> open(
          String id, String label, FileViewResult expected) async {
        await checkpoint(label);
        await until(() =>
            appleViewerProbe()['nativeReady'] == true &&
            (binding.lifecycleState == null ||
                binding.lifecycleState == AppLifecycleState.resumed));
        final before = viewer.completions;
        await tapItem(id);
        await until(() => viewer.completions > before,
            timeout: const Duration(minutes: 10));
        expect(viewer.last, expected);
        if (expected == FileViewResult.unsupported) {
          await until(() =>
              find.text(loc.noSupportedApplication).evaluate().isNotEmpty);
          expect(find.text(loc.longPressToDownload), findsNothing);
          await until(
              () => find.text(loc.noSupportedApplication).evaluate().isEmpty);
        }
        checks[label] = true;
        await checkpoint('${label}_passed');
      }

      await tapItem(root.id);
      await open(local.id, 'local_explorer_preview', FileViewResult.opened);
      await open(
          unknown.id, 'local_explorer_unsupported', FileViewResult.unsupported);

      // Supply only another device's replicated metadata as test input. It
      // references our real uploaded synthetic bytes. No setup/key/permission
      // transition is supplied, and these rows never enter the changes queue.
      final changesBefore = await db.query('changes',
          where: 'id IN (?, ?)', whereArgs: [remoteRoot, remoteId]);
      expect(changesBefore, isEmpty);
      await db.insert('items', {
        'id': remoteRoot,
        'name': 'FiFe remote taps $runId',
        'parent_id': 'fife',
        'root_id': remoteRoot,
        'is_folder': 1,
        'archived_at': 0
      });
      final replica = local.toMap()
        ..addAll({
          'id': remoteId,
          'parent_id': remoteRoot,
          'root_id': remoteRoot,
          'path': null,
          'bookmark': null,
        });
      await db.insert('items', replica);
      expect((await ModelItem.get(remoteId))!.size, sourceContents.length);
      expect(
          await db.query('changes',
              where: 'id IN (?, ?)', whereArgs: [remoteRoot, remoteId]),
          isEmpty);
      expect(await ModelItem.isLocalPath(local.id), isTrue);
      expect(await ModelItem.isLocalPath(remoteId), isFalse);
      final remotePath = await ModelItem.getPathForItem(remoteId);
      expect(await File(remotePath).exists(), isFalse);
      await vaultRoot();
      await tapItem(remoteRoot);
      final calls = viewer.calls;
      await checkpoint('remote_missing_download_guidance');
      await tapItem(remoteId);
      await until(
          () => find.text(loc.longPressToDownload).evaluate().isNotEmpty);
      expect(viewer.calls, calls);
      await until(() => find.text(loc.longPressToDownload).evaluate().isEmpty);
      final remoteRow = find.byKey(ValueKey(remoteId));
      await readyTarget(remoteRow);
      await tester.longPress(remoteRow);
      await until(() => find.byTooltip(loc.download).evaluate().isNotEmpty);
      await checkpoint('remote_real_download');
      await tester.tap(find.byTooltip(loc.download));
      await until(() async {
        try {
          return await File(remotePath).readAsString() == sourceContents;
        } on FileSystemException {
          return false;
        }
      }, timeout: const Duration(minutes: 3));
      expect(await File(remotePath).readAsString(), sourceContents);
      if (find.byTooltip(loc.cancel).evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip(loc.cancel));
      }
      await open(remoteId, 'remote_explorer_preview', FileViewResult.opened);
      await checkpoint('open_search_menu');
      await tapReady(find.byIcon(LucideIcons.moreVertical));
      await checkpoint('select_search_menu_item');
      await tapReady(find.text(loc.search));
      await until(() => find.byType(SearchScreen).evaluate().isNotEmpty);
      await checkpoint('search_public_query');
      await typePublicText(find.byType(TextField), 'as0pgk65');
      await until(() =>
          find.byKey(ValueKey(remoteId)).evaluate().isNotEmpty &&
          find.byKey(ValueKey(local.id)).evaluate().isNotEmpty);
      await open(local.id, 'local_search_preview', FileViewResult.opened);
      await open(remoteId, 'remote_search_preview', FileViewResult.opened);
      await open(
          unknown.id, 'local_search_unsupported', FileViewResult.unsupported);
      await checkpoint('select_downloaded_remote_copy');
      await readyTarget(remoteRow);
      await tester.longPress(remoteRow);
      await until(() => find.byTooltip(loc.delete).evaluate().isNotEmpty);
      expect(find.byTooltip(loc.archive), findsNothing);
      await checkpoint('delete_downloaded_remote_copy');
      await tapReady(find.byTooltip(loc.delete));
      await until(() async => !await File(remotePath).exists());
      expect((await ModelItem.get(remoteId))!.archivedAt, 0);
      expect(
          await LocalItemAccess.withAccess(
              local.id, (path) => File(path).readAsString()),
          sourceContents);
      checks['remoteCopyDeletionPreservesSource'] = true;
      await checkpoint('remote_copy_deleted_source_retained');
      await tapReady(find.descendant(
          of: find.byType(SearchScreen),
          matching: find.byIcon(LucideIcons.arrowLeft)));
      await until(() => find.byType(SearchScreen).evaluate().isEmpty);
      await vaultRoot();
    } finally {
      await viewer.cancel();
      FileViewerPlatform.instance = actualViewer;
      // Delete only the two local synthetic replica rows, never server/vault data.
      await cleanReplicaTransfer(runId);
      await db.delete('items', where: 'id = ?', whereArgs: [remoteId]);
      await db.delete('items', where: 'id = ?', whereArgs: [remoteRoot]);
      checks['syntheticReplicaRowsRemoved'] = true;
    }
    await tapItem(device);
    await until(() => find.byKey(ValueKey(root!.id)).evaluate().isNotEmpty);
    await vaultRoot();
    expect(find.byKey(ValueKey(remoteRoot)), findsNothing);
    checks['normalReturnNavigation'] = true;
    await checkpoint('file_tap_complete');

    if (const bool.fromEnvironment('FIFE_RUN_APP_LOCK_VIEWER_CHECKS')) {
      final lock =
          tester.widget<AppLockGate>(find.byType(AppLockGate)).controller;
      final initialPolicy = await ModelAppLockStore().read();
      expect(initialPolicy.enabled, isFalse,
          reason:
              'This optional check must start with the test preview lock off');
      Future<void> settings() async {
        await tapReady(find.byIcon(LucideIcons.moreVertical));
        await tapReady(find.text(loc.settings));
        await until(() => find.byType(SettingsPage).evaluate().isNotEmpty);
      }

      Future<void> backFromSettings() async {
        await tapReady(find.descendant(
            of: find.byType(SettingsPage),
            matching: find.byIcon(LucideIcons.arrowLeft)));
        await until(() => find.byType(SettingsPage).evaluate().isEmpty);
      }

      Future<void> timeoutMinutes(int minutes) async {
        final slider = find.byKey(const ValueKey('app-lock-timeout'));
        await readyTarget(slider);
        final rect = tester.getRect(slider);
        final choices = [1, 5, 10, 15, 20, 25, 30];
        final index = choices.indexOf(minutes);
        expect(index, isNonNegative);
        await tester.tapAt(Offset(
            rect.left + 24 + (rect.width - 48) * index / 6, rect.center.dy));
        await until(() => lock.minutes == minutes && !lock.busy);
      }

      await settings();
      await checkpoint('owner_enable_app_lock');
      await tapReady(find.byKey(const ValueKey('app-lock-switch')));
      await until(() => lock.enabled && !lock.busy && !lock.locked,
          timeout: const Duration(minutes: 10));
      await timeoutMinutes(1);
      await backFromSettings();
      await vaultRoot();
      await tapItem(device);
      await tapItem(root.id);
      final lockedViewer = _ObservedViewer(actualViewer);
      FileViewerPlatform.instance = lockedViewer;
      DateTime? leftSceneAt, returnedSceneAt;
      var authRequestedAfterAway = false;
      void sceneChanged() {
        if (leftSceneAt == null && !lock.foreground) {
          leftSceneAt = DateTime.now().toUtc();
        } else if (leftSceneAt != null &&
            returnedSceneAt == null &&
            lock.foreground) {
          returnedSceneAt = DateTime.now().toUtc();
        }
        if (leftSceneAt != null && lock.locked && lock.busy) {
          authRequestedAfterAway = true;
        }
      }

      try {
        final before = lockedViewer.completions;
        await checkpoint('hold_reading_preview_65_seconds');
        await tapItem(local.id);
        await until(() =>
            lockedViewer.calls > 0 &&
            appleViewerProbe()['hostClass'] != 'FlutterViewController');
        final reading = Stopwatch()..start();
        while (reading.elapsed < const Duration(seconds: 65)) {
          expect(lock.foreground, isTrue,
              reason: 'Native reading is still foreground application use');
          expect(lock.locked, isFalse);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        metrics['nativeReadingMilliseconds'] = reading.elapsedMilliseconds;
        await checkpoint('owner_dismiss_reading_preview');
        await until(() => lockedViewer.completions > before,
            timeout: const Duration(minutes: 10));
        expect(lockedViewer.last, FileViewResult.opened);
        expect(lock.locked, isFalse);
        checks['nativeReadingBeyondTimeoutRemainsAuthorized'] = true;
        await until(() =>
            binding.lifecycleState == AppLifecycleState.resumed &&
            appleViewerProbe()['nativeReady'] == true);
        lock.addListener(sceneChanged);
        final beforeBackground = lockedViewer.completions;
        await checkpoint('owner_background_preview_65_seconds');
        await tapItem(local.id);
        await until(() => leftSceneAt != null,
            timeout: const Duration(minutes: 10));
        await until(
            () =>
                returnedSceneAt != null &&
                authRequestedAfterAway &&
                lock.foreground &&
                !lock.locked &&
                !lock.busy,
            timeout: const Duration(minutes: 10));
        metrics['nativeSceneAwayMilliseconds'] =
            returnedSceneAt!.difference(leftSceneAt!).inMilliseconds;
        expect(metrics['nativeSceneAwayMilliseconds'],
            greaterThanOrEqualTo(60000));
        expect(lockedViewer.completions, greaterThan(beforeBackground));
        expect(lockedViewer.last, FileViewResult.cancelled);
        expect(
            await LocalItemAccess.withAccess(
                local.id, (path) => File(path).readAsString()),
            sourceContents);
        checks['realSceneTimeoutAuthenticatesAndClosesNativePreview'] = true;
        await checkpoint('native_app_lock_return_verified');
      } finally {
        lock.removeListener(sceneChanged);
        await lockedViewer.cancel();
        FileViewerPlatform.instance = actualViewer;
      }
      await until(() =>
          binding.lifecycleState == AppLifecycleState.resumed &&
          appleViewerProbe()['nativeReady'] == true);
      await settings();
      await timeoutMinutes(initialPolicy.minutes);
      await checkpoint('owner_restore_app_lock_off');
      await tapReady(find.byKey(const ValueKey('app-lock-switch')));
      await until(() => !lock.enabled && !lock.busy,
          timeout: const Duration(minutes: 10));
      final restored = await ModelAppLockStore().read();
      expect(restored.enabled, initialPolicy.enabled);
      expect(restored.minutes, initialPolicy.minutes);
      checks['appLockPolicyRestored'] = true;
      await backFromSettings();
      await vaultRoot();
    }
    await checkpoint('complete');
  }, timeout: const Timeout(Duration(minutes: 60)));
}
