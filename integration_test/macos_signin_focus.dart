import 'dart:io';

import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'support/native_test_identity.dart';

/// Native keyboard check: run in a freshly isolated Apple project with
/// FIFE_RUN_DESKTOP_SIGNIN_FOCUS=true, API_BASE_URL=https://backend.example.test
/// and NEON_AUTH=https://auth.example.test. Use actual keyboard events after
/// clicking the prefilled field; setting its accessibility value bypasses focus.
///
/// The first invocation prepares history and exits; launch it again to test.
/// Seeds only synthetic saved-session history. The normal main, native runner,
/// privacy lifecycle, sign-in UI and saved-state restart remain in charge.
/// No widget tester, focus repair or authentication request is supplied here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bundle = (await PackageInfo.fromPlatform()).packageName;
  if (!Platform.isMacOS ||
      !isIsolatedNativeTestBundle(bundle) ||
      !const bool.fromEnvironment('FIFE_RUN_DESKTOP_SIGNIN_FOCUS') ||
      AppEnv.localTestingBuild ||
      AppEnv.effectiveApiBaseUrl != 'https://backend.example.test' ||
      AppEnv.neonAuthUrl != 'https://auth.example.test') {
    throw StateError('Fresh isolated macOS focus fixture required');
  }
  for (final directory in [
    await getApplicationSupportDirectory(),
    await getApplicationDocumentsDirectory(),
    await getTemporaryDirectory(),
  ]) {
    if (!directory.path.contains(bundle)) {
      throw StateError('Fixture storage is not isolated');
    }
  }
  final support = await getApplicationSupportDirectory();
  final prepared = File('${support.path}/signin-focus-prepared.marker');
  if (await prepared.exists()) {
    // Start in a fresh process: production main owns storage initialization and
    // restoring the durable authentication hold. Reinitializing storage in the
    // process that just expired its session correctly fails its private guard.
    await application.main();
    return;
  }
  await StorageSqlite.initialize(ExecutionMode.mainApp);
  if (!await SessionCleanup.instance.resume()) {
    throw StateError('Fixture cleanup could not resume');
  }
  if (!SessionWork.authenticationRequired) {
    if (await ModelProfile.get() != null) {
      throw StateError('Do not replace an existing test vault');
    }
    await ModelProfile(
      id: 'startup-focus-fixture',
      email: 'retained-focus@example.test',
    ).insert();
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    if (!await SessionCleanup.instance.expiredAuthentication()) {
      throw StateError('Fixture session did not expire');
    }
  }
  await prepared.writeAsString('Synthetic startup focus fixture', flush: true);
  exit(0);
}
