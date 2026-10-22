import 'package:file_vault_bb/services/service_app_lock.dart';

class MemoryAppLockStore implements AppLockStore {
  bool enabled = false;
  int minutes = 5;
  Future<AppLockPolicy> Function()? onRead;
  Future<void> Function(bool)? onSetEnabled;
  Future<void> Function(int)? onSetTimeout;

  @override
  Future<AppLockPolicy> read() async => onRead != null
      ? onRead!()
      : AppLockPolicy(enabled: enabled, minutes: minutes);
  @override
  Future<void> setEnabled(bool value) async {
    if (onSetEnabled != null) return onSetEnabled!(value);
    enabled = value;
  }

  @override
  Future<void> setTimeout(int value) async {
    if (onSetTimeout != null) return onSetTimeout!(value);
    minutes = value;
  }
}

class FakeAppLockAuthenticator implements AppLockAuthenticator {
  bool supported = true;
  bool result = true;
  int attempts = 0, cancellations = 0;
  Future<bool> Function(AppLockPrompt)? onAuthenticate;
  AppLockPrompt? prompt;

  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> authenticate(AppLockPrompt value) async {
    attempts++;
    prompt = value;
    return onAuthenticate != null ? onAuthenticate!(value) : result;
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

const testAppLockPrompt = AppLockPrompt(
    reason: 'Unlock fixture',
    title: 'App lock',
    hint: 'Verify identity',
    cancel: 'Cancel');
