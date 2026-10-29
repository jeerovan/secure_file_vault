import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Controlled OS transport for host widget tests. It does not establish native
/// window/screen-lock delivery; those require the actual macOS runner.
class NativePrivacyFixture with WidgetsBindingObserver {
  static const channel = MethodChannel('com.jeerovan.fife/app_lock_privacy');
  static const export = MethodChannel('com.jeerovan.fife/recovery_export');
  final _messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  int _revision = 0;
  bool _active = true;

  void install() {
    WidgetsBinding.instance.addObserver(this);
    _messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'observeLifecycle') {
        return {'active': _active, 'revision': _revision};
      }
      return null;
    });
    _messenger.setMockMethodCallHandler(export, (call) async {
      if (call.method == 'reserve') return 'synthetic-export-reservation';
      if (call.method == 'save') return false;
      return null;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _revision++;
    unawaited(_messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(
            'lifecycle', {'active': _active, 'revision': _revision})),
        (_) {}));
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messenger.setMockMethodCallHandler(channel, null);
    _messenger.setMockMethodCallHandler(export, null);
  }
}
