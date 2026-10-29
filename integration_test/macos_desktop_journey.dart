import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'support/native_http_overrides.dart';
import 'support/native_test_identity.dart';

/// Interactive macOS journey: production launcher/menu/window/auth/storage,
/// isolated identity and synthetic authenticated vault. Only HTTP is controlled.
/// Does not establish production cloud transfers or a real Neon sign-in.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This is an interactive launcher, outside flutter_test's test zone.
  final bundle = (await PackageInfo.fromPlatform()).packageName;
  if (!isIsolatedNativeTestBundle(bundle) ||
      !AppEnv.localTestingBuild ||
      !const bool.fromEnvironment('FIFE_RUN_RECOVERY_NATIVE_TESTS')) {
    throw StateError('An isolated test identity is required');
  }
  for (final path in [
    await getApplicationSupportDirectory(),
    await getApplicationDocumentsDirectory(),
    await getTemporaryDirectory()
  ]) {
    if (!path.path.contains(bundle)) throw StateError('Unisolated storage');
  }
  if (!Platform.isMacOS ||
      AppEnv.effectiveApiBaseUrl != 'https://backend.example.test') {
    throw StateError('This fixture requires its isolated macOS configuration');
  }
  await StorageSqlite.initialize(ExecutionMode.mainApp);
  final storage = SecureStorage();
  if (await ModelProfile.get() == null) {
    await (await ModelProfile.fromMap({
      'id': AppEnv.localTestUserId,
      'email': localTestEmailId,
    }))
        .insert();
    for (final entry in {
      AppString.signedIn: 'yes',
      AppString.onboarding: 'yes',
      AppString.localTesting: 'yes',
      AppString.deviceUuid: 'mac-menu-fixture',
      AppString.deviceHash: 'mac-menu-device',
    }.entries) {
      await ModelSetting.set(entry.key.string, entry.value);
    }
    for (final key in [
      AppString.masterKey,
      AppString.fileHashKey,
      AppString.accessKey
    ]) {
      await storage.write(
          key: key.string, value: base64Encode(List<int>.filled(32, 0)));
    }
    await ModelItem.ensureVaultRoot();
  }
  final directory = await getApplicationSupportDirectory();
  final proof = File('${directory.path}/macos-desktop-evidence.json');
  var syncRequests = 0, finishedResponses = 0, started = 0, stopped = 0;
  Future<void> writing = Future.value();
  void record() {
    final snapshot = jsonEncode({
      'syntheticDataOnly': true,
      'pid': pid,
      'syncRequests': syncRequests,
      'finishedResponses': finishedResponses,
      'operationStarts': started,
      'operationStops': stopped,
    });
    writing = writing.then((_) => proof.writeAsString(snapshot, flush: true));
  }

  EventStream().events.listen((event) {
    if (event.type != EventType.system) return;
    if (event.key == EventKey.running) started++;
    if (event.key == EventKey.stopped) stopped++;
    record();
  });
  HttpOverrides.global = NativeFixtureHttpOverrides((request) async {
    if (request.method == 'HEAD') return http.Response('', 200);
    Map<String, Object> body;
    if (request.url.path.endsWith('/devices')) {
      body = {
        'success': 1,
        'data': {'active': 1}
      };
    } else if (request.url.path.endsWith('/sync')) {
      syncRequests++;
      record();
      await Future<void>.delayed(const Duration(seconds: 8));
      finishedResponses++;
      record();
      body = {'success': 1, 'data': <String, Object>{}};
    } else {
      throw StateError('Unexpected fixture endpoint');
    }
    return http.Response(jsonEncode(body), 200,
        headers: {'content-type': 'application/json'});
  }, allowedHosts: const {
    'backend.example.test',
    'one.one.one.one',
    'icanhazip.com',
    'ajax.googleapis.com',
    'captive.apple.com',
  });
  record();
  // No direct menu construction, lifecycle callbacks, or sync invocation.
  await application.main();
}
