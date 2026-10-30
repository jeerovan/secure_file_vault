import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'package:local_auth_darwin/types/auth_messages_macos.dart';

import '../models/model_setting.dart';
import '../utils/enums.dart';
import 'service_session_work.dart';

class AppLockPolicy {
  const AppLockPolicy({this.enabled = false, this.minutes = 5});
  final bool enabled;
  final int minutes;
}

abstract interface class AppLockStore {
  Future<AppLockPolicy> read();
  Future<void> setEnabled(bool enabled);
  Future<void> setTimeout(int minutes);
}

class ModelAppLockStore implements AppLockStore {
  @override
  Future<AppLockPolicy> read() async {
    return SessionWork.authenticate(() async {
      final enabled =
          await ModelSetting.getRaw(AppString.appLockEnabled.string);
      final minutes =
          await ModelSetting.getRaw(AppString.appLockTimeoutMinutes.string);
      // An unrecognized saved policy must not silently disable protection.
      return AppLockPolicy(
        enabled: enabled.isNotEmpty && enabled != 'no',
        minutes: ModelSetting.parseAppLockTimeoutMinutes(minutes),
      );
    });
  }

  @override
  Future<void> setEnabled(bool enabled) =>
      ModelSetting.set(AppString.appLockEnabled.string, enabled ? 'yes' : 'no');

  @override
  Future<void> setTimeout(int minutes) =>
      ModelSetting.set(AppString.appLockTimeoutMinutes.string, '$minutes');
}

class AppLockPrompt {
  const AppLockPrompt(
      {required this.reason,
      required this.title,
      required this.hint,
      required this.cancel});
  final String reason;
  final String title;
  final String hint;
  final String cancel;
}

abstract interface class AppLockAuthenticator {
  Future<bool> isSupported();
  Future<bool> authenticate(AppLockPrompt prompt);
  Future<void> cancel();
}

class SystemAppLockAuthenticator implements AppLockAuthenticator {
  SystemAppLockAuthenticator({LocalAuthentication? authentication})
      : _auth = authentication ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate(AppLockPrompt prompt) => _auth.authenticate(
        localizedReason: prompt.reason,
        biometricOnly: false,
        // Cancellation returns to our locked screen. Native automatic retries
        // can create overlapping credential activities on older Android.
        persistAcrossBackgrounding: false,
        authMessages: [
          AndroidAuthMessages(
              signInTitle: prompt.title,
              signInHint: prompt.hint,
              cancelButton: prompt.cancel),
          IOSAuthMessages(cancelButton: prompt.cancel),
          MacOSAuthMessages(cancelButton: prompt.cancel),
        ],
      );

  @override
  Future<void> cancel() async {
    await _auth.stopAuthentication();
  }
}

/// Linux's desktop authentication agent owns credentials and the system prompt.
/// The native side requires a fresh, non-cached current-user polkit challenge.
class LinuxAppLockAuthenticator implements AppLockAuthenticator {
  const LinuxAppLockAuthenticator();
  static const channel = MethodChannel('com.jeerovan.fife/linux_auth');
  @override
  Future<bool> isSupported() async =>
      await channel.invokeMethod<bool>('isSupported') ?? false;
  @override
  Future<bool> authenticate(AppLockPrompt prompt) async =>
      await channel.invokeMethod<bool>('authenticate') ?? false;
  @override
  Future<void> cancel() => channel.invokeMethod<void>('cancel');
}

enum AppLockFailure {
  authenticationUnavailable,
  authenticationFailed,
  storageUnavailable
}

class AppLockAccessDenied implements Exception {
  const AppLockAccessDenied();
}

/// An in-memory proof for one sensitive view, never a saved unlock or PIN.
class AppLockAuthorization {
  AppLockAuthorization._(this.controller, this._epoch, this._revision);
  final AppLockController controller;
  final int _epoch;
  final String _revision;
  bool _revoked = false;

  bool get isValid =>
      !_revoked &&
      controller._current(_epoch, _revision) &&
      controller.ready &&
      controller.enabled &&
      !controller.locked &&
      SessionWork.active &&
      !SessionWork.authenticationRequired;

  bool get available => isValid && controller.foreground;

  void requireAvailable() {
    if (!available) throw const AppLockAccessDenied();
  }

  void revoke() => _revoked = true;
}

/// Protects foreground UI only. It never invalidates keys, sessions or sync work.
/// Inactivity counts device sleep as well as elapsed runtime. Clock rollback
/// fails closed; a new process never inherits an unlock.
class AppLockController extends ChangeNotifier {
  AppLockController(
      {AppLockStore? store,
      AppLockAuthenticator? authenticator,
      Duration Function()? clock,
      DateTime Function()? wallClock})
      : _store = store ?? ModelAppLockStore(),
        _auth = authenticator ??
            (Platform.isLinux
                ? const LinuxAppLockAuthenticator()
                : SystemAppLockAuthenticator()) {
    final stopwatch = Stopwatch()..start();
    _now = clock ?? (() => stopwatch.elapsed);
    _wallNow = wallClock ?? DateTime.now;
  }

  final AppLockStore _store;
  final AppLockAuthenticator _auth;
  late final Duration Function() _now;
  late final DateTime Function() _wallNow;
  bool _ready = false, _enabled = false, _locked = true, _busy = false;
  bool _foreground = true, _disposed = false;
  int _minutes = ModelSetting.defaultAppLockTimeoutMinutes;
  int _epoch = 0, _lockRevision = 0;
  Duration? _leftAt;
  DateTime? _leftWallAt;
  AppLockFailure? _failure;
  Future<bool>? _authentication;
  Future<void>? _cancellation;

  bool get ready => _ready;
  bool get enabled => _enabled;
  bool get locked => _locked;
  bool get busy => _busy;
  bool get foreground => _foreground;
  bool get concealed => !_ready || (_enabled && (_locked || !_foreground));
  int get minutes => _minutes;
  int get lockRevision => _lockRevision;
  AppLockFailure? get failure => _failure;

  bool _current(int epoch, String revision) =>
      !_disposed &&
      epoch == _epoch &&
      revision == SessionWork.revision &&
      (SessionWork.active || SessionWork.authenticationRequired);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _cancel();
    final epoch = ++_epoch, revision = SessionWork.revision;
    _ready = false;
    _locked = true;
    _failure = null;
    _notify();
    try {
      final policy = await _store.read();
      if (!_current(epoch, revision)) return;
      _enabled = policy.enabled;
      _minutes = ModelSetting.parseAppLockTimeoutMinutes('${policy.minutes}');
      _locked = _enabled;
      _ready = true;
      _leftAt = null;
      _leftWallAt = null;
      if (_locked) _lockRevision++;
    } catch (_) {
      if (!_current(epoch, revision)) return;
      _failure = AppLockFailure.storageUnavailable;
    }
    _notify();
  }

  void handleLifecycle(AppLifecycleState state) {
    if (_disposed) return;
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _foreground) return;
    _foreground = resumed;
    if (!resumed) {
      _leftAt = _now();
      _leftWallAt = _wallNow();
    } else {
      final leftAt = _leftAt;
      if (_enabled && !_locked && leftAt != null) {
        final away = _now() - leftAt;
        final wallAway = _wallNow().difference(_leftWallAt!);
        final timeout = Duration(minutes: _minutes);
        if (away.isNegative ||
            wallAway.isNegative ||
            away >= timeout ||
            wallAway >= timeout) {
          _locked = true;
          _lockRevision++;
          _failure = null;
        }
      }
      _leftAt = null;
      _leftWallAt = null;
    }
    _notify();
  }

  Future<bool> unlock(AppLockPrompt prompt) {
    if (_authentication case final pending?) return pending;
    if (!_ready || !_enabled || !_locked) {
      return Future.value(_ready && !_locked);
    }
    if (!_foreground || _busy) return Future.value(false);
    return _authenticate(prompt);
  }

  Future<bool> setEnabled(bool enabled, AppLockPrompt prompt) {
    if (!_ready || _busy || !_foreground || _locked || enabled == _enabled) {
      return Future.value(false);
    }
    return _authenticate(prompt, nextEnabled: enabled);
  }

  /// A normal unlocked/grace-period session is not proof for exporting keys.
  /// Never share an in-flight unlock/settings prompt with a sensitive action.
  Future<AppLockAuthorization?> authorizeSensitiveAction(
      AppLockPrompt prompt) async {
    if (!_ready ||
        !_enabled ||
        _locked ||
        _busy ||
        !_foreground ||
        !SessionWork.active ||
        SessionWork.authenticationRequired) {
      return null;
    }
    final revision = SessionWork.revision;
    final authentication = _authenticate(prompt);
    final epoch = _epoch;
    if (!await authentication || !_current(epoch, revision)) return null;
    final proof = AppLockAuthorization._(this, epoch, revision);
    return proof.isValid ? proof : null;
  }

  Future<bool> _authenticate(AppLockPrompt prompt, {bool? nextEnabled}) {
    final future = _authenticateOnce(prompt, nextEnabled: nextEnabled);
    _authentication = future;
    unawaited(future.then((_) {
      if (identical(_authentication, future)) _authentication = null;
    }));
    return future;
  }

  Future<bool> _authenticateOnce(AppLockPrompt prompt,
      {bool? nextEnabled}) async {
    final epoch = ++_epoch, revision = SessionWork.revision;
    _busy = true;
    _failure = null;
    _notify();
    try {
      if (_cancellation case final pending?) await pending;
      if (!_current(epoch, revision)) return false;
      final supported = await _auth.isSupported();
      if (!_current(epoch, revision)) return false;
      if (!supported) {
        _failure = AppLockFailure.authenticationUnavailable;
        return false;
      }
      final authenticated = await _auth.authenticate(prompt);
      if (!_current(epoch, revision)) return false;
      if (!authenticated) {
        _failure = AppLockFailure.authenticationFailed;
        return false;
      }
      if (nextEnabled != null) {
        try {
          await _store.setEnabled(nextEnabled);
        } catch (_) {
          if (_current(epoch, revision)) {
            _ready = false;
            _locked = true;
            _failure = AppLockFailure.storageUnavailable;
          }
          return false;
        }
        if (!_current(epoch, revision)) return false;
        _enabled = nextEnabled;
      }
      _locked = false;
      // Native authentication itself can briefly deactivate the application.
      // A success received while inactive remains hidden until resume.
      _leftAt = _foreground ? null : _now();
      _leftWallAt = _foreground ? null : _wallNow();
      return true;
    } on LocalAuthException catch (error) {
      if (_current(epoch, revision)) {
        _failure = error.code == LocalAuthExceptionCode.noCredentialsSet ||
                error.code == LocalAuthExceptionCode.noBiometricHardware
            ? AppLockFailure.authenticationUnavailable
            : AppLockFailure.authenticationFailed;
      }
      return false;
    } catch (_) {
      if (_current(epoch, revision)) {
        _failure = AppLockFailure.authenticationFailed;
      }
      return false;
    } finally {
      if (_current(epoch, revision)) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<bool> setTimeout(int minutes) async {
    if (!_ready ||
        !_enabled ||
        _locked ||
        _busy ||
        !ModelSetting.appLockTimeoutChoices.contains(minutes)) {
      return false;
    }
    final epoch = ++_epoch, revision = SessionWork.revision;
    _busy = true;
    _failure = null;
    _notify();
    try {
      await _store.setTimeout(minutes);
      if (!_current(epoch, revision)) return false;
      _minutes = minutes;
      return true;
    } catch (_) {
      if (_current(epoch, revision)) {
        _ready = false;
        _locked = true;
        _failure = AppLockFailure.storageUnavailable;
      }
      return false;
    } finally {
      if (_current(epoch, revision)) {
        _busy = false;
        _notify();
      }
    }
  }

  /// The root also discards routes. No old authentication result can authorize
  /// the replacement account, even if the system dialog completes afterward.
  void invalidateSession() {
    _epoch++;
    _ready = false;
    _locked = true;
    _failure = null;
    _cancel();
    _notify();
  }

  void _cancel() {
    if (_busy) {
      _cancellation = _auth.cancel().catchError((Object _) {});
    }
    _busy = false;
    _authentication = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _cancel();
    super.dispose();
  }
}
