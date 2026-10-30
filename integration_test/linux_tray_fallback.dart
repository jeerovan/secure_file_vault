import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Exercises the production GTK runner with no vault, keyring or network work.
/// Only the desktop host is substituted; Close uses the real native window.
Future<void> main() async {
  final root = Platform.environment['FIFE_LINUX_TRAY_TEST_ROOT'];
  if (!Platform.isLinux ||
      !const bool.fromEnvironment('FIFE_LINUX_TRAY_VERIFICATION') ||
      root == null ||
      !File('$root/synthetic-fixture.marker').existsSync()) {
    throw StateError('Explicit isolated tray fixture required');
  }
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  const privacy = MethodChannel('com.jeerovan.fife/app_lock_privacy');
  privacy.setMethodCallHandler((call) async {
    if (call.method == 'lifecycle' && call.arguments['active'] == true) {
      await privacy
          .invokeMethod<void>('frameReady', {'allowNativeDocuments': false});
    }
  });
  await privacy.invokeMethod<void>('setEnabled', false);
  await privacy.invokeMethod<Object?>('observeLifecycle');
  runApp(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Tray fallback fixture')))));
  await WidgetsBinding.instance.endOfFrame;
  await privacy
      .invokeMethod<void>('frameReady', {'allowNativeDocuments': false});
  await File('$root/ready-$pid').writeAsString('native-runner-ready');
}
