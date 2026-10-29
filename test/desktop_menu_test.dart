import 'dart:async';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/models/model_state.dart';
import 'package:file_vault_bb/services/service_desktop_menu.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jeerovan.fife/desktop');
  final updates = <Map<Object?, Object?>>[];
  late SyncFixture fixture;
  DesktopMenuController? controller;
  int syncs = 0;

  Future<void> until(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  void event(EventKey key) => EventStream()
      .publish(AppEvent(type: EventType.system, id: 'fixture', key: key));

  Future<void> ready() async {
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
  }

  Future<void> clickSync() async {
    final done = Completer<void>();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(const MethodCall('sync')),
        (_) => done.complete());
    await done.future;
  }

  setUp(() async {
    SessionWork.resetForTesting();
    fixture = await SyncFixture.create();
    updates.clear();
    syncs = 0;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'updateMenu');
      updates.add(Map<Object?, Object?>.from(call.arguments as Map));
      return null;
    });
  });
  tearDown(() async {
    controller?.dispose();
    controller = null;
    await fixture.dispose();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    SessionWork.resetForTesting();
  });

  DesktopMenuController start({Future<void> Function()? sync}) {
    controller = DesktopMenuController(
        sync: sync ??
            () async {
              syncs++;
            });
    controller!.setLabels({
      'open': 'Ouvrir',
      'sync': 'Synchroniser',
      'syncing': 'En cours…',
      'quit': 'Quitter'
    });
    controller!.start();
    return controller!;
  }

  test(
      'normal startup attaches disabled, then completed onboarding enables the native action',
      () async {
    start();
    await until(() => updates.isNotEmpty);
    expect(updates.last['syncEnabled'], false);
    await clickSync();
    expect(syncs, 0);
    await ready();
    event(EventKey.authenticated);
    await until(() => updates.last['syncEnabled'] == true);
    expect(updates.last['open'], 'Ouvrir');
    expect(updates.last['quit'], 'Quitter');
    await clickSync();
    expect(syncs, 1);
    await until(() => updates.last['syncEnabled'] == true);
    // App lock does not prevent already-authorized background sync.
    await ModelSetting.set(AppString.appLockEnabled.string, 'yes');
    await clickSync();
    expect(syncs, 2);
  });

  test(
      'a saved ready session works on first construction without an auth event',
      () async {
    await ready();
    start();
    await until(
        () => updates.isNotEmpty && updates.last['syncEnabled'] == true);
    await clickSync();
    expect(syncs, 1);
  });

  for (final state in ['onboarding', 'signout', 'device', 'reset', 'keys']) {
    test('stale enabled menu cannot sync after $state changes', () async {
      await ready();
      start();
      await until(
          () => updates.isNotEmpty && updates.last['syncEnabled'] == true);
      switch (state) {
        case 'onboarding':
          await ModelSetting.delete(AppString.onboarding.string);
        case 'signout':
          await ModelSetting.set(AppString.signedIn.string, 'no');
        case 'device':
          await ModelSetting.delete(AppString.deviceUuid.string);
        case 'reset':
          fixture.secrets[AppString.recoveryResetStage.string] = 'pending';
        case 'keys':
          fixture.secrets[AppString.vaultKeySetupStage.string] = 'pending';
      }
      await clickSync();
      expect(syncs, 0);
      await until(() => updates.last['syncEnabled'] == false);
    });
  }

  test('busy request rejects duplicate native clicks and returns to ready',
      () async {
    await ready();
    final gate = Completer<void>();
    start(sync: () async {
      syncs++;
      await gate.future;
    });
    await until(
        () => updates.isNotEmpty && updates.last['syncEnabled'] == true);
    final first = clickSync();
    await until(() => syncs == 1 && updates.last['busy'] == true);
    expect(updates.last['syncEnabled'], false);
    await clickSync();
    expect(syncs, 1);
    gate.complete();
    await first;
    await until(() =>
        updates.last['busy'] == false && updates.last['syncEnabled'] == true);
  });

  test('active transfers disable Sync; expired leases do not', () async {
    await ready();
    await ModelState.set('operation_lease:transfer:menu-fixture',
        '{"owner":"fixture","expires_at":${DateTime.now().toUtc().add(const Duration(minutes: 1)).millisecondsSinceEpoch}}');
    final menu = start();
    await until(() => updates.isNotEmpty && updates.last['busy'] == true);
    await clickSync();
    expect(syncs, 0);
    await ModelState.set('operation_lease:transfer:menu-fixture', '1');
    await menu.refresh();
    await until(() => updates.last['syncEnabled'] == true);
    await clickSync();
    expect(syncs, 1);
  });

  test('a late key read cannot enable or sync a revoked session', () async {
    await ready();
    final entered = Completer<void>(), resume = Completer<void>();
    fixture.beforeRead = (key) async {
      if (key == AppString.masterKey.string) {
        if (!entered.isCompleted) entered.complete();
        await resume.future;
      }
    };
    start();
    await entered.future;
    SessionWork.invalidate('revoked-fixture');
    event(EventKey.sessionInvalidated);
    resume.complete();
    await until(
        () => updates.isNotEmpty && updates.last['syncEnabled'] == false);
    await clickSync();
    expect(syncs, 0);
  });

  test('authentication hold denies menu sync even in the public sign-in zone',
      () async {
    await ready();
    start();
    await until(
        () => updates.isNotEmpty && updates.last['syncEnabled'] == true);
    SessionWork.complete(SessionWork.revision, authenticationRequired: true);
    await SessionWork.authenticate(() => controller!.sync());
    expect(syncs, 0);
  });

  test('temporary storage and sync failures recover without a stuck busy menu',
      () async {
    await ready();
    var fail = true;
    fixture.beforeRead = (_) async {
      if (fail) throw StateError('storage unavailable');
    };
    final menu = start(sync: () async {
      syncs++;
      throw StateError('temporary sync failure');
    });
    await until(() => updates.isNotEmpty);
    await menu.refresh();
    expect(updates.last['syncEnabled'], false);
    fail = false;
    await menu.refresh();
    await until(() => updates.last['syncEnabled'] == true);
    await clickSync();
    expect(syncs, 1);
    await until(() =>
        updates.last['busy'] == false && updates.last['syncEnabled'] == true);
  });
}
