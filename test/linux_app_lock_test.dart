import 'dart:io';

import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/app_lock_fixture.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const prompt = AppLockPrompt(
      reason: 'test', title: 'test', hint: 'test', cancel: 'Cancel');
  final calls = <String>[];
  bool supported = true, accepted = true;
  setUp(() {
    calls.clear();
    supported = true;
    accepted = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        LinuxAppLockAuthenticator.channel, (call) async {
      calls.add(call.method);
      expect(call.arguments, isNull,
          reason: 'No credentials pass through Dart');
      return switch (call.method) {
        'isSupported' => supported,
        'authenticate' => accepted,
        'cancel' => null,
        _ => throw StateError('Unexpected native method'),
      };
    });
  });
  tearDown(() => binding.defaultBinaryMessenger
      .setMockMethodCallHandler(LinuxAppLockAuthenticator.channel, null));

  test('Linux native authentication adapter requires an affirmative result',
      () async {
    const auth = LinuxAppLockAuthenticator();
    expect(await auth.isSupported(), isTrue);
    accepted = false;
    expect(await auth.authenticate(prompt), isFalse);
    accepted = true;
    expect(await auth.authenticate(prompt), isTrue);
    await auth.cancel();
    expect(calls, ['isSupported', 'authenticate', 'authenticate', 'cancel']);
  });

  test(
      'default Linux controller reaches system authentication and fails closed',
      () async {
    final store = MemoryAppLockStore();
    final controller = AppLockController(store: store);
    addTearDown(controller.dispose);
    await controller.load();
    supported = false;
    expect(await controller.setEnabled(true, prompt), isFalse);
    expect(controller.enabled, isFalse);
    expect(controller.failure, AppLockFailure.authenticationUnavailable);
    expect(calls, ['isSupported']);
    supported = true;
    expect(await controller.setEnabled(true, prompt), isTrue);
    expect(controller.enabled, isTrue);
    expect(controller.minutes, 5);
    accepted = false;
    expect(await controller.authorizeSensitiveAction(prompt), isNull);
    accepted = true;
    expect(await controller.authorizeSensitiveAction(prompt), isNotNull);
  }, skip: !Platform.isLinux);
}
