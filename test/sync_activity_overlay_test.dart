import 'package:file_vault_bb/main.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/models/model_state.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/sync_activity_overlay.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/app_lock_fixture.dart';
import 'support/sync_fixture.dart';

void main() {
  testWidgets('the real app root displays active sync above its navigator',
      (tester) async {
    late SyncFixture fixture;
    late AppSetupState setup;
    final locale = LocaleProvider();
    final store = MemoryAppLockStore();
    final auth = FakeAppLockAuthenticator()..result = false;
    final lock = AppLockController(store: store, authenticator: auth);
    OperationLease? lease;
    await tester.runAsync(() async {
      fixture = await SyncFixture.create();
      await ModelSetting.set(AppString.onboarding.string, 'yes');
      await ModelSetting.set(AppString.signedIn.string, 'no');
      setup = AppSetupState(SecureStorage());
      await setup.recheckStatus();
      await lock.load();
    });
    try {
      await tester.pumpWidget(MultiProvider(providers: [
        ChangeNotifierProvider.value(value: setup),
        ChangeNotifierProvider.value(value: locale)
      ], child: MyApp(appLock: lock)));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      lease = await tester.runAsync<OperationLease?>(
          () => ExclusiveOperationCoordinator.tryAcquire('metadata'));
      expect(lease, isNotNull);
      EventStream().publish(AppEvent(
          type: EventType.system, id: 'metadata', key: EventKey.running));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(
          tester
              .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator))
              .value,
          isNull);
      store.enabled = true;
      await tester.runAsync(lock.load);
      await tester.pump();
      expect(lock.concealed, isTrue);
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: 'The activity overlay belongs inside the privacy shield');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.runAsync(() async => lease?.release());
      EventStream().publish(AppEvent(
          type: EventType.system, id: 'metadata', key: EventKey.stopped));
      await tester.pumpWidget(const SizedBox.shrink());
      setup.dispose();
      locale.dispose();
      lock.dispose();
      await tester.runAsync(fixture.dispose);
    }
  });

  testWidgets('existing cross-isolate transfer is discovered without an event',
      (tester) async {
    await withActivity(tester, (activity) async {
      await activity.acquire('transfer:upload:fixture');
      await activity.mount();
      await activity.flush();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('overlapping work preserves content until the final lease ends',
      (tester) async {
    await withActivity(tester, (activity) async {
      await activity.mount();
      await activity.flush();
      final position = tester.getTopLeft(find.byKey(const ValueKey('input')));
      activity.input.text = 'Keep this unsaved input';
      activity.focus.requestFocus();
      await tester.pump();
      final metadata = await activity.acquire('metadata');
      activity.signal('metadata', EventKey.running);
      await tester.pump();
      final transfer = await activity.acquire('transfer:download:fixture');
      activity.signal('transfer', EventKey.running);
      await activity.release(metadata);
      activity.signal('metadata', EventKey.stopped);
      await activity.flush();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(activity.focus.hasFocus, isTrue);
      expect(activity.input.text, 'Keep this unsaved input');
      expect(tester.getTopLeft(find.byKey(const ValueKey('input'))), position);
      await activity.release(transfer);
      activity.signal('transfer', EventKey.stopped);
      await activity.flush();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(activity.input.text, 'Keep this unsaved input');
      expect(tester.getTopLeft(find.byKey(const ValueKey('input'))), position);
    });
  });

  testWidgets('expired or malformed work and queued retries are not active',
      (tester) async {
    await withActivity(tester, (activity) async {
      await tester.runAsync(() async {
        final now = DateTime.now().millisecondsSinceEpoch;
        await ModelState.set('operation_lease:transfer:expired',
            '{"owner":"fixture","expires_at":${now - 1}}');
        await ModelState.set('operation_lease:metadata', 'malformed');
        await (await activity.fixture.db).insert('item_tasks', {
          'id': SyncFixture.rootId,
          'task': 1,
          'state': 'retryWaiting',
          'next_attempt_at': now + 60000,
        });
      });
      await activity.mount();
      await activity.flush();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      activity.signal('obsolete-service-hint', EventKey.running);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await activity.flush(tick: true);
      expect(find.byType(LinearProgressIndicator), findsNothing,
          reason: 'A missing stop event must not leave permanent progress');
    });
  });

  testWidgets('pause stops display and resume rediscovers ongoing work',
      (tester) async {
    await withActivity(tester, (activity) async {
      await activity.acquire('reconciliation:fixture');
      await activity.mount();
      await activity.flush();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      resumeActivity(tester);
      await activity.flush();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });
  });

  testWidgets('session invalidation removes progress despite retained leases',
      (tester) async {
    await withActivity(tester, (activity) async {
      await activity.acquire('metadata');
      await activity.mount();
      await activity.flush();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      SessionWork.invalidate('new-authentication');
      activity.signal('session', EventKey.sessionInvalidated);
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      SessionWork.complete('new-authentication', authenticationRequired: true);
      activity.signal('obsolete-work', EventKey.running);
      await activity.flush(tick: true);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('reduced motion stays indeterminate with $brightness theme',
        (tester) async {
      await withActivity(tester, (activity) async {
        await activity.acquire('metadata');
        await activity.mount(
            brightness: brightness,
            reduceMotion: true,
            locale: const Locale('ar'));
        await activity.flush();
        final progress = tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator));
        expect(progress.value, isNull);
        expect(progress.controller, isNotNull);
        expect(progress.controller!.isAnimating, isFalse);
        final phase = progress.controller!.value;
        final context = tester.element(find.byType(LinearProgressIndicator));
        expect(Theme.of(context).brightness, brightness);
        expect(progress.semanticsLabel,
            AppLocalizations.of(context)!.quickSyncNotificationInProgress);
        expect(Directionality.of(context), TextDirection.rtl);
        await tester.pump(const Duration(milliseconds: 500));
        expect(progress.controller!.value, phase);
      });
    });
  }
}

Future<void> withActivity(WidgetTester tester,
    Future<void> Function(ActivityHarness activity) body) async {
  final fixture = (await tester.runAsync(SyncFixture.create))!;
  final activity = ActivityHarness(tester, fixture);
  try {
    await body(activity);
    expect(tester.takeException(), isNull);
  } finally {
    resumeActivity(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(() => SessionWork.maintain(() async {
          for (final lease in activity.leases) {
            if (lease.isValid) await lease.release();
          }
        }));
    activity.input.dispose();
    activity.focus.dispose();
    await tester.runAsync(fixture.dispose);
  }
}

void resumeActivity(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

class ActivityHarness {
  ActivityHarness(this.tester, this.fixture);
  final WidgetTester tester;
  final SyncFixture fixture;
  final leases = <OperationLease>[];
  final input = TextEditingController();
  final focus = FocusNode();

  Future<OperationLease> acquire(String id) async {
    final lease = (await tester.runAsync<OperationLease?>(
        () => ExclusiveOperationCoordinator.tryAcquire(id)))!;
    leases.add(lease);
    return lease;
  }

  Future<void> release(OperationLease lease) async {
    await tester.runAsync(lease.release);
  }

  void signal(String id, EventKey key) =>
      EventStream().publish(AppEvent(type: EventType.system, id: id, key: key));

  Future<void> mount(
          {Brightness brightness = Brightness.light,
          bool reduceMotion = false,
          Locale locale = const Locale('en')}) =>
      tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: child!),
          home: SyncActivityOverlay(
              child: Scaffold(
                  body: TextField(
                      key: const ValueKey('input'),
                      controller: input,
                      focusNode: focus)))));

  Future<void> flush({bool tick = false}) async {
    if (tick) await tester.pump(const Duration(seconds: 1));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 10));
    }
  }
}
