import 'dart:ui' as ui;

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/ui/thumb_reach_list.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'support/sync_fixture.dart';
import 'support/app_lock_fixture.dart';

Future<void> _openSettings(WidgetTester tester,
    {TargetPlatform platform = TargetPlatform.android,
    double safeTop = 0,
    Size viewSize = const Size(400, 800),
    ValueChanged<String?>? onThemeChange}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  PackageInfo.setMockInitialValues(
      appName: 'FiFe',
      packageName: 'fixture.settings',
      version: '1',
      buildNumber: '1',
      buildSignature: 'fixture');
  final fixture = (await tester.runAsync(SyncFixture.create))!;
  final locale = LocaleProvider();
  final lock = AppLockController(
      store: MemoryAppLockStore(), authenticator: FakeAppLockAuthenticator());
  await lock.load();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    locale.dispose();
    lock.dispose();
    await tester.runAsync(() => fixture.dispose());
  });
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: locale),
        ChangeNotifierProvider.value(value: lock),
      ],
      child: Consumer<LocaleProvider>(
          builder: (context, provider, _) => MaterialApp(
              locale: provider.locale,
              theme: ThemeData(platform: platform),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      padding: EdgeInsets.only(top: safeTop),
                      viewPadding: EdgeInsets.only(top: safeTop)),
                  child: child!),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Builder(
                  builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                  builder: (_) => SettingsPage(
                                      onThemeChange: onThemeChange ?? (_) {}))),
                          child: const Text('Open settings'))))))));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open settings'));
  await tester.pumpAndSettle();
}

ScrollPosition _settingsPosition(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(
        of: find.byType(ThumbReachListView), matching: find.byType(Scrollable)))
    .position;

Future<void> _pullSettings(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(180, 80));
  await gesture.moveBy(const Offset(0, 30));
  await tester.pump();
  await gesture.moveBy(const Offset(0, 110));
  await tester.pump(const Duration(milliseconds: 400));
  await gesture.up();
  await tester.pumpAndSettle();
  expect(_settingsPosition(tester).pixels, lessThan(0));
}

void _expectReadingOrder(WidgetTester tester, List<String> labels) {
  var previous = double.negativeInfinity;
  for (final label in labels) {
    final item = find.text(label);
    expect(item, findsOneWidget);
    final top = tester.getTopLeft(item).dy;
    expect(top, greaterThan(previous),
        reason: '$label follows the previous item');
    previous = top;
  }
}

void main() {
  testWidgets('mobile Settings opens at the normal top above its fixed toolbar',
      (tester) async {
    await _openSettings(tester);
    final accountRow = find.ancestor(
        of: find.text('Sign out'), matching: find.byType(ListTile));
    expect(tester.getTopLeft(accountRow).dy, lessThan(100),
        reason: 'First controls start normally, not in a reversed bottom list');
    expect(tester.getBottomLeft(find.text('Settings')).dy, greaterThan(700));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'desktop Settings keeps bottom alignment and requested reading order',
      (tester) async {
    await _openSettings(tester,
        platform: TargetPlatform.macOS, viewSize: const Size(400, 1800));
    final labels = [
      'Sign out',
      'Version: 1',
      'Share',
      'Leave a review',
      'Mobile App',
      'Source Code',
      'Report Issue',
      'Language',
      'Theme',
      'Logging',
      'App lock'
    ];
    _expectReadingOrder(tester, labels);
    expect(tester.getTopLeft(find.text('Sign out')).dy, greaterThan(600));
    expect(find.text('App lock'), findsOneWidget);
    expect(
        find.text('Use Touch ID or your Mac login password to protect FiFe.'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('app-lock-timeout')), findsNothing);
    expect(find.text('Auto sync notification'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        '$platform Settings follows the requested order with App lock last',
        (tester) async {
      await _openSettings(tester,
          platform: platform, viewSize: const Size(400, 1800));
      final labels = [
        'Sign out',
        'Version: 1',
        'Share',
        'Leave a review',
        'Desktop App',
        'Source Code',
        'Report Issue',
        'Language',
        'Theme',
        'Logging',
        if (platform == TargetPlatform.android) ...[
          'Auto sync notification',
          'Auto sync interval',
        ],
        'App lock'
      ];
      _expectReadingOrder(tester, labels);
      expect(tester.getTopLeft(find.text('Sign out')).dy, lessThan(100));
      expect(tester.getBottomLeft(find.text('App lock')).dy,
          lessThan(tester.getTopLeft(find.byTooltip('Back')).dy));
      expect(find.text('Background sync'), findsNothing);
      if (platform == TargetPlatform.iOS) {
        expect(find.text('Auto sync notification'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('iOS status-bar tap still scrolls the Settings list to the top',
      (tester) async {
    await _openSettings(tester,
        platform: TargetPlatform.iOS,
        safeTop: 24,
        viewSize: const Size(400, 500));
    final position = _settingsPosition(tester);
    position.jumpTo(120);
    await tester.pumpAndSettle();
    expect(position.pixels, 120,
        reason: 'The list must actually be scrolled before the native event');
    ui.channelBuffers.push(
        SystemChannels.statusBar.name,
        SystemChannels.statusBar.codec
            .encodeMethodCall(const MethodCall('handleScrollToTop')),
        (_) {});
    await tester.pumpAndSettle();
    expect(position.pixels, 0,
        reason: 'Custom reach scrolling must retain native scroll-to-top');
  });

  testWidgets(
      'reachable Settings still saves theme and Back returns to its caller',
      (tester) async {
    String? changedTheme;
    await _openSettings(tester, onThemeChange: (value) => changedTheme = value);
    final back = tester.getRect(find.byTooltip('Back'));
    await _pullSettings(tester);
    final position = _settingsPosition(tester);
    final retained = position.pixels;
    await tester.runAsync(() async {
      await tester.tap(find.text('Theme'));
      for (var n = 0;
          n < 50 && ModelSetting.get(AppString.theme.string).isEmpty;
          n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(changedTheme, isNotEmpty);
    expect(ModelSetting.get(AppString.theme.string), changedTheme);
    expect(position.pixels, retained);
    expect(tester.getRect(find.byTooltip('Back')), back);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
    expect(_settingsPosition(tester).pixels, 0);
  });

  testWidgets(
      'language sheet owns its drag and selecting RTL keeps Settings usable',
      (tester) async {
    await _openSettings(tester);
    await _pullSettings(tester);
    final position = _settingsPosition(tester);
    final retained = position.pixels;
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    final sheet = find.byType(DraggableScrollableSheet);
    expect(sheet, findsOneWidget);
    await tester.drag(
        find.descendant(of: sheet, matching: find.byType(ListView)),
        const Offset(0, 80));
    await tester.pumpAndSettle();
    expect(position.pixels, retained);
    await tester.runAsync(() async {
      await tester.tap(find.text('العربية'));
      for (var n = 0;
          n < 50 && ModelSetting.get(AppString.locale.string) != 'ar';
          n++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsNothing);
    expect(ModelSetting.get(AppString.locale.string), 'ar');
    expect(position.pixels, retained);
    expect(Directionality.of(tester.element(find.byType(SettingsPage))),
        TextDirection.rtl);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Open settings'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
