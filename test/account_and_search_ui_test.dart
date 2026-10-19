import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_check.dart';
import 'package:file_vault_bb/ui/pages/page_file_info.dart';
import 'package:file_vault_bb/ui/pages/page_search.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';

Future<void> waitForUi(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 250 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), isTrue);
}

Future<void> withUi(
    WidgetTester tester,
    Future<void> Function(SyncFixture fixture, AppSetupState setup)
        action) async {
  await tester.runAsync(() async {
    final fixture = await SyncFixture.create();
    final setup = AppSetupState(SecureStorage());
    try {
      await waitForUi(tester, () => setup.currentStep == SetupStep.onboard);
      await action(fixture, setup);
      // A visible row starts asynchronous disk/database status checks. Let its
      // loading state finish before this isolated fixture closes the database.
      await waitForUi(tester,
          () => find.byType(CircularProgressIndicator).evaluate().isEmpty);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      setup.dispose();
      await fixture.dispose();
    }
  });
}

Future<void> mount(WidgetTester tester, AppSetupState setup, Widget page) =>
    tester.pumpWidget(ChangeNotifierProvider<AppSetupState>.value(
      value: setup,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    ));

void main() {
  for (final existing in [false, true]) {
    testWidgets(
        'key onboarding routes to ${existing ? 'recovery for existing keys' : 'generation for a new account'}',
        (tester) async {
      await http.runWithClient(
          () => withUi(tester, (fixture, setup) async {
                await mount(tester, setup, const PageAccessKeyCheck());
                await waitForUi(
                    tester,
                    () =>
                        setup.currentStep ==
                        (existing
                            ? SetupStep.decodeAccessKey
                            : SetupStep.generateAccessKey));
                expect(fixture.secrets[AppString.keyCipher.string],
                    existing ? 'server-cipher' : isNull);
                expect(fixture.secrets[AppString.keyNonce.string],
                    existing ? 'server-nonce' : isNull);
              }),
          () => MockClient((request) async {
                expect(request.url.path, endsWith('/keys'));
                return http.Response(
                    jsonEncode(existing
                        ? {
                            'success': 1,
                            'data': {
                              'cipher': 'server-cipher',
                              'nonce': 'server-nonce'
                            }
                          }
                        : {'success': 0, 'message': '1'}),
                    200);
              }));
    });
  }

  testWidgets('key check recovers from a network error using the retry action',
      (tester) async {
    var calls = 0;
    AppHttpClients.closeAll();
    await http.runWithClient(
        () => withUi(tester, (fixture, setup) async {
              await mount(tester, setup, const PageAccessKeyCheck());
              final loc = AppLocalizations.of(
                  tester.element(find.byType(PageAccessKeyCheck)))!;
              await waitForUi(
                  tester, () => find.text(loc.tryAgain).evaluate().isNotEmpty);
              expect(find.text('Network Error'), findsOneWidget);
              await tester.tap(find.text(loc.tryAgain));
              await waitForUi(tester,
                  () => setup.currentStep == SetupStep.generateAccessKey);
              expect(calls, 2);
            }),
        () => MockClient((_) async {
              if (calls++ == 0) throw http.ClientException('offline');
              return http.Response('{"success":0,"message":"1"}', 200);
            }));
  });

  testWidgets('file details display the reconciled name and part count',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      await fixture.text('report.txt', 'contents');
      await fixture.scan();
      final item = await fixture.item('report.txt');
      await mount(tester, setup, PageFileInfo(item: item));
      await waitForUi(
          tester, () => find.text('report.txt').evaluate().isNotEmpty);
      final loc =
          AppLocalizations.of(tester.element(find.byType(PageFileInfo)))!;
      expect(find.text(loc.filePartsTitle(1)), findsOneWidget);
    });
  });

  testWidgets('file details recover when missing metadata becomes available',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      await fixture.text('report.txt', 'contents');
      await fixture.scan();
      final item = await fixture.item('report.txt');
      final file = (await ModelFile.get(item.fileHash!))!;
      await (await fixture.db).delete('files');
      await mount(tester, setup, PageFileInfo(item: item));
      final loc =
          AppLocalizations.of(tester.element(find.byType(PageFileInfo)))!;
      await waitForUi(
          tester, () => find.text(loc.fileNotFound).evaluate().isNotEmpty);
      await (await fixture.db).insert('files', file.toMap());
      await tester.tap(find.text(loc.tryAgain));
      await waitForUi(
          tester, () => find.text('report.txt').evaluate().isNotEmpty);
      expect(find.text(loc.filePartsTitle(1)), findsOneWidget);
    });
  });

  for (final invalid in ['', 'one two', List.filled(25, 'word').join(' ')]) {
    testWidgets('recovery form rejects ${invalid.split(' ').length}-word input',
        (tester) async {
      await withUi(tester, (fixture, setup) async {
        final before = Map.of(fixture.secrets);
        await mount(tester, setup, const PageAccessKeyDecode());
        await tester.enterText(find.byType(TextFormField), invalid);
        await tester.ensureVisible(find.byType(FilledButton));
        await tester.tap(find.byType(FilledButton));
        await tester.pump();
        final loc = AppLocalizations.of(
            tester.element(find.byType(PageAccessKeyDecode)))!;
        expect(
            find.text(invalid.isEmpty
                ? loc.pleaseEnterRecoveryPhrase
                : loc.mustContainExactly24Words),
            findsOneWidget);
        expect(fixture.secrets, before);
      });
    });
  }

  testWidgets('24 invalid words show an error and keep existing keys intact',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      final before = Map.of(fixture.secrets);
      await mount(tester, setup, const PageAccessKeyDecode());
      await tester.enterText(
          find.byType(TextFormField), List.filled(24, 'invalid').join(' '));
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      await waitForUi(
          tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
      final loc = AppLocalizations.of(
          tester.element(find.byType(PageAccessKeyDecode)))!;
      expect(find.text(loc.invalidWordList), findsOneWidget);
      expect(fixture.secrets, before);
      expect(setup.currentStep, SetupStep.onboard);
    });
  });

  for (final valid in [true, false]) {
    testWidgets(
        'valid recovery phrase ${valid ? 'restores keys and advances' : 'for a different account is rejected'}',
        (tester) async {
      await withUi(tester, (fixture, setup) async {
        final crypto = CryptoUtils(fixture.sodium);
        final generated = crypto.generateKeys().getResult()!;
        final private = generated[AppString.privateKeys.string];
        final server = generated[AppString.serverKeys.string];
        fixture.secrets[AppString.keyCipher.string] =
            server[AppString.cipher.string];
        fixture.secrets[AppString.keyNonce.string] =
            server[AppString.nonce.string];
        final access = valid
            ? private[AppString.accessKey.string]
            : base64Encode(Uint8List.fromList(List.filled(32, 11)));
        final words =
            bip39.entropyToMnemonic(bytesToHex(base64Decode(access as String)));
        final before = Map.of(fixture.secrets);
        await mount(tester, setup, const PageAccessKeyDecode());
        await tester.enterText(
            find.byType(TextFormField), '  ${words.split(' ').join(' \n ')}  ');
        await tester.ensureVisible(find.byType(FilledButton));
        await tester.tap(find.byType(FilledButton));
        await waitForUi(
            tester,
            () => valid
                ? setup.currentStep == SetupStep.registerDevice
                : find.byType(AlertDialog).evaluate().isNotEmpty);
        if (valid) {
          for (final key in [
            AppString.masterKey,
            AppString.accessKey,
            AppString.fileHashKey
          ]) {
            expect(fixture.secrets[key.string], private[key.string]);
          }
          expect(
              fixture.secrets.containsKey(AppString.keyCipher.string), isFalse);
          expect(
              fixture.secrets.containsKey(AppString.keyNonce.string), isFalse);
        } else {
          final loc = AppLocalizations.of(
              tester.element(find.byType(PageAccessKeyDecode)))!;
          expect(find.text(loc.invalidAccessKey), findsOneWidget);
          expect(fixture.secrets, before);
        }
      });
    });
  }

  testWidgets(
      'sign-in validates empty and malformed email before any authentication',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      await mount(tester, setup, const PageSignin());
      final loc = AppLocalizations.of(tester.element(find.byType(PageSignin)))!;
      await tester.ensureVisible(find.text(loc.sendOtp));
      await tester.tap(find.text(loc.sendOtp));
      await tester.pump();
      expect(find.text(loc.pleaseEnterYourEmail), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'invalid-address');
      await tester.tap(find.text(loc.sendOtp));
      await tester.pump();
      expect(find.text(loc.pleaseEnterValidEmailAddress), findsOneWidget);
      expect(await ModelSetting.getRaw(AppString.otpSentTo.string), '');
    });
  });

  testWidgets('simulation sign-in remains available through verification',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      await (await fixture.db).delete('profiles');
      await mount(tester, setup, const PageSignin());
      final loc = AppLocalizations.of(tester.element(find.byType(PageSignin)))!;
      await tester.enterText(find.byType(TextFormField), testEmailId);
      await tester.ensureVisible(find.text(loc.sendOtp));
      await tester.tap(find.text(loc.sendOtp));
      await waitForUi(
          tester, () => find.text(loc.verifyOtp).evaluate().isNotEmpty);
      expect(simulateTesting(), isTrue);
      await tester.enterText(find.byType(TextFormField), '123456');
      await tester.ensureVisible(find.text(loc.verifyOtp));
      await tester.tap(find.text(loc.verifyOtp));
      await waitForUi(
          tester, () => setup.currentStep == SetupStep.checkAccessKey);
      expect(await ModelSetting.getRaw(AppString.signedIn.string), 'yes');
      expect((await ModelProfile.get())?.email, testEmailId);
      expect(await ModelItem.get('fife'), isNotNull);
      expect(await ModelSetting.getRaw(AppString.otpSentTo.string), '');
    });
  });

  testWidgets('cached verification can return to email without stale OTP state',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      await ModelSetting.set(
          AppString.otpSentTo.string, 'fixture@example.test');
      await ModelSetting.set(AppString.otpSentAt.string,
          DateTime.now().millisecondsSinceEpoch.toString());
      await mount(tester, setup, const PageSignin());
      final loc = AppLocalizations.of(tester.element(find.byType(PageSignin)))!;
      expect(find.text(loc.verifyOtp), findsOneWidget);
      await tester.ensureVisible(find.text(loc.useDifferentEmail));
      await tester.tap(find.text(loc.useDifferentEmail));
      await waitForUi(
          tester, () => find.text(loc.sendOtp).evaluate().isNotEmpty);
      expect(await ModelSetting.getRaw(AppString.otpSentTo.string), '');
      expect(await ModelSetting.getRaw(AppString.otpSentAt.string), '');
    });
  });

  testWidgets('search debounces rapid input, shows latest results and clears',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      await fixture.text('annual-report.txt', 'report');
      await fixture.text('holiday-photo.jpg', 'photo');
      await fixture.scan();
      final report = await fixture.item('annual-report.txt');
      final photo = await fixture.item('holiday-photo.jpg');
      await mount(tester, setup, const SearchScreen());
      await tester.enterText(find.byType(TextField), 'report');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'photo');
      await tester.pump(const Duration(milliseconds: 600));
      await waitForUi(
          tester, () => find.byKey(ValueKey(photo.id)).evaluate().isNotEmpty);
      expect(find.byKey(ValueKey(report.id)), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 600));
      await waitForUi(
          tester, () => find.byKey(ValueKey(photo.id)).evaluate().isEmpty);
      final loc =
          AppLocalizations.of(tester.element(find.byType(SearchScreen)))!;
      expect(find.text(loc.typeBelowToSearch), findsOneWidget);
    });
  });

  testWidgets('leaving search before the debounce expires cancels the query',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      await mount(tester, setup, const SearchScreen());
      await tester.enterText(find.byType(TextField), 'pending');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('search reflects a renamed file after filesystem reconciliation',
      (tester) async {
    await withUi(tester, (fixture, setup) async {
      final source = await fixture.text('old-report.txt', 'same content');
      await fixture.scan();
      final original = await fixture.item('old-report.txt');
      await source.rename('${fixture.source.path}/renamed-report.txt');
      await fixture.scan();
      await mount(tester, setup, const SearchScreen());
      await tester.enterText(find.byType(TextField), 'renamed');
      await tester.pump(const Duration(milliseconds: 600));
      await waitForUi(tester,
          () => find.byKey(ValueKey(original.id)).evaluate().isNotEmpty);
      expect(find.text('renamed-report.txt'), findsOneWidget);
      expect(find.text('old-report.txt'), findsNothing);
      expect(
          await File('${fixture.source.path}/renamed-report.txt')
              .readAsString(),
          'same content');
    });
  });
}
