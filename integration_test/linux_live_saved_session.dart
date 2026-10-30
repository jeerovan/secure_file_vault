import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:device_info_plus_platform_interface/device_info_plus_platform_interface.dart';
import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Persistent normal launcher for the previously authenticated live fixture.
/// There is no testWidgets teardown to dispose the app during its final metadata
/// push. Native UI drives sync; an external observer checks the completed cycle.
/// Only storage/keyring/device identity are isolated; no app state is seeded.
Future<void> main() async {
  final runtime = Platform.environment['FIFE_LINUX_TEST_ROOT'];
  const identity = String.fromEnvironment('FIFE_LIVE_IDENTITY');
  if (!Platform.isLinux ||
      !const bool.fromEnvironment('FIFE_RUN_LINUX_LIVE_CLOUD') ||
      runtime == null ||
      !RegExp(r'runtime-[a-f0-9]{16}$').hasMatch(runtime) ||
      !RegExp(r'^linux-live-[a-f0-9]{10}$').hasMatch(identity) ||
      !File(path.join(runtime, 'synthetic-fixture.marker')).existsSync() ||
      Platform.environment['XDG_DATA_HOME'] != path.join(runtime, 'xdg') ||
      AppEnv.localTestingBuild ||
      Uri.parse(AppEnv.effectiveApiBaseUrl).scheme != 'https' ||
      Uri.parse(AppEnv.neonAuthUrl).scheme != 'https') {
    throw StateError('Explicit isolated production-network fixture required');
  }
  final plugin = File(path.join(path.dirname(Platform.resolvedExecutable),
      'lib', 'libflutter_secure_storage_linux_plugin.so'));
  if (!latin1
      .decode(await plugin.readAsBytes())
      .contains('com.jeerovan.fife.LiveCloudTest\u0000')) {
    throw StateError('Isolated native keyring identity required');
  }
  WidgetsFlutterBinding.ensureInitialized();
  WidgetsBinding.instance.ensureSemantics();
  PathProviderPlatform.instance = _SavedPaths(runtime);
  DeviceInfoPlatform.instance =
      _SavedIdentity(await DeviceInfoPlugin().linuxInfo, identity);
  await application.main();
  if ((await ModelProfile.get())?.email?.toLowerCase() !=
          'tojeevansingh@gmail.com' ||
      localTesting() ||
      simulateTesting()) {
    throw StateError('Authorized real saved session required');
  }
  await File(path.join(runtime, 'persistent-launch.json')).writeAsString(
      jsonEncode({
        'pid': pid,
        'normalMainInvoked': true,
        'savedAuthorizedAccount': true,
        'productionNetworking': true,
        'productStateSeeded': false,
      }),
      flush: true);
}

class _SavedPaths extends PathProviderPlatform {
  _SavedPaths(this.root);
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

class _SavedIdentity extends DeviceInfoPlatform {
  _SavedIdentity(LinuxDeviceInfo native, String identity)
      : info = LinuxDeviceInfo(
          name: 'FiFe Linux Live $identity',
          version: native.version,
          id: native.id,
          idLike: native.idLike,
          versionCodename: native.versionCodename,
          versionId: native.versionId,
          prettyName: native.prettyName,
          buildId: native.buildId,
          variant: native.variant,
          variantId: native.variantId,
          machineId: 'fife-live-$identity',
        );
  final LinuxDeviceInfo info;
  @override
  Future<BaseDeviceInfo> deviceInfo() async => info;
}
