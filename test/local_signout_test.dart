import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  const purchases = MethodChannel('purchases_flutter');
  setUp(() async {
    fixture = await SyncFixture.create();
    await ModelSetting.set(AppString.localTesting.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, (_) async => true);
  });
  tearDown(() async {
    await fixture.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, null);
  });

  group('local account sign-out', () {
    test('removes only this device and retains the remote vault', () async {
      final original = await fixture.text('original.txt', 'external bytes');
      final owned = await File('${fixture.directory.path}/FiFe/download.txt')
          .create(recursive: true);
      await owned.writeAsString('downloaded bytes');
      final db = await fixture.db;
      await db.insert(
          'item_tasks', {'id': 'pending', 'task': ItemTask.upload.value});
      final devices = {
        'samsung': false,
        'iphone': false,
        'fixture-device-uuid': true
      };
      var vaultExists = true;
      final mutations = <String>[];
      await http.runWithClient(() async {
        expect(await SyncUtils.signout(), isTrue);
      },
          () => MockClient((request) async {
                if (request.method == 'HEAD') return http.Response('', 200);
                mutations.add(request.url.path);
                if (request.url.path.endsWith('/local-test/reset')) {
                  vaultExists = false;
                  devices.clear();
                } else if (request.url.path.endsWith('/signout')) {
                  final body = jsonDecode(request.body) as Map;
                  devices.remove(body['device_uuid']);
                } else {
                  fail('Unexpected sign-out request');
                }
                return http.Response('{"success":1}', 200);
              }));
      expect(vaultExists, isTrue,
          reason:
              'Removing the final device must not delete the account keys or files');
      expect(devices, {'samsung': false, 'iphone': false});
      expect(mutations, ['/api/signout']);
      expect(await ModelProfile.get(), isNull);
      expect(fixture.secrets, isEmpty);
      expect(await db.query('item_tasks'), isEmpty);
      expect(await owned.exists(), isFalse);
      expect(await original.readAsString(), 'external bytes');
    });

    test('LAN sign-out does not require a public internet probe', () async {
      var probes = 0;
      await http.runWithClient(() async {
        expect(await SyncUtils.signout(), isTrue);
      },
          () => MockClient((request) async {
                if (request.method == 'HEAD') {
                  probes++;
                  return http.Response('', 503);
                }
                expect(request.url.path, '/api/signout');
                return http.Response('{"success":1}', 200);
              }));
      expect(probes, 0);
      expect(await ModelProfile.get(), isNull);
    });

    for (final status in [0, -1]) {
      test('unconfirmed sign-out $status preserves local data for retry',
          () async {
        final before = Map.of(fixture.secrets);
        final original = await fixture.text('original.txt', 'keep bytes');
        await http.runWithClient(() async {
          expect(await SyncUtils.signout(), isFalse);
        },
            () => MockClient((request) async {
                  if (request.method == 'HEAD') return http.Response('', 200);
                  expect(request.url.path, '/api/signout');
                  return http.Response(jsonEncode({'success': status}), 200);
                }));
        expect(fixture.secrets, before);
        expect(await ModelProfile.get(), isNotNull);
        expect(await original.readAsString(), 'keep bytes');
      });
    }

    test(
        'unregistered onboarding sign-out clears locally without deleting an account',
        () async {
      await ModelSetting.delete(AppString.deviceUuid.string);
      await http.runWithClient(() async {
        expect(await SyncUtils.signout(), isTrue);
      },
          () => MockClient((_) async {
                fail(
                    'An unregistered local sign-in has no remote device to remove');
              }));
      expect(await ModelProfile.get(), isNull);
      expect(fixture.secrets, isEmpty);
    });

    test('retry after a rejected sign-out still removes only this device',
        () async {
      var attempts = 0;
      await http.runWithClient(() async {
        expect(await SyncUtils.signout(), isFalse);
        expect(await ModelProfile.get(), isNotNull);
        expect(await SyncUtils.signout(), isTrue);
      },
          () => MockClient((request) async {
                if (request.method == 'HEAD') return http.Response('', 200);
                expect(request.url.path, '/api/signout');
                return http.Response(
                    jsonEncode({'success': ++attempts == 1 ? 0 : 1}), 200);
              }));
      expect(attempts, 2);
      expect(fixture.secrets, isEmpty);
    });
  }, skip: !AppEnv.localTestingBuild);

  test(
      'simulation sign-out stays local even if a local-testing setting remains',
      () async {
    await ModelSetting.set(AppString.simulateTesting.string, 'yes');
    await http.runWithClient(() async {
      expect(await SyncUtils.signout(), isTrue);
    },
        () => MockClient((_) async {
              fail('Simulation logout must never contact a server');
            }));
    expect(fixture.secrets, isEmpty);
    expect(await ModelProfile.get(), isNull);
  });
}
