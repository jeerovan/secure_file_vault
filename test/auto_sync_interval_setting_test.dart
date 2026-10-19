import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget setting({
    required int minutes,
    required ValueChanged<double>? onChanged,
    required ValueChanged<double> onChangeEnd,
    double textScale = 1,
    bool dark = false,
    TextDirection direction = TextDirection.ltr,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true),
          child: Directionality(
            textDirection: direction,
            child: Scaffold(
              body: ListView(children: [
                AutoSyncIntervalSetting(
                  minutes: minutes,
                  onChanged: onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ]),
            ),
          ),
        );
      }),
    );
  }

  testWidgets('shows the current interval with one-minute steps and endpoints',
      (tester) async {
    int selected = 15;
    int? saved;
    await tester.pumpWidget(StatefulBuilder(builder: (context, setState) {
      return setting(
        minutes: selected,
        onChanged: (value) => setState(() => selected = value.round()),
        onChangeEnd: (value) => saved = value.round(),
      );
    }));
    await tester.pumpAndSettle();
    expect(find.text('15 minutes'), findsOneWidget);
    expect(find.text('1 minute'), findsOneWidget);
    expect(find.text('30 minutes'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 1);
    expect(slider.max, 30);
    expect(slider.divisions, 29);
    expect(slider.semanticFormatterCallback!(1), '1 minute');
    final rect = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    await tester.pumpAndSettle();
    expect(selected, 30);
    expect(saved, 30);
    await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(saved, 1);
  });

  testWidgets('slider exposes an accessible name and minute value',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(setting(
      minutes: 15,
      onChanged: (_) {},
      onChangeEnd: (_) {},
    ));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.byType(Slider)),
      matchesSemantics(
        label: 'Auto sync interval: 15 minutes',
        value: '15 minutes',
        increasedValue: '16 minutes',
        decreasedValue: '14 minutes',
        isSlider: true,
        hasEnabledState: true,
        isEnabled: true,
        isFocusable: true,
        hasIncreaseAction: true,
        hasDecreaseAction: true,
        hasFocusAction: true,
      ),
    );
    semantics.dispose();
  });

  testWidgets('saving disables edits while retaining the selected value',
      (tester) async {
    await tester.pumpWidget(setting(
      minutes: 7,
      onChanged: null,
      onChangeEnd: (_) => fail('Saving must prevent another commit'),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Slider));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 7);
    expect(find.text('7 minutes'), findsOneWidget);
  });

  testWidgets('fits a narrow screen with large text, dark theme and RTL',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(setting(
      minutes: 30,
      onChanged: (_) {},
      onChangeEnd: (_) {},
      textScale: 2,
      dark: true,
      direction: TextDirection.rtl,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Auto sync interval'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
  });
}
