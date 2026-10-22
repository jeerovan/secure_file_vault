import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'native_test_identity.dart';

Future<void> verifyNativeTestStorageIsolation(String bundle) async {
  if (!Platform.isMacOS) return;
  for (final directory in [
    await getApplicationSupportDirectory(),
    await getApplicationDocumentsDirectory(),
    await getTemporaryDirectory(),
  ]) {
    expect(directory.path.contains(bundle), isTrue,
        reason: 'Destructive fixtures require their own app storage paths');
  }
}

/// Physical Android erasure is opt-in for the owner's designated test handset.
/// Apple fixtures always use a separate bundle/container and keychain.
Future<void> verifyNativeTestInstall() async {
  final bundle = (await PackageInfo.fromPlatform()).packageName;
  expect(isIsolatedNativeTestBundle(bundle), isTrue,
      reason: 'Native cleanup must never run in a production or manual app');
  expect(const bool.fromEnvironment('FIFE_RUN_RECOVERY_NATIVE_TESTS'), isTrue);
  expect(AppEnv.localTestingBuild, isTrue);
  expect(AppEnv.localTestUserId.startsWith('fife-provider-local-'), isTrue);
  if (Platform.isAndroid) {
    final device = await DeviceInfoPlugin().androidInfo;
    if (device.isPhysicalDevice) {
      expect(const bool.fromEnvironment('FIFE_ALLOW_PHYSICAL_ANDROID_TESTS'),
          isTrue,
          reason: 'Physical handset erasure requires an explicit opt-in');
      expect(device.model, 'SM-A305F',
          reason: 'Only the authorized Samsung is a disposable test handset');
    }
    return;
  }
  await verifyNativeTestStorageIsolation(bundle);
}
