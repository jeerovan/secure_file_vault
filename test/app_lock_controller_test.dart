import 'dart:async';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import 'support/app_lock_fixture.dart';

void main() {
  late MemoryAppLockStore store;
  late FakeAppLockAuthenticator auth;
  late AppLockController lock;
  late Duration time;

  setUp(() {
    SessionWork.resetForTesting();
    store = MemoryAppLockStore();
    auth = FakeAppLockAuthenticator();
    time = Duration.zero;
    lock =
        AppLockController(store: store, authenticator: auth, clock: () => time);
  });
  tearDown(() {
    lock.dispose();
    SessionWork.resetForTesting();
  });

  Future<void> unlocked({int minutes = 5}) async {
    store.enabled = true;
    store.minutes = minutes;
    await lock.load();
    expect(await lock.unlock(testAppLockPrompt), isTrue);
  }

  test(
      'native cancellation returns control without automatic background retries',
      () async {
    final native = _NativeAuthenticationProbe();
    final adapter = SystemAppLockAuthenticator(authentication: native);
    expect(await adapter.authenticate(testAppLockPrompt), isFalse);
    expect(native.retryAfterBackground, isFalse,
        reason: 'A canceled system prompt must stay dismissed until Unlock');
    expect(native.biometricsRequired, isFalse,
        reason: 'The device PIN/passcode fallback must remain available');
  });

  test(
      'fresh installations are off with five-minute default and no authentication',
      () async {
    expect(lock.concealed, isTrue);
    await lock.load();
    expect(lock.enabled, isFalse);
    expect(lock.minutes, 5);
    expect(lock.concealed, isFalse);
    expect(auth.attempts, 0);
  });

  test('only the seven specified timeout values are accepted', () {
    for (final value in [1, 5, 10, 15, 20, 25, 30]) {
      expect(ModelSetting.parseAppLockTimeoutMinutes('$value'), value);
    }
    for (final invalid in ['', 'garbage', '-1', '0', '2', '29', '31', '5.0']) {
      expect(ModelSetting.parseAppLockTimeoutMinutes(invalid), 5);
    }
  });

  for (final minutes in [1, 5, 10, 15, 20, 25, 30]) {
    test(
        'return before $minutes minutes keeps the unlock; exact boundary locks',
        () async {
      await unlocked(minutes: minutes);
      lock.handleLifecycle(AppLifecycleState.inactive);
      expect(lock.concealed, isTrue);
      time += Duration(minutes: minutes) - const Duration(milliseconds: 1);
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.locked, isFalse);
      expect(lock.concealed, isFalse);
      expect(auth.attempts, 1);
      lock.handleLifecycle(AppLifecycleState.paused);
      time += Duration(minutes: minutes);
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.locked, isTrue);
      expect(lock.concealed, isTrue);
    });
  }

  test('inactive followed by paused does not restart the inactivity timer',
      () async {
    await unlocked(minutes: 1);
    lock.handleLifecycle(AppLifecycleState.inactive);
    time += const Duration(seconds: 59);
    lock.handleLifecycle(AppLifecycleState.hidden);
    lock.handleLifecycle(AppLifecycleState.paused);
    time += const Duration(seconds: 1);
    lock.handleLifecycle(AppLifecycleState.resumed);
    expect(lock.locked, isTrue);
  });

  test('active use does not expire; each short return counts as use', () async {
    await unlocked();
    time += const Duration(hours: 8);
    expect(lock.locked, isFalse);
    for (var visit = 0; visit < 5; visit++) {
      lock.handleLifecycle(AppLifecycleState.paused);
      time += const Duration(minutes: 4);
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.concealed, isFalse);
    }
    expect(auth.attempts, 1);
  });

  test('restarting the app never restores an earlier unlock grant', () async {
    await unlocked(minutes: 30);
    final next = AppLockController(store: store, authenticator: auth);
    addTearDown(next.dispose);
    await next.load();
    expect(next.enabled, isTrue);
    expect(next.minutes, 30);
    expect(next.concealed, isTrue);
  });

  for (final wallChange in [
    const Duration(minutes: 5),
    const Duration(minutes: -1)
  ]) {
    test(
        'device sleep or wall-clock rollback cannot prolong an unlock ($wallChange)',
        () async {
      lock.dispose();
      var wall = DateTime(2026, 10, 22);
      lock = AppLockController(
          store: store,
          authenticator: auth,
          clock: () => time,
          wallClock: () => wall);
      await unlocked();
      lock.handleLifecycle(AppLifecycleState.paused);
      // CLOCK_MONOTONIC can stop during deep sleep on a mobile device.
      wall = wall.add(wallChange);
      lock.handleLifecycle(AppLifecycleState.resumed);
      expect(lock.locked, isTrue);
    });
  }

  test('enabling is persisted only after successful authentication', () async {
    await lock.load();
    final response = Completer<bool>();
    auth.onAuthenticate = (_) => response.future;
    final enabling = lock.setEnabled(true, testAppLockPrompt);
    expect(lock.busy, isTrue);
    expect(store.enabled, isFalse);
    response.complete(true);
    expect(await enabling, isTrue);
    expect(store.enabled, isTrue);
    expect(lock.enabled, isTrue);
    expect(lock.locked, isFalse);
  });

  test('canceled enable and absent device credentials cannot enable the lock',
      () async {
    await lock.load();
    auth.result = false;
    expect(await lock.setEnabled(true, testAppLockPrompt), isFalse);
    expect(store.enabled, isFalse);
    auth.supported = false;
    expect(await lock.setEnabled(true, testAppLockPrompt), isFalse);
    expect(lock.failure, AppLockFailure.authenticationUnavailable);
    expect(store.enabled, isFalse);
  });

  test(
      'canceling unlock leaves the vault protected and allows an explicit retry',
      () async {
    store.enabled = true;
    await lock.load();
    auth.result = false;
    expect(await lock.unlock(testAppLockPrompt), isFalse);
    expect(lock.concealed, isTrue);
    expect(lock.failure, AppLockFailure.authenticationFailed);
    auth.result = true;
    expect(await lock.unlock(testAppLockPrompt), isTrue);
    expect(lock.failure, isNull);
    expect(lock.concealed, isFalse);
  });

  for (final code in [
    LocalAuthExceptionCode.noCredentialsSet,
    LocalAuthExceptionCode.temporaryLockout,
    LocalAuthExceptionCode.biometricLockout,
    LocalAuthExceptionCode.systemCanceled,
    LocalAuthExceptionCode.userCanceled
  ]) {
    test('native $code errors cannot unlock', () async {
      store.enabled = true;
      await lock.load();
      auth.onAuthenticate = (_) async => throw LocalAuthException(code: code);
      expect(await lock.unlock(testAppLockPrompt), isFalse);
      expect(lock.concealed, isTrue);
      expect(lock.busy, isFalse);
    });
  }

  test('a missing or throwing native plugin fails closed', () async {
    store.enabled = true;
    await lock.load();
    auth.onAuthenticate = (_) async => throw StateError('platform unavailable');
    expect(await lock.unlock(testAppLockPrompt), isFalse);
    expect(lock.concealed, isTrue);
  });

  test('concurrent unlocks join one native prompt', () async {
    store.enabled = true;
    await lock.load();
    final response = Completer<bool>();
    auth.onAuthenticate = (_) => response.future;
    final first = lock.unlock(testAppLockPrompt);
    final second = lock.unlock(testAppLockPrompt);
    expect(identical(first, second), isTrue);
    response.complete(true);
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(auth.attempts, 1);
  });

  test(
      'native prompt deactivation cannot reveal the inactive app or cause a second prompt',
      () async {
    store.enabled = true;
    await lock.load();
    auth.onAuthenticate = (_) async {
      lock.handleLifecycle(AppLifecycleState.inactive);
      return true;
    };
    expect(await lock.unlock(testAppLockPrompt), isTrue);
    expect(lock.concealed, isTrue);
    lock.handleLifecycle(AppLifecycleState.resumed);
    expect(lock.concealed, isFalse);
    expect(auth.attempts, 1);
  });

  test(
      'disabling requires authentication and cancellation preserves the policy',
      () async {
    await unlocked();
    auth.result = false;
    expect(await lock.setEnabled(false, testAppLockPrompt), isFalse);
    expect(store.enabled, isTrue);
    auth.result = true;
    expect(await lock.setEnabled(false, testAppLockPrompt), isTrue);
    expect(store.enabled, isFalse);
    lock.handleLifecycle(AppLifecycleState.paused);
    time += const Duration(hours: 1);
    lock.handleLifecycle(AppLifecycleState.resumed);
    expect(lock.concealed, isFalse);
  });

  test(
      'timeout persistence accepts all choices and rejects intermediate values',
      () async {
    await unlocked();
    for (final invalid in [0, 2, 3, 6, 29, 31]) {
      expect(await lock.setTimeout(invalid), isFalse);
      expect(store.minutes, 5);
    }
    for (final value in [1, 5, 10, 15, 20, 25, 30]) {
      expect(await lock.setTimeout(value), isTrue);
      expect(store.minutes, value);
      expect(lock.minutes, value);
    }
  });

  test('unreadable saved settings conceal content until a successful retry',
      () async {
    store.onRead = () async => throw StateError('unreadable');
    await lock.load();
    expect(lock.ready, isFalse);
    expect(lock.concealed, isTrue);
    expect(lock.failure, AppLockFailure.storageUnavailable);
    store.onRead = null;
    await lock.load();
    expect(lock.ready, isTrue);
    expect(lock.concealed, isFalse);
  });

  test(
      'ambiguous enable write remains concealed and reloads the durable policy',
      () async {
    await lock.load();
    store.onSetEnabled = (value) async {
      store.enabled = value;
      throw StateError('lost write response');
    };
    expect(await lock.setEnabled(true, testAppLockPrompt), isFalse);
    expect(lock.ready, isFalse);
    expect(lock.concealed, isTrue);
    await lock.load();
    expect(lock.enabled, isTrue);
    expect(lock.locked, isTrue);
  });

  test('failed timeout save cannot leave a contradictory unlocked policy',
      () async {
    await unlocked();
    store.onSetTimeout = (_) async => throw StateError('disk full');
    expect(await lock.setTimeout(1), isFalse);
    expect(lock.concealed, isTrue);
    expect(store.minutes, 5);
    await lock.load();
    expect(lock.minutes, 5);
    expect(lock.locked, isTrue);
  });

  test('old authentication cannot authorize a replacement session', () async {
    store.enabled = true;
    await lock.load();
    final response = Completer<bool>();
    auth.onAuthenticate = (_) => response.future;
    final old = lock.unlock(testAppLockPrompt);
    await Future<void>.delayed(Duration.zero);
    SessionWork.invalidate('replacement');
    lock.invalidateSession();
    SessionWork.complete('replacement');
    await lock.load();
    response.complete(true);
    expect(await old, isFalse);
    expect(lock.concealed, isTrue);
    expect(lock.busy, isFalse);
    expect(auth.cancellations, 1);
  });

  test('an obsolete policy read cannot replace the new session policy',
      () async {
    final old = Completer<AppLockPolicy>();
    store.onRead = () => old.future;
    final loading = lock.load();
    lock.invalidateSession();
    store.onRead = null;
    await lock.load();
    old.complete(const AppLockPolicy(enabled: true));
    await loading;
    expect(lock.enabled, isFalse);
    expect(lock.concealed, isFalse);
  });

  test('disposing cancels authentication and ignores its late success',
      () async {
    store.enabled = true;
    await lock.load();
    final response = Completer<bool>();
    auth.onAuthenticate = (_) => response.future;
    final pending = lock.unlock(testAppLockPrompt);
    await Future<void>.delayed(Duration.zero);
    lock.dispose();
    response.complete(true);
    expect(await pending, isFalse);
    expect(auth.cancellations, 1);
    // A second dispose is avoided by replacing the tearDown-owned controller.
    lock = AppLockController(store: store, authenticator: auth);
  });
}

class _NativeAuthenticationProbe extends LocalAuthentication {
  bool? retryAfterBackground, biometricsRequired;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    Iterable<AuthMessages> authMessages = const [],
    bool biometricOnly = false,
    bool sensitiveTransaction = true,
    bool persistAcrossBackgrounding = false,
  }) async {
    retryAfterBackground = persistAcrossBackgrounding;
    biometricsRequired = biometricOnly;
    return false;
  }
}
