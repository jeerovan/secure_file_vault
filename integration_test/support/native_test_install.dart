import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Physical Android erasure is opt-in for the owner's designated test handset.
/// Apple fixtures always use a separate bundle/container and keychain.
Future<void> verifyNativeTestInstall() async {
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
  expect((await PackageInfo.fromPlatform()).packageName,
      'com.jeerovan.fife.localtest.recovery');
  if (Platform.isMacOS) {
    expect((await getApplicationSupportDirectory()).path,
        contains('com.jeerovan.fife.localtest.recovery'));
  }
}
