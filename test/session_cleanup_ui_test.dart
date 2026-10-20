import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_session_cleanup.dart';
import 'package:file_vault_bb/ui/pages/page_signin.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async => fixture.dispose());

  Future<void> until(bool Function() ready) async {
    for (var i = 0; i < 200 && !ready(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ready(), isTrue);
  }

  Future<AppSetupState> mountApp(WidgetTester tester) async {
    final setup = (await tester.runAsync(() async {
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      final state = AppSetupState(SecureStorage());
      await until(() => state.currentStep == SetupStep.signin);
      return state;
    }))!;
    final locale = LocaleProvider();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
      locale.dispose();
    });
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider.value(value: setup),
      ChangeNotifierProvider.value(value: locale),
    ], child: const MyApp()));
    await tester.pumpAndSettle();
    return setup;
  }

  testWidgets('revocation discards pushed private pages and open dialogs',
      (tester) async {
    final setup = await mountApp(tester);
    final navigator = Navigator.of(tester.element(find.byType(PageSignin)));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Cached private page')))));
    await tester.pumpAndSettle();
    unawaited(showDialog<void>(
        context: tester.element(find.text('Cached private page')),
        builder: (_) => const AlertDialog(content: Text('Private dialog'))));
    await tester.pumpAndSettle();
    expect(find.text('Private dialog'), findsOneWidget);
    await tester.runAsync(() async {
      expect(await SessionCleanup.instance.request(), isTrue);
      await until(() => setup.currentStep == SetupStep.signin);
    });
    await tester.pumpAndSettle();
    expect(find.byType(PageSignin), findsOneWidget);
    expect(find.text('Cached private page'), findsNothing);
    expect(find.text('Private dialog'), findsNothing);
    expect(navigator.mounted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed secure deletion stays locked and retries to sign-in',
      (tester) async {
    final setup = await mountApp(tester);
    final source = await tester
        .runAsync(() => fixture.text('original.txt', 'keep original'));
    var available = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncFixture.secure, (call) async {
      if (call.method == 'deleteAll') {
        if (!available) throw PlatformException(code: 'LOCKED');
        fixture.secrets.clear();
      }
      if (call.method == 'read') return fixture.secrets[call.arguments['key']];
      if (call.method == 'containsKey') {
        return fixture.secrets.containsKey(call.arguments['key']);
      }
      return null;
    });
    await tester.runAsync(() async {
      expect(await SessionCleanup.instance.request(), isFalse);
      await setup.recheckStatus();
    });
    await tester.pumpAndSettle();
    expect(find.byType(PageSessionCleanup), findsOneWidget);
    expect(find.byType(PageSignin), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PageSessionCleanup), findsOneWidget);
    available = true;
    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton));
      await until(() => setup.currentStep == SetupStep.signin);
    });
    await tester.pumpAndSettle();
    expect(find.byType(PageSignin), findsOneWidget);
    expect(fixture.secrets, isEmpty);
    expect(
        await tester.runAsync(() => source!.readAsString()), 'keep original');
    expect(tester.takeException(), isNull);
  });

  testWidgets('external cleanup wakeup removes active cached private routes',
      (tester) async {
    final setup = await mountApp(tester);
    final navigator = Navigator.of(tester.element(find.byType(PageSignin)));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Old vault page')))));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      // Represents the shared marker written by an independent service engine.
      await File('${fixture.directory.path}/fife-session-state.json')
          .writeAsString(
              jsonEncode({
                'revision': 'external-revocation',
                'pending': true,
                'mode': 'forced',
                'locale': 'en'
              }),
              flush: true);
      await SessionCleanup.instance.observeExternalState();
      await until(() => setup.currentStep == SetupStep.signin);
    });
    await tester.pumpAndSettle();
    expect(find.text('Old vault page'), findsNothing);
    expect(find.byType(PageSignin), findsOneWidget);
    expect(fixture.secrets, isEmpty);
    expect(navigator.mounted, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unavailable recovery key storage cannot bypass setup and can retry',
      (tester) async {
    final setup = await mountApp(tester);
    var locked = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncFixture.secure, (call) async {
      if (call.method == 'containsKey') {
        if (locked) throw PlatformException(code: 'LOCKED');
        return fixture.secrets.containsKey(call.arguments['key']);
      }
      if (call.method == 'read') return fixture.secrets[call.arguments['key']];
      return null;
    });
    await tester.runAsync(setup.recheckStatus);
    await tester.pumpAndSettle();
    expect(find.byType(PageSessionCleanup), findsOneWidget);
    locked = false;
    await tester.runAsync(() async {
      await tester.tap(find.byType(FilledButton));
      await until(() => setup.currentStep == SetupStep.signin);
    });
    await tester.pumpAndSettle();
    expect(find.byType(PageSignin), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      testWidgets(
          'cleanup supports large text and $locale/$brightness at 320px',
          (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(MaterialApp(
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  disableAnimations: true),
              child: child!),
          home: const PageSessionCleanup(),
        ));
        await tester.pumpAndSettle();
        expect(find.byType(FilledButton), findsOneWidget);
        expect(
            tester
                .getSemantics(find.byType(FilledButton))
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isTrue);
        expect(
            Directionality.of(tester.element(find.byType(PageSessionCleanup))),
            locale.languageCode == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      });
    }
  }
}
