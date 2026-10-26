import 'dart:async';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_lock_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryAppLockStore store;
  late FakeAppLockAuthenticator auth;
  late AppLockController lock;
  late AppLockNavigatorObserver observer;
  late Duration time;
  late GlobalKey<NavigatorState> navigator;

  setUp(() {
    SessionWork.resetForTesting();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    store = MemoryAppLockStore();
    auth = FakeAppLockAuthenticator();
    time = Duration.zero;
    lock =
        AppLockController(store: store, authenticator: auth, clock: () => time);
    observer = AppLockNavigatorObserver(lock);
    navigator = GlobalKey<NavigatorState>();
  });
  tearDown(() {
    observer.dispose();
    lock.dispose();
    SessionWork.resetForTesting();
  });

  Widget app(
          {bool settings = false,
          Locale locale = const Locale('en'),
          double scale = 1,
          bool dark = false,
          AppLockPrivacyBridge privacy = const SystemAppLockPrivacy()}) =>
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [observer],
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: AppLockGate(controller: lock, privacy: privacy, child: child!),
        ),
        home: Scaffold(
            body: ListView(children: [
          const Text('Private fixture content'),
          if (settings) AppLockSettings(controller: lock),
        ])),
      );

  testWidgets('unknown policy hides private content on the first frame',
      (tester) async {
    await tester.pumpWidget(app());
    expect(find.text('Private fixture content'), findsNothing);
    expect(find.text('FiFe is locked'), findsOneWidget);
    await lock.load();
    await tester.pumpAndSettle();
    expect(find.text('Private fixture content'), findsOneWidget);
  });

  testWidgets('native frame transport denies native documents by default',
      (tester) async {
    MethodCall? received;
    const channel = MethodChannel('com.jeerovan.fife/app_lock_privacy');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      received = call;
      return null;
    });
    addTearDown(() =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await const SystemAppLockPrivacy().frameReady();
    expect(received?.method, 'frameReady');
    expect(received?.arguments, {'allowNativeDocuments': false});
  });

  testWidgets('native frame exposure follows the actual App lock state',
      (tester) async {
    store.enabled = true;
    auth.result = false;
    await lock.load();
    final privacy = _DelayedPrivacy()..enabled.complete();
    await tester.pumpWidget(app(privacy: privacy));
    await tester.pumpAndSettle();
    expect(find.text('Private fixture content'), findsNothing);
    expect(privacy.documentExposure.last, isFalse);
    auth.result = true;
    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    expect(find.text('Private fixture content'), findsOneWidget);
    expect(privacy.documentExposure.last, isTrue);
  });

  testWidgets(
      'native application activity owns timeout while Flutter is hidden',
      (tester) async {
    store.enabled = true;
    store.minutes = 1;
    await lock.load();
    await lock.unlock(testAppLockPrompt);
    final privacy = _DelayedPrivacy()
      ..reportsApplicationLifecycle = true
      ..enabled.complete();
    await tester.pumpWidget(app(privacy: privacy));
    await tester.pumpAndSettle();
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    // A native file preview hides Flutter while the actual scene stays active.
    time += const Duration(minutes: 2);
    expect(lock.foreground, isTrue);
    expect(lock.locked, isFalse);
    // Native deactivation closes the preview; Flutter can paint again when
    // its host returns. The physical channel test verifies that native close.
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed
    ]) {
      binding.handleAppLifecycleStateChanged(state);
    }
    privacy.lifecycleListener!(AppLifecycleState.inactive);
    time += const Duration(seconds: 30);
    privacy.lifecycleListener!(AppLifecycleState.resumed);
    expect(lock.locked, isFalse);
    auth.result = false;
    privacy.lifecycleListener!(AppLifecycleState.inactive);
    time += const Duration(seconds: 61);
    privacy.lifecycleListener!(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(lock.locked, isTrue);
    expect(find.text('Private fixture content'), findsNothing);
    expect(privacy.documentExposure.last, isFalse);
  });

  testWidgets('native lifecycle ignores a late older initial snapshot',
      (tester) async {
    const bridge = SystemAppLockPrivacy();
    const channel = MethodChannel('com.jeerovan.fife/app_lock_privacy');
    final initial = Completer<Object?>();
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => initial.future);
    addTearDown(() =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final events = <AppLifecycleState>[];
    final watching = bridge.watchLifecycle(events.add);
    await tester.idle();
    ServicesBinding.instance.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('lifecycle', {'active': false, 'revision': 2})),
        (_) {});
    await tester.idle();
    initial.complete({'active': true, 'revision': 1});
    final stop = await watching;
    addTearDown(stop);
    expect(events, [AppLifecycleState.inactive]);
  });

  testWidgets('old lifecycle disposal cannot disconnect the replacement gate',
      (tester) async {
    const bridge = SystemAppLockPrivacy();
    const channel = MethodChannel('com.jeerovan.fife/app_lock_privacy');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (call) async => {'active': true, 'revision': 0});
    addTearDown(() =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    final oldEvents = <AppLifecycleState>[];
    final newEvents = <AppLifecycleState>[];
    final oldStop = await bridge.watchLifecycle(oldEvents.add);
    final stop = await bridge.watchLifecycle(newEvents.add);
    addTearDown(stop);
    oldStop();
    ServicesBinding.instance.channelBuffers.push(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
            const MethodCall('lifecycle', {'active': false, 'revision': 1})),
        (_) {});
    await tester.idle();
    expect(oldEvents, [AppLifecycleState.resumed]);
    expect(newEvents, [AppLifecycleState.resumed, AppLifecycleState.inactive]);
  });

  testWidgets(
      'a delayed native frame acknowledgment cannot expose a newly locked route',
      (tester) async {
    store.enabled = true;
    store.minutes = 1;
    await lock.load();
    await lock.unlock(testAppLockPrompt);
    final privacy = _DelayedPrivacy();
    await tester.pumpWidget(app(privacy: privacy));
    await tester.idle();
    expect(find.text('Private fixture content'), findsOneWidget);
    // The old authorized frame is waiting on the native channel. Expire the
    // grant before another Flutter frame is painted, then release that channel.
    lock.handleLifecycle(AppLifecycleState.paused);
    time += const Duration(minutes: 1);
    lock.handleLifecycle(AppLifecycleState.resumed);
    auth.result = false;
    privacy.enabled.complete();
    await tester.idle();
    expect(privacy.readyFrames, 0,
        reason:
            'Only a frame painted for the current lock state may remove the native cover');
    await tester.pumpAndSettle();
    expect(find.text('Private fixture content'), findsNothing);
    expect(find.text('FiFe is locked'), findsOneWidget);
    expect(privacy.readyFrames, greaterThan(0));
  });

  testWidgets('settings start off; enabling reveals the five-minute slider',
      (tester) async {
    await lock.load();
    await tester.pumpWidget(app(settings: true));
    await tester.pumpAndSettle();
    expect(find.text('App lock'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-lock-timeout')), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(store.enabled, isTrue);
    expect(auth.attempts, 1);
    expect(find.text('5 minutes'), findsOneWidget);
    expect(find.byKey(const ValueKey('app-lock-timeout')), findsOneWidget);
    expect(auth.prompt!.reason, 'Authenticate to change App lock settings.');
  });

  testWidgets('slider maps every discrete stop to its specified minute value',
      (tester) async {
    store.enabled = true;
    await lock.load();
    await lock.unlock(testAppLockPrompt);
    await tester.pumpWidget(app(settings: true));
    await tester.pumpAndSettle();
    const expected = [1, 5, 10, 15, 20, 25, 30];
    for (var index = 0; index < expected.length; index++) {
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.divisions, 6);
      expect(slider.semanticFormatterCallback!(index.toDouble()),
          '${expected[index]} ${expected[index] == 1 ? 'minute' : 'minutes'}');
      slider.onChanged!(index.toDouble());
      slider.onChangeEnd!(index.toDouble());
      await tester.pumpAndSettle();
      expect(store.minutes, expected[index]);
      expect(lock.minutes, expected[index]);
    }
    final rect = tester.getRect(find.byType(Slider));
    await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
    await tester.pumpAndSettle();
    expect(store.minutes, 1);
    await tester.tapAt(Offset(rect.right - 1, rect.center.dy));
    await tester.pumpAndSettle();
    expect(store.minutes, 30);
  });

  testWidgets(
      'canceling the native prompt leaves the lock visible without a prompt loop',
      (tester) async {
    store.enabled = true;
    auth.result = false;
    await lock.load();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(auth.attempts, 1);
    expect(find.text('Private fixture content'), findsNothing);
    expect(find.text('Authentication was not completed. Try again.'),
        findsOneWidget);
    await tester.pump(const Duration(minutes: 1));
    expect(auth.attempts, 1);
    auth.result = true;
    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    expect(auth.attempts, 2);
    expect(find.text('Private fixture content'), findsOneWidget);
  });

  testWidgets(
      'background shield preserves the current route and dialog through timeout and Back',
      (tester) async {
    store.enabled = true;
    store.minutes = 1;
    await lock.load();
    await lock.unlock(testAppLockPrompt);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Private detail route')))));
    await tester.pumpAndSettle();
    var dialogDismissed = false;
    unawaited(showDialog<void>(
            context: navigator.currentContext!,
            builder: (_) =>
                const AlertDialog(content: Text('Private dialog content')))
        .then((_) => dialogDismissed = true));
    await tester.pumpAndSettle();
    expect(find.text('Private dialog content'), findsOneWidget);
    final response = Completer<bool>();
    auth.onAuthenticate = (_) => response.future;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Private dialog content'), findsNothing);
    time += const Duration(minutes: 1);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    await binding.handlePopRoute();
    await tester.pump();
    expect(dialogDismissed, isFalse);
    expect(find.text('Private detail route'), findsNothing);
    response.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Private dialog content'), findsNothing);
    auth.onAuthenticate = null;
    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    expect(find.text('Private dialog content'), findsOneWidget);
    expect(dialogDismissed, isFalse);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('Private detail route'), findsOneWidget);
  });

  testWidgets(
      'locked content is excluded from accessibility and keyboard focus',
      (tester) async {
    final semantics = tester.ensureSemantics();
    store.enabled = true;
    auth.result = false;
    await lock.load();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Private fixture content'), findsNothing);
    expect(find.text('Private fixture content', skipOffstage: false),
        findsOneWidget);
    expect(
        tester
            .getSemantics(find.byKey(const ValueKey('app-lock-unlock')))
            .label,
        'Unlock');
    semantics.dispose();
  });

  testWidgets('storage read failure offers retry while keeping content hidden',
      (tester) async {
    store.onRead = () async => throw StateError('private settings unavailable');
    await lock.load();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Private fixture content'), findsNothing);
    store.onRead = null;
    await tester.tap(find.byKey(const ValueKey('app-lock-unlock')));
    await tester.pumpAndSettle();
    expect(find.text('Private fixture content'), findsOneWidget);
  });

  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets(
        'locked state fits a narrow large-text screen in ${locale.languageCode}',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      store.enabled = true;
      auth.result = false;
      await lock.load();
      await tester.pumpWidget(app(locale: locale, scale: 2, dark: true));
      await tester.pumpAndSettle();
      final loc =
          AppLocalizations.of(tester.element(find.byType(AppLockGate)))!;
      expect(find.text(loc.appLocked), findsOneWidget);
      expect(find.text(loc.appLockUnlock), findsOneWidget);
      expect(find.text('Private fixture content'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'timeout settings fit large-text RTL and disable repeated edits while saving',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    store.enabled = true;
    await lock.load();
    await lock.unlock(testAppLockPrompt);
    await tester
        .pumpWidget(app(settings: true, locale: const Locale('ar'), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final saved = Completer<void>();
    store.onSetTimeout = (_) => saved.future;
    final pending = lock.setTimeout(10);
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    saved.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _DelayedPrivacy implements AppLockPrivacyBridge {
  final enabled = Completer<void>();
  int readyFrames = 0;
  final documentExposure = <bool>[];
  @override
  bool reportsApplicationLifecycle = false;
  ValueChanged<AppLifecycleState>? lifecycleListener;
  @override
  Future<VoidCallback> watchLifecycle(
      ValueChanged<AppLifecycleState> listener) async {
    lifecycleListener = listener;
    listener(AppLifecycleState.resumed);
    return () {
      if (identical(lifecycleListener, listener)) lifecycleListener = null;
    };
  }

  @override
  bool get supported => true;
  @override
  Future<void> setEnabled(bool value) => enabled.future;
  @override
  Future<void> frameReady({bool allowNativeDocuments = false}) async {
    readyFrames++;
    documentExposure.add(allowNativeDocuments);
  }
}
