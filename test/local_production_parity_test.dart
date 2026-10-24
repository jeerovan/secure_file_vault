import 'dart:convert';
import 'dart:async';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/services/service_recovery_reset.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/utils/common.dart' as common;
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/ui/pages/page_device_register.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/ui/pages/page_subscription.dart';
import 'package:file_vault_bb/main.dart' as application;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'support/recovery_reset_fixture.dart';
import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  late bool purchasesConfigured;
  Future<void> Function()? beforeCustomerInfo;
  final billingCalls = <MethodCall>[];
  final customerInfo = {
    'entitlements': {'all': {}, 'active': {}},
    'allPurchaseDates': {},
    'activeSubscriptions': [],
    'allPurchasedProductIdentifiers': [],
    'nonSubscriptionTransactions': [],
    'firstSeen': '2026-10-21T00:00:00Z',
    'originalAppUserId': 'server-local-user',
    'allExpirationDates': {},
    'requestDate': '2026-10-21T00:00:00Z'
  };
  const purchases = MethodChannel('purchases_flutter');
  const deviceInfo = MethodChannel('dev.fluttercommunity.plus/device_info');
  setUp(() async {
    fixture = await SyncFixture.create();
    purchasesConfigured = false;
    beforeCustomerInfo = null;
    billingCalls.clear();
    await ModelSetting.set(AppString.localTesting.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, (call) async {
      billingCalls.add(call);
      if (call.method == 'isConfigured') return purchasesConfigured;
      if (call.method == 'setupPurchases') purchasesConfigured = true;
      if (call.method == 'logIn') {
        return {'customerInfo': customerInfo, 'created': true};
      }
      if (call.method == 'getCustomerInfo') {
        await beforeCustomerInfo?.call();
        return customerInfo;
      }
      if (call.method == 'getOfferings') return {'all': {}, 'current': null};
      if (call.method == 'isAnonymous') return true;
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            deviceInfo,
            (_) async => {
                  'computerName': 'Fixture Mac',
                  'hostName': 'fixture',
                  'arch': 'arm64',
                  'model': 'fixture',
                  'modelName': 'fixture',
                  'kernelVersion': 'fixture',
                  'osRelease': 'fixture',
                  'majorVersion': 12,
                  'minorVersion': 0,
                  'patchVersion': 0,
                  'activeCPUs': 1,
                  'memorySize': 1024,
                  'cpuFrequency': 1,
                  'systemGUID': 'fixture-device'
                });
  });
  tearDown(() async {
    await fixture.dispose();
    for (final channel in [purchases, deviceInfo]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    }
  });

  Future<void> until(WidgetTester tester, Future<bool> Function() ready) async {
    final elapsed = Stopwatch()..start();
    while (!(await tester.runAsync(ready))! &&
        elapsed.elapsed < const Duration(seconds: 10)) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(await tester.runAsync(ready), isTrue);
  }

  Future<AppSetupState> mount(WidgetTester tester, Widget page) async {
    final setup = (await tester.runAsync(() async {
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      final state = AppSetupState(SecureStorage());
      // Finish startup before a short-lived page tears down its SQL/platform
      // fixture; the constructor's read is otherwise still pending at dispose.
      await state.recheckStatus();
      return state;
    }))!;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: setup,
        child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: page)));
    return setup;
  }

  group('local authentication and registration', () {
    for (final accepted in [true, false]) {
      testWidgets(
          'sign-in ${accepted ? 'stores' : 'rejects missing'} server session proof',
          (tester) async {
        await tester.runAsync(() async {
          await (await fixture.db).delete('profiles');
          await ModelSetting.delete(AppString.signedIn.string);
          await ModelSetting.delete(AppString.deviceUuid.string);
          await ModelSetting.set(AppString.simulateTesting.string, 'yes');
        });
        var authentications = 0;
        purchasesConfigured = true;
        await http.runWithClient(() async {
          final setup = await mount(tester, const PageSignin());
          await tester.enterText(
              find.byType(TextFormField), common.localTestEmailId);
          await tester.tap(find.byType(FilledButton));
          await until(
              tester,
              () async => accepted
                  ? setup.currentStep == SetupStep.checkAccessKey
                  : find
                          .text('Failed to send OTP. Please try again.')
                          .evaluate()
                          .isNotEmpty ||
                      tester
                                  .widget<FilledButton>(
                                      find.byType(FilledButton))
                                  .onPressed !=
                              null &&
                          authentications > 0);
          expect(authentications, 1);
          await tester.runAsync(() async {
            if (accepted) {
              expect(fixture.secrets[AppString.sessionCookie.string],
                  'fife-local.server-session-proof');
              expect((await ModelProfile.get())?.id, 'server-local-user');
              expect(common.simulateTesting(), isFalse);
              expect(
                  await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
              expect(await ModelSetting.getRaw(AppString.otpSentAt.string),
                  isEmpty);
              if (common.subscriptionsSupported) {
                expect(
                    billingCalls
                        .where((call) => call.method == 'logIn')
                        .single
                        .arguments['appUserID'],
                    'server-local-user');
              }
            } else {
              expect(fixture.secrets[AppString.sessionCookie.string], isNull);
              expect(await ModelProfile.get(), isNull);
              expect(await ModelSetting.getRaw(AppString.signedIn.string),
                  isEmpty);
            }
          });
        },
            () => MockClient((request) async {
                  if (request.url.path == '/api/keys') {
                    expect(request.headers['x-fife-session'],
                        'fife-local.server-session-proof');
                    expect(request.headers['device_uuid'], isNull);
                    return http.Response(
                        jsonEncode({
                          'success': 1,
                          'data': {
                            'cipher': null,
                            'nonce': null,
                            'key_state': 'missing',
                            'vault_generation': 'legacy'
                          }
                        }),
                        200);
                  }
                  expect(request.url.path, '/api/local-test/session');
                  authentications++;
                  return http.Response(
                      jsonEncode(accepted
                          ? {
                              'success': 1,
                              'data': {
                                'sessionToken':
                                    'fife-local.server-session-proof',
                                'user': {
                                  'id': 'server-local-user',
                                  'email': common.localTestEmailId
                                }
                              }
                            }
                          : {'success': 0, 'message': 14}),
                      200);
                }));
      });
    }

    testWidgets(
        'device registration restores FiFe root and retains notification token',
        (tester) async {
      fixture.secrets[AppString.fcmId.string] = 'stored-notification-token';
      await tester
          .runAsync(() => ModelSetting.delete(AppString.deviceUuid.string));
      Map<String, dynamic>? registered;
      await http.runWithClient(() async {
        final setup = await mount(tester, const PageRegisterDevice());
        await until(
            tester, () async => setup.currentStep == SetupStep.explorer);
        expect(registered?['notificationId'], 'stored-notification-token');
        expect(registered?['device_uuid'],
            await tester.runAsync(common.getDeviceUuid));
        await tester.runAsync(() async {
          expect((await ModelItem.get('fife'))!.name, 'FiFe');
          expect((await ModelItem.get(await common.getDeviceHash()))!.parentId,
              'fife');
        });
        expect(tester.takeException(), isNull);
      },
          () => MockClient((request) async {
                expect(request.url.path, '/api/devices');
                registered = jsonDecode(request.body) as Map<String, dynamic>;
                return http.Response('{"success":1}', 200);
              }));
    });
  }, skip: !common.AppEnv.localTestingBuild);

  test('purchase SDK initialization is identical for local and ordinary builds',
      () async {
    await application.initializePurchases();
    expect(purchasesConfigured, isTrue);
    expect(billingCalls.where((call) => call.method == 'setupPurchases'),
        hasLength(1));
    expect(
        billingCalls
            .singleWhere((call) => call.method == 'setupPurchases')
            .arguments['appUserId'],
        'fixture-user');
  },
      skip: !common.subscriptionsSupported ||
          (common.AppEnv.rcAndroidKey.isEmpty &&
              common.AppEnv.rcIosKey.isEmpty));

  for (final configured in [true, false]) {
    testWidgets(
        'subscription UI keeps production actions with SDK configured=$configured',
        (tester) async {
      purchasesConfigured = configured;
      await mount(tester, const SubscriptionPage());
      await until(tester,
          () async => find.text('Restore Purchases').evaluate().isNotEmpty);
      expect(
          billingCalls.where((call) => call.method == 'getCustomerInfo').length,
          configured ? 1 : 0);
      expect(billingCalls.where((call) => call.method == 'getOfferings').length,
          configured ? 1 : 0);
      expect(billingCalls.any((call) => call.method.startsWith('purchase')),
          isFalse);
      expect(tester.takeException(), isNull);
    }, skip: !common.subscriptionsSupported);
  }

  test('local builds retain production subscription capabilities', () {
    final original = common.revenueCatSupported;
    try {
      common.revenueCatSupported = true;
      expect(common.subscriptionsSupported, isTrue);
      common.revenueCatSupported = false;
      expect(common.subscriptionsSupported, isFalse);
    } finally {
      common.revenueCatSupported = original;
    }
  });

  testWidgets('leaving subscription loading ignores the late SDK result',
      (tester) async {
    purchasesConfigured = true;
    final release = Completer<void>();
    beforeCustomerInfo = () => release.future;
    addTearDown(() {
      if (!release.isCompleted) release.complete();
    });
    await mount(tester, const SubscriptionPage());
    await until(
        tester,
        () async =>
            billingCalls.any((call) => call.method == 'getCustomerInfo'));
    await tester.pumpWidget(const SizedBox.shrink());
    release.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  }, skip: !common.subscriptionsSupported);

  for (final expired in [true, false]) {
    testWidgets(
        'cached subscription respects expiry when SDK is unavailable: expired=$expired',
        (tester) async {
      await tester.runAsync(() async => (await fixture.db).update('profiles', {
            'plan_expires_at': DateTime.now().millisecondsSinceEpoch +
                (expired ? -1 : 1) * const Duration(days: 1).inMilliseconds
          }));
      await mount(tester, const SubscriptionPage());
      await until(
          tester,
          () async =>
              find.byType(CircularProgressIndicator).evaluate().isEmpty);
      final loc =
          AppLocalizations.of(tester.element(find.byType(SubscriptionPage)))!;
      expect(find.text(loc.subscriptionExpiredTitle),
          expired ? findsOneWidget : findsNothing);
      expect(find.text(loc.restorePurchases),
          expired ? findsOneWidget : findsNothing);
      expect(billingCalls.any((call) => call.method == 'getCustomerInfo'),
          isFalse);
      expect(tester.takeException(), isNull);
    }, skip: !common.subscriptionsSupported);
  }

  for (final debug in [true, false]) {
    test('desktop auto sync uses production cadence with debug=$debug', () {
      final original = common.isDebugEnabled;
      Duration? interval;
      try {
        common.isDebugEnabled = debug;
        runZoned(() => SyncUtils().startAutoSync(), zoneSpecification:
            ZoneSpecification(
                createPeriodicTimer: (self, parent, zone, duration, callback) {
          interval = duration;
          return parent.createPeriodicTimer(zone, duration, callback);
        }));
        expect(interval, const Duration(minutes: 15));
      } finally {
        SyncUtils().stopAutoSync();
        common.isDebugEnabled = original;
      }
    });
  }

  group('authenticated local recovery', () {
    test('uses the normal reset and preserves its authentication after cleanup',
        () async {
      fixture.secrets.remove(AppString.masterKey.string);
      fixture.secrets.remove(AppString.fileHashKey.string);
      fixture.secrets[AppString.sessionCookie.string] =
          'fife-local.session-proof';
      await ModelSetting.delete(AppString.deviceUuid.string);
      final peer = RecoveryResetPeer()
        ..requiredSessionProof = 'fife-local.session-proof'
        ..requiredAuthService = 'local-test';
      final service = peer.service();
      final result = await service.confirm();
      expect(result.phase, RecoveryResetPhase.waiting);
      expect(peer.prepareCalls, 1);
      expect(peer.confirmCalls, 1);
      expect(common.localTesting(), isTrue);
      expect(fixture.secrets[AppString.sessionCookie.string],
          'fife-local.session-proof');
      expect(await common.getSignedInUserId(), 'fixture-user');
      expect(await common.getMasterKey(), isNull);
      peer.phase = 'ready';
      expect((await service.refresh()).phase, RecoveryResetPhase.bootstrap);
      expect(fixture.secrets[AppString.recoveryResetStage.string], isNull);
      expect(await common.getMasterKey(), isNull);
      expect(common.localTesting(), isTrue);
    });

    test('forced logout clears local authentication and private data',
        () async {
      fixture.secrets[AppString.sessionCookie.string] =
          'fife-local.session-proof';
      expect(await SessionCleanup.instance.request(), isTrue);
      expect(common.localTesting(), isFalse);
      expect(fixture.secrets, isEmpty);
      expect(await common.getSignedInUserId(), isNull);
    });
  }, skip: !common.AppEnv.localTestingBuild);
}
