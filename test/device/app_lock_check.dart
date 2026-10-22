// Interactive native acceptance harness. It cannot run in a normal install.
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/app_lock.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../integration_test/support/native_test_identity.dart';

class _ObservedDeviceAuth extends SystemAppLockAuthenticator {
  @override
  Future<bool> authenticate(AppLockPrompt prompt) async {
    debugPrint('APP_LOCK_NATIVE:prompt');
    final result = await super.authenticate(prompt);
    debugPrint('APP_LOCK_NATIVE:authentication=$result');
    return result;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!const bool.fromEnvironment('FIFE_APP_LOCK_NATIVE_CHECK') ||
      !isIsolatedNativeTestBundle(
          (await PackageInfo.fromPlatform()).packageName)) {
    throw StateError(
        'App lock acceptance requires an isolated test installation');
  }
  await StorageSqlite.initialize(ExecutionMode.mainApp);
  final controller = AppLockController(authenticator: _ObservedDeviceAuth());
  runApp(_AppLockNativeCheck(controller: controller));
  await controller.load();
}

class _AppLockNativeCheck extends StatefulWidget {
  const _AppLockNativeCheck({required this.controller});
  final AppLockController controller;
  @override
  State<_AppLockNativeCheck> createState() => _AppLockNativeCheckState();
}

class _AppLockNativeCheckState extends State<_AppLockNativeCheck> {
  late final AppLockNavigatorObserver _observer;
  Locale _locale = const Locale('en');

  @override
  void initState() {
    super.initState();
    _observer = AppLockNavigatorObserver(widget.controller);
    widget.controller.addListener(_receipt);
  }

  void _receipt() {
    final c = widget.controller;
    debugPrint('APP_LOCK_NATIVE:ready=${c.ready};enabled=${c.enabled};'
        'locked=${c.locked};foreground=${c.foreground};minutes=${c.minutes};'
        'busy=${c.busy};failure=${c.failure?.name}');
  }

  @override
  void dispose() {
    widget.controller.removeListener(_receipt);
    _observer.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: _locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [_observer],
        builder: (context, child) =>
            AppLockGate(controller: widget.controller, child: child!),
        home: Scaffold(
            appBar: AppBar(title: const Text('FiFe App lock test')),
            body: ListView(children: [
              const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Private native fixture')),
              AppLockSettings(controller: widget.controller),
              TextButton(
                  onPressed: () => setState(() => _locale = const Locale('hi')),
                  child: const Text('Hindi')),
              TextButton(
                  onPressed: () => setState(() => _locale = const Locale('en')),
                  child: const Text('English')),
            ])),
      );
}
