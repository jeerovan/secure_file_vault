import 'dart:math' as math;

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:file_vault_bb/ui/pages/page_settings.dart';
import 'package:file_vault_bb/ui/thumb_reach_list.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_lock_fixture.dart';

const _first = ValueKey('first-setting');
const _toolbar = ValueKey('fixed-controls');

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(find.descendant(
        of: find.byType(ThumbReachListView), matching: find.byType(Scrollable)))
    .position;

Rect _viewport(WidgetTester tester) => tester.getRect(find.byType(Viewport));

Future<void> _mount(WidgetTester tester,
    {Size size = const Size(400, 900),
    double? contentHeight,
    double toolbarHeight = 64,
    bool short = false,
    EdgeInsets padding = EdgeInsets.zero,
    EdgeInsets viewInsets = EdgeInsets.zero,
    TargetPlatform platform = TargetPlatform.android,
    Locale locale = const Locale('en'),
    bool reducedMotion = false,
    double scale = 1,
    PageStorageBucket? bucket,
    AppLockController? gate,
    VoidCallback? onBack,
    List<Widget>? controls}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final list = ThumbReachListView(
      key: const PageStorageKey('settings-reach-list'),
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(
            key: _first,
            height: 72,
            child: Center(child: Text('First setting'))),
        ...?controls,
        if (!short)
          for (var n = 1; n < 32; n++)
            SizedBox(height: 72, child: Text('Setting $n')),
      ]);
  await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(platform: platform),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              size: size,
              padding: padding,
              viewPadding: padding,
              viewInsets: viewInsets,
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion),
          child: gate == null
              ? child!
              : AppLockGate(controller: gate, child: child!)),
      home: PageStorage(
          bucket: bucket ?? PageStorageBucket(),
          child: Scaffold(
              body: Column(children: [
            if (contentHeight == null)
              Expanded(child: list)
            else ...[
              SizedBox(height: contentHeight, child: list),
              const Spacer(),
            ],
            SafeArea(
                top: false,
                child: SizedBox(
                    key: _toolbar,
                    height: toolbarHeight,
                    width: double.infinity,
                    child: TextButton(
                        onPressed: onBack ?? () {},
                        child: const Text('Back')))),
          ])))));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<TestGesture> _startDrag(WidgetTester tester, {bool down = true}) async {
  final view = _viewport(tester);
  final gesture = await tester.startGesture(
      Offset(view.center.dx, view.top + math.min(120, view.height / 2)));
  // Cross native touch slop; subsequent moves have an exact known distance.
  await gesture.moveBy(Offset(0, down ? 30 : -30));
  await tester.pump();
  return gesture;
}

Future<void> _release(WidgetTester tester, TestGesture gesture) async {
  await tester.pump(const Duration(milliseconds: 400));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, {double distance = 150}) async {
  final gesture = await _startDrag(tester);
  await gesture.moveBy(Offset(0, distance));
  await tester.pump();
  await _release(tester, gesture);
  expect(_position(tester).pixels, lessThan(0));
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets(
        '$platform starts normally and retains bounded reach on release',
        (tester) async {
      await _mount(tester,
          platform: platform,
          padding: const EdgeInsets.only(top: 24, bottom: 20));
      final viewport = _viewport(tester);
      final toolbar = tester.getRect(find.byKey(_toolbar));
      expect(tester.getTopLeft(find.byKey(_first)).dy, viewport.top);
      expect(viewport.bottom, toolbar.top);
      expect(_position(tester).pixels, 0);
      final gesture = await _startDrag(tester);
      await gesture.moveBy(const Offset(0, 2000));
      await tester.pump();
      final expected = viewport.height - 360;
      expect(_position(tester).pixels, closeTo(-expected, .01));
      expect(tester.getTopLeft(find.byKey(_first)).dy,
          closeTo(viewport.bottom - 360, .01));
      await _release(tester, gesture);
      await tester.pump(const Duration(seconds: 2));
      expect(_position(tester).pixels, closeTo(-expected, .01));
      expect(_viewport(tester), viewport);
      expect(tester.getRect(find.byKey(_toolbar)), toolbar);
    });
  }

  testWidgets(
      'downward movement scrolls content first and uses only the remainder',
      (tester) async {
    await _mount(tester);
    _position(tester).jumpTo(120);
    await tester.pump();
    final gesture = await _startDrag(tester);
    final before = _position(tester).pixels;
    expect(before, greaterThan(0));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(_position(tester).pixels, closeTo(before - 30, .01));
    final nearTop = _position(tester).pixels;
    await gesture.moveBy(Offset(0, nearTop + 40));
    await tester.pump();
    expect(_position(tester).pixels, closeTo(-40, .01));
    expect(tester.getTopLeft(find.byKey(_first)).dy,
        closeTo(_viewport(tester).top + 40, .01));
    await _release(tester, gesture);
  });

  testWidgets('upward movement removes reach first then scrolls its remainder',
      (tester) async {
    await _mount(tester);
    await _reveal(tester);
    final gesture = await _startDrag(tester, down: false);
    final reach = -_position(tester).pixels;
    expect(reach, greaterThan(40));
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    expect(_position(tester).pixels, closeTo(-(reach - 40), .01));
    await gesture.moveBy(Offset(0, -(reach - 40 + 55)));
    await tester.pump();
    expect(_position(tester).pixels, closeTo(55, .01));
    await _release(tester, gesture);
  });

  testWidgets('short content can be reached without shrinking the viewport',
      (tester) async {
    await _mount(tester, short: true);
    final viewport = _viewport(tester);
    expect(_position(tester).maxScrollExtent, 0);
    await _reveal(tester);
    expect(_viewport(tester), viewport);
    final gesture = await _startDrag(tester, down: false);
    await gesture.moveBy(const Offset(0, -1000));
    await _release(tester, gesture);
    expect(_position(tester).pixels, 0);
    expect(tester.getTopLeft(find.byKey(_first)).dy, viewport.top);
  });

  for (final height in [0.0, 100.0, 359.0, 360.0, 361.0, 720.0]) {
    testWidgets('portrait available height $height bounds valid reach',
        (tester) async {
      await _mount(tester,
          size: const Size(400, 1000), contentHeight: height, short: true);
      expect(_viewport(tester).height, height);
      if (height > 0) {
        final gesture = await _startDrag(tester);
        await gesture.moveBy(const Offset(0, 2000));
        await _release(tester, gesture);
      }
      expect(
          _position(tester).pixels, closeTo(-math.max(0, height - 360), .01));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'landscape disables reach even when its content height exceeds 360',
      (tester) async {
    await _mount(tester, size: const Size(1000, 700));
    expect(_viewport(tester).height, greaterThan(360));
    final gesture = await _startDrag(tester);
    await gesture.moveBy(const Offset(0, 400));
    await _release(tester, gesture);
    expect(_position(tester).pixels, 0);
    expect(tester.getTopLeft(find.byKey(_first)).dy, _viewport(tester).top);
  });

  testWidgets(
      'rotation clears reach and returning to portrait never restores it',
      (tester) async {
    await _mount(tester);
    await _reveal(tester);
    await _mount(tester, size: const Size(1000, 700));
    expect(_position(tester).pixels, 0);
    await _mount(tester);
    expect(_position(tester).pixels, 0);
    _position(tester).jumpTo(180);
    await _mount(tester, size: const Size(1000, 700));
    expect(_position(tester).pixels, 180);
  });

  for (final change in ['safe insets', 'keyboard', 'fixed toolbar', 'window']) {
    testWidgets('$change changes reset reach but preserve content scrolling',
        (tester) async {
      await _mount(tester);
      await _reveal(tester);
      final padding = change == 'safe insets'
          ? const EdgeInsets.only(top: 30, bottom: 20)
          : EdgeInsets.zero;
      final inset = change == 'keyboard'
          ? const EdgeInsets.only(bottom: 250)
          : EdgeInsets.zero;
      final toolbar = change == 'fixed toolbar' ? 100.0 : 64.0;
      final size =
          change == 'window' ? const Size(420, 950) : const Size(400, 900);
      await _mount(tester,
          padding: padding,
          viewInsets: inset,
          toolbarHeight: toolbar,
          size: size);
      expect(_position(tester).pixels, 0);
      expect(tester.getTopLeft(find.byKey(_first)).dy, _viewport(tester).top);
      _position(tester).jumpTo(160);
      await _mount(tester);
      expect(_position(tester).pixels, 160);
    });
  }

  testWidgets('programmatic jumps and animations cannot create reach',
      (tester) async {
    await _mount(tester);
    _position(tester).restoreOffset(-80, initialRestore: true);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0,
        reason: 'An old restored overscroll must not create reach space');
    _position(tester).jumpTo(-100);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    var animation = _position(tester).animateTo(-200,
        duration: const Duration(milliseconds: 100), curve: Curves.linear);
    await tester.pumpAndSettle();
    await animation;
    expect(_position(tester).pixels, 0);
    await _reveal(tester);
    _position(tester).jumpTo(150);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 150);
    animation = _position(tester).animateTo(0,
        duration: const Duration(milliseconds: 100), curve: Curves.linear);
    await tester.pumpAndSettle();
    await animation;
    expect(_position(tester).pixels, 0);
  });

  testWidgets('unused downward fling momentum cannot reveal reach at the top',
      (tester) async {
    await _mount(tester);
    _position(tester).jumpTo(400);
    await tester.pump();
    await tester.fling(
        find.byType(ThumbReachListView), const Offset(0, 100), 3500);
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    expect(tester.getTopLeft(find.byKey(_first)).dy, _viewport(tester).top);
  });

  testWidgets('pointer scrolling removes reach without expanding it',
      (tester) async {
    await _mount(tester);
    await _reveal(tester);
    final before = _position(tester).pixels;
    for (final delta in [const Offset(0, -80), const Offset(80, 0)]) {
      await tester.sendEventToBinding(PointerScrollEvent(
          position: _viewport(tester).center, scrollDelta: delta));
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, before);
    }
    await tester.sendEventToBinding(PointerScrollEvent(
        position: _viewport(tester).center, scrollDelta: const Offset(0, 30)));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(before + 30, .01));
  });

  testWidgets(
      'taps and horizontal movement do not reveal reach; Back stays usable',
      (tester) async {
    var back = 0;
    await _mount(tester, onBack: () => back++);
    await tester.tap(find.byKey(_first));
    await tester.drag(find.byKey(_first), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    await _reveal(tester);
    final pixels = _position(tester).pixels;
    await tester.tap(find.text('Back'));
    expect(back, 1);
    expect(_position(tester).pixels, pixels);
  });

  testWidgets('reach is transient while normal PageStorage scrolling survives',
      (tester) async {
    final bucket = PageStorageBucket();
    await _mount(tester, bucket: bucket);
    await _reveal(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, bucket: bucket);
    expect(_position(tester).pixels, 0);
    _position(tester).jumpTo(180);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await _mount(tester, bucket: bucket);
    expect(_position(tester).pixels, 180);
  });

  testWidgets('canceled dragging leaves the next drag usable', (tester) async {
    await _mount(tester);
    var gesture = await _startDrag(tester);
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, lessThan(0));
    gesture = await _startDrag(tester, down: false);
    await gesture.moveBy(const Offset(0, -300));
    await _release(tester, gesture);
    expect(_position(tester).pixels, greaterThan(0));
  });

  testWidgets('standard scroll actions remove reach and expose later settings',
      (tester) async {
    await _mount(tester);
    await _reveal(tester);
    Actions.invoke(
        tester.element(find.byKey(_first)),
        const ScrollIntent(
            direction: AxisDirection.down, type: ScrollIncrementType.page));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'App lock still conceals a reached list and returns it after authentication',
      (tester) async {
    var clock = Duration.zero;
    final auth = FakeAppLockAuthenticator();
    final lock = AppLockController(
        store: MemoryAppLockStore()..enabled = true,
        authenticator: auth,
        clock: () => clock);
    addTearDown(lock.dispose);
    await lock.load();
    await lock.unlock(testAppLockPrompt);
    await _mount(tester, gate: lock);
    await _reveal(tester);
    final position = _position(tester);
    final retained = position.pixels;
    auth.result = false;
    lock.handleLifecycle(AppLifecycleState.paused);
    clock += const Duration(minutes: 5);
    lock.handleLifecycle(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byKey(_first), findsNothing);
    expect(find.text('FiFe is locked'), findsOneWidget);
    await tester.dragFrom(const Offset(160, 150), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(position.pixels, retained);
    auth.result = true;
    await lock.unlock(testAppLockPrompt);
    await tester.pumpAndSettle();
    expect(find.byKey(_first), findsOneWidget);
    expect(position.pixels, retained);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'large RTL text and reduced motion keep controls and semantics usable',
      (tester) async {
    final lock = AppLockController(
        store: MemoryAppLockStore(), authenticator: FakeAppLockAuthenticator());
    addTearDown(lock.dispose);
    await lock.load();
    await lock.setEnabled(true, testAppLockPrompt);
    await _mount(tester,
        size: const Size(360, 900),
        locale: const Locale('ar'),
        scale: 2,
        reducedMotion: true,
        controls: [AppLockSettings(controller: lock)]);
    await _reveal(tester, distance: 70);
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(find.byKey(_first)).label,
        contains('First setting'));
    expect(tester.getRect(find.byKey(_toolbar)).bottom, 900);
    semantics.dispose();
    final gesture = await _startDrag(tester, down: false);
    await gesture.moveBy(const Offset(0, -500));
    await _release(tester, gesture);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'both Settings sliders retain their horizontal gesture and values',
      (tester) async {
    final lock = AppLockController(
        store: MemoryAppLockStore(), authenticator: FakeAppLockAuthenticator());
    addTearDown(lock.dispose);
    await lock.load();
    await lock.setEnabled(true, testAppLockPrompt);
    var autoInterval = 15;
    await _mount(tester, size: const Size(420, 1100), short: true, controls: [
      AppLockSettings(controller: lock),
      AutoSyncIntervalSetting(
          minutes: 15,
          onChanged: (value) => autoInterval = value.round(),
          onChangeEnd: (value) => autoInterval = value.round()),
    ]);
    await _reveal(tester, distance: 35);
    final before = _position(tester).pixels;
    final sliders = find.byType(Slider);
    expect(sliders, findsNWidgets(2));
    for (var n = 0; n < 2; n++) {
      final rect = tester.getRect(sliders.at(n));
      await tester.dragFrom(rect.center, Offset(rect.width / 2 - 5, 0));
      await tester.pumpAndSettle();
      expect(_position(tester).pixels, closeTo(before, .01));
    }
    expect(lock.minutes, 30);
    expect(autoInterval, 30);
  });
}
