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
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/native_http_overrides.dart';

/// Actual Windows runner/main/menu/auth/DPAPI/SQLite with isolated directories
/// and a synthetic saved session. Directory redirection and controlled HTTP do
/// not establish a real account upgrade, Windows known-folder setup or cloud I/O.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = Platform.environment['FIFE_WINDOWS_TEST_ROOT'];
  if (!Platform.isWindows ||
      root == null ||
      !RegExp(r'runtime-[a-f0-9]{16}$').hasMatch(root) ||
      !File(path.join(root, 'synthetic-fixture.marker')).existsSync() ||
      Platform.environment['APPDATA'] != path.join(root, 'roaming') ||
      !AppEnv.localTestingBuild ||
      AppEnv.localTestAuthToken.isEmpty ||
      AppEnv.effectiveApiBaseUrl != 'https://backend.example.test') {
    throw StateError('Explicit isolated Windows fixture required');
  }
  PathProviderPlatform.instance = _FixturePaths(root);
  // Keep Flutter accessibility available to the external Windows UIA driver.
  // This changes only test observation, not lifecycle/menu/auth implementations.
  WidgetsBinding.instance.ensureSemantics();
  for (final name in ['roaming', 'support', 'documents', 'temp']) {
    await Directory(path.join(root, name)).create(recursive: true);
  }
  await StorageSqlite.initialize(ExecutionMode.mainApp);
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
      AppString.deviceUuid: 'windows-menu-fixture',
      AppString.deviceHash: 'windows-menu-device',
    }.entries) {
      await ModelSetting.set(entry.key.string, entry.value);
    }
    for (final key in [
      AppString.masterKey,
      AppString.fileHashKey,
      AppString.accessKey
    ]) {
      await SecureStorage()
          .write(key: key.string, value: base64Encode(List<int>.filled(32, 0)));
    }
    await ModelItem.ensureVaultRoot();
  }
  var requests = 0, responses = 0, starts = 0, stops = 0;
  Future<void> writing = Future.value();
  final proof = File(path.join(root, 'journey-evidence.json'));
  void record() {
    final data = jsonEncode({
      'syntheticDataOnly': true,
      'pid': pid,
      'syncRequests': requests,
      'finishedResponses': responses,
      'operationStarts': starts,
      'operationStops': stops,
    });
    writing = writing.then((_) => proof.writeAsString(data, flush: true));
  }

  EventStream().events.listen((event) {
    if (event.type != EventType.system) return;
    if (event.key == EventKey.running) starts++;
    if (event.key == EventKey.stopped) stops++;
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
      requests++;
      record();
      await Future<void>.delayed(const Duration(seconds: 8));
      responses++;
      record();
      body = {'success': 1, 'data': <String, Object>{}};
    } else {
      throw StateError('Unexpected synthetic endpoint');
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
  // No direct controller creation, native lifecycle callback or sync trigger.
  await application.main();
}

class _FixturePaths extends PathProviderPlatform {
  _FixturePaths(this.root);
  final String root;
  @override
  Future<String> getApplicationSupportPath() async =>
      path.join(root, 'support');
  @override
  Future<String> getApplicationDocumentsPath() async =>
      path.join(root, 'documents');
  @override
  Future<String> getTemporaryPath() async => path.join(root, 'temp');
  @override
  Future<String> getDownloadsPath() async => path.join(root, 'documents');
}
