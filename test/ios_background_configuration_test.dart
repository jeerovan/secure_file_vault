import 'dart:io';

import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS background task identifier is registered consistently', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(
      appDelegate,
      contains(
        'WorkmanagerPlugin.registerPeriodicTask(\n'
        '            withIdentifier: "$iosBackgroundTaskIdentifier"',
      ),
    );
    expect(
      infoPlist,
      contains('<string>$iosBackgroundTaskIdentifier</string>'),
    );
  });

  test('iOS path provider stays on the non-FFI implementation', () {
    final lockfile = File('pubspec.lock').readAsStringSync();
    final packageStart = lockfile.indexOf('  path_provider_foundation:');
    final packageEnd = lockfile.indexOf('\n  path_provider_linux:', packageStart);

    expect(packageStart, isNonNegative);
    expect(packageEnd, greaterThan(packageStart));
    expect(lockfile.substring(packageStart, packageEnd),
        contains('version: "2.5.1"'));
  });
}
