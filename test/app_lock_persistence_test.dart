import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/ui/pages/page_session_cleanup.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/app_lock_fixture.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() => fixture.dispose());

  test(
      'lock policy survives SQLite reopening and ignores stale preference cache',
      () async {
    final store = ModelAppLockStore();
    await store.setEnabled(true);
    await store.setTimeout(25);
    await StorageSqlite.instance.close();
    ModelSetting.clear();
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    ModelSetting.settingJson[AppString.appLockEnabled.string] = 'no';
    ModelSetting.settingJson[AppString.appLockTimeoutMinutes.string] = '1';
    final policy = await store.read();
    expect(policy.enabled, isTrue);
    expect(policy.minutes, 25);
    final lock = AppLockController(
        store: store, authenticator: FakeAppLockAuthenticator());
    addTearDown(lock.dispose);
    await lock.load();
    expect(lock.concealed, isTrue);
    expect(lock.minutes, 25);
  });

  test(
      'missing policy is opt-in; malformed saved policy cannot disable protection',
      () async {
    final store = ModelAppLockStore();
    expect((await store.read()).enabled, isFalse);
    expect((await store.read()).minutes, 5);
    await ModelSetting.set(AppString.appLockEnabled.string, 'malformed');
    await ModelSetting.set(AppString.appLockTimeoutMinutes.string, '29');
    final policy = await store.read();
    expect(policy.enabled, isTrue);
    expect(policy.minutes, 5);
  });

  test('lock mutations cannot publish into a revoked session', () async {
    SessionWork.invalidate('revoked');
    final store = ModelAppLockStore();
    await expectLater(
        store.setEnabled(true), throwsA(isA<SessionInvalidated>()));
    await expectLater(store.setTimeout(30), throwsA(isA<SessionInvalidated>()));
    SessionWork.complete('revoked');
    expect((await store.read()).enabled, isFalse);
  });

  testWidgets(
      'reauthentication during biometric proof cannot leave App lock busy',
      (tester) async {
    final auth = FakeAppLockAuthenticator()..result = false;
    final lock = AppLockController(
        store: MemoryAppLockStore()..enabled = true, authenticator: auth);
    final locale = LocaleProvider();
    final setup = (await tester.runAsync(() async {
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'no');
      expect(await SessionCleanup.instance.expiredAuthentication(), isTrue);
      final state = AppSetupState(SecureStorage());
      await state.recheckStatus();
      return state;
    }))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      SyncUtils().stopAutoSync();
      setup.dispose();
      locale.dispose();
      lock.dispose();
    });
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: setup),
      ChangeNotifierProvider.value(value: locale)
    ], child: MyApp(appLock: lock)));
    await tester.pumpAndSettle();
    expect(lock.ready, isTrue);
    final response = Completer<bool>();
    var oldRequested = false;
    auth.onAuthenticate = (_) {
      if (oldRequested) return Future.value(false);
      oldRequested = true;
      return response.future;
    };
    final old = lock.unlock(testAppLockPrompt);
    await tester.pump();
    expect(lock.busy, isTrue);
    await tester.runAsync(() => SessionCleanup.instance.activateAuthentication(
        expectedRevision: SessionWork.revision, writeCredentials: () async {}));
    EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'authentication',
        key: EventKey.authenticated));
    await tester.pump();
    response.complete(true);
    expect(await old, isFalse);
    await tester.pump();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(lock.ready, isTrue);
    expect(lock.busy, isFalse);
    expect(lock.locked, isTrue);
    expect(auth.cancellations, 1);
    auth.onAuthenticate = null;
    auth.result = true;
    expect(await lock.unlock(testAppLockPrompt), isTrue);
  });

  testWidgets(
      'the real app root gates startup and resets obsolete proof after revocation',
      (tester) async {
    final store = ModelAppLockStore();
    final auth = FakeAppLockAuthenticator()..result = false;
    late AppSetupState setup;
    final locale = LocaleProvider();
    final lock = AppLockController(store: store, authenticator: auth);
    final states = <String>[];
    lock.addListener(() => states.add(
        'ready=${lock.ready},busy=${lock.busy},failure=${lock.failure},revision=${SessionWork.revision},active=${SessionWork.active}'));
    await tester.runAsync(() async {
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'no');
      await store.setEnabled(true);
      setup = AppSetupState(SecureStorage());
      await setup.recheckStatus();
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
      locale.dispose();
      lock.dispose();
    });
    await tester.runAsync(() => tester.pumpWidget(MultiProvider(providers: [
          ChangeNotifierProvider.value(value: setup),
          ChangeNotifierProvider.value(value: locale),
        ], child: MyApp(appLock: lock))));
    for (var n = 0; n < 20 && !lock.ready; n++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(lock.ready, isTrue);
    expect(find.byType(PageSignin), findsNothing);
    expect(find.text('FiFe is locked'), findsOneWidget);
    auth.result = true;
    await lock.unlock(testAppLockPrompt);
    await tester.pumpAndSettle();
    expect(find.byType(PageSignin), findsOneWidget);

    // Simulate the same invalidation/completion events used by native cleanup.
    SessionWork.invalidate('new-local-session');
    EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'session',
        key: EventKey.sessionInvalidated));
    await tester.pump();
    expect(find.byType(PageSignin), findsNothing);
    expect(find.byType(PageSessionCleanup), findsOneWidget,
        reason: 'Revoked devices must be able to retry safe local cleanup');
    await tester
        .runAsync(() => SessionWork.maintain(() => store.setEnabled(false)));
    await tester.runAsync(() =>
        File('${fixture.directory.path}/fife-session-state.json').writeAsString(
            jsonEncode({'revision': 'new-local-session', 'pending': false})));
    SessionWork.complete('new-local-session');
    EventStream().publish(
        AppEvent(type: EventType.system, id: 'signout', key: EventKey.signout));
    await tester.pump();
    for (var n = 0;
        n < 200 && (!lock.ready || setup.currentStep != SetupStep.signin);
        n++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    expect(lock.ready, isTrue,
        reason: '${setup.currentStep}: ${states.join('; ')}');
    expect(setup.currentStep, SetupStep.signin);
    await tester.pumpAndSettle();
    expect(lock.enabled, isFalse);
    expect(find.byType(PageSignin), findsOneWidget);
  });
}
