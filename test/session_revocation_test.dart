import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/common.dart' as common;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const purchases = MethodChannel('purchases_flutter');
  late SyncFixture fixture;

  setUp(() async {
    fixture = await SyncFixture.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, (call) async => true);
  });

  tearDown(() async {
    await fixture.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, null);
  });

  test('registered device clears its local account when server user is gone',
      () async {
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    final source = await fixture.text('original.txt', 'external original');

    await http.runWithClient(() async {
      expect(await SyncUtils.checkDeviceStatus(), isTrue);
    },
        () => MockClient((request) async {
              expect(request.method, 'GET');
              expect(request.url.path, endsWith('/devices'));
              return http.Response('{"success":0,"message":1}', 200);
            }));

    expect(await ModelProfile.get(), isNull);
    expect(fixture.secrets, isEmpty);
    expect(await source.readAsString(), 'external original');
  });

  test('billing client failure cannot prevent local account cleanup', () async {
    final source = await fixture.text('original.txt', 'external original');
    final managed = await File('${fixture.directory.path}/FiFe/local-copy.txt')
        .create(recursive: true);
    await managed.writeAsString('app-owned plaintext');
    await ModelSetting.set(AppString.locale.string, 'de');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, (_) async {
      throw PlatformException(code: 'BILLING_UNAVAILABLE');
    });

    expect(await SyncUtils.resetDevice(), isTrue);
    expect(fixture.secrets, isEmpty);
    expect(await ModelProfile.get(), isNull);
    expect(await managed.exists(), isFalse);
    expect(await source.readAsString(), 'external original');
    expect(await ModelSetting.getRaw(AppString.locale.string), 'de');
    expect(await ModelSetting.getRaw(AppString.signedIn.string), isEmpty);
  });

  test('cleanup never queries an unconfigured native billing session',
      () async {
    final supported = common.revenueCatSupported;
    common.revenueCatSupported = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, (call) async {
      calls.add(call.method);
      if (call.method == 'isConfigured') return false;
      // On Apple platforms this access can terminate the native process.
      throw PlatformException(code: 'UNSAFE_UNCONFIGURED_BILLING_ACCESS');
    });
    try {
      expect(await SyncUtils.resetDevice(), isTrue);
      expect(await ModelProfile.get(), isNull);
      expect(fixture.secrets, isEmpty);
      expect(calls, ['isConfigured']);
    } finally {
      common.revenueCatSupported = supported;
    }
  });

  test('configured billing logout failure still clears private data', () async {
    final supported = common.revenueCatSupported;
    common.revenueCatSupported = true;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchases, (call) async {
      calls.add(call.method);
      if (call.method == 'isConfigured') return true;
      if (call.method == 'isAnonymous') return false;
      throw PlatformException(code: 'BILLING_LOGOUT_UNAVAILABLE');
    });
    try {
      expect(await SyncUtils.resetDevice(), isTrue);
      expect(await ModelProfile.get(), isNull);
      expect(fixture.secrets, isEmpty);
      expect(calls, ['isConfigured', 'isAnonymous', 'logOut']);
    } finally {
      common.revenueCatSupported = supported;
    }
  });

  for (final response in [
    {
      'success': 1,
      'data': {'active': 1}
    },
    {'success': -1, 'message': 'Network Error'},
    {'success': 0, 'message': 'Server Error'},
    {'success': 0, 'message': '14'},
    {'success': 1, 'data': 'malformed'},
  ]) {
    test('non-revocation response preserves the local vault: $response',
        () async {
      final before = Map.of(fixture.secrets);
      await http.runWithClient(() async {
        expect(await SyncUtils.checkDeviceStatus(), isFalse);
      },
          () => MockClient(
              (_) async => http.Response(jsonEncode(response), 200)));
      expect(fixture.secrets, before);
      expect((await ModelProfile.get())?.id, 'fixture-user');
    });
  }

  test('a new OTP login with no registration is not revoked by NO_USER',
      () async {
    await ModelSetting.delete(AppString.deviceUuid.string);
    final before = Map.of(fixture.secrets);
    await http.runWithClient(() async {
      expect(await SyncUtils.checkDeviceStatus(), isFalse);
    },
        () => MockClient(
            (_) async => http.Response('{"success":0,"message":"1"}', 200)));
    expect(fixture.secrets, before);
  });

  for (final data in [
    null,
    <String, dynamic>{},
    {'active': 0}
  ]) {
    test(
        'missing or inactive registration clears locally without remote logout: $data',
        () async {
      await http.runWithClient(() async {
        expect(await SyncUtils.checkDeviceStatus(), isTrue);
      },
          () => MockClient((request) async {
                expect(request.method, 'GET');
                return http.Response(
                    jsonEncode({'success': 1, 'data': data}), 200);
              }));
      expect(fixture.secrets, isEmpty);
      expect(await ModelProfile.get(), isNull);
    });
  }

  test('cleanup removes only app-owned files and unlinks symbolic links',
      () async {
    final source = await fixture.text('original.txt', 'keep external bytes');
    final owned = Directory('${fixture.directory.path}/FiFe');
    await owned.create();
    await Link('${owned.path}/outside-link').create(fixture.source.path);
    final artifact =
        File('${fixture.directory.path}/${'a' * 43}_1.crypt.ready');
    final partial = File('${artifact.path}.partial');
    final exported = File('${fixture.directory.path}/fife_access_key.txt');
    final unrelated = File('${fixture.directory.path}/other-tool.tmp');
    for (final file in [artifact, partial, exported, unrelated]) {
      await file.writeAsString('fixture');
    }
    expect(await SyncUtils.resetDevice(), isTrue);
    for (final file in [artifact, partial, exported]) {
      expect(await file.exists(), isFalse);
    }
    expect(await unrelated.readAsString(), 'fixture');
    expect(await source.readAsString(), 'keep external bytes');
  });

  test('failed steps do not prevent other deletion and resume after restart',
      () async {
    final marker = File('${fixture.directory.path}/cleanup-state.json');
    var secureAvailable = false;
    var databaseCleared = false;
    var filesCleared = false;
    List<SessionCleanupAction> actions() => [
          SessionCleanupAction('Secure store', () async {
            if (!secureAvailable) {
              throw const FileSystemException('unavailable');
            }
            fixture.secrets.clear();
          }),
          SessionCleanupAction('Database', () async => databaseCleared = true),
          SessionCleanupAction('Files', () async => filesCleared = true),
        ];
    final cleanup = SessionCleanup.test(marker: marker, actions: actions());
    expect(await cleanup.request(), isFalse);
    expect(databaseCleared, isTrue);
    expect(filesCleared, isTrue);
    expect(await cleanup.pending, isTrue);
    secureAvailable = true;
    final restarted = SessionCleanup.test(marker: marker, actions: actions());
    expect(await restarted.resume(), isTrue);
    expect(await restarted.pending, isFalse);
    expect(fixture.secrets, isEmpty);
    expect(await restarted.resume(), isTrue);
  });

  test('stale work cannot write old data after cleanup and a new login',
      () async {
    await SessionCleanup.instance.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    final oldWork = SessionWork.run(() async {
      entered.complete();
      await release.future;
      await (await ModelProfile.fromMap(
              {'id': 'old-account', 'email': 'old@example.test'}))
          .insert();
    });
    final rejected = expectLater(oldWork, throwsA(isA<SessionInvalidated>()));
    await entered.future;
    expect(await SyncUtils.resetDevice(), isTrue);
    await (await ModelProfile.fromMap(
            {'id': 'new-account', 'email': 'new@example.test'}))
        .insert();
    release.complete();
    await rejected;
    expect((await ModelProfile.get())?.id, 'new-account');
  });

  test('a transaction in flight rolls back before cleanup commits', () async {
    await SessionCleanup.instance.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    final oldWork =
        SessionWork.run(() => StorageSqlite.instance.runInTransaction(() async {
              await ModelSetting.set('old_work', 'must roll back');
              entered.complete();
              await release.future;
            }));
    final rejected = expectLater(oldWork, throwsA(isA<SessionInvalidated>()));
    await entered.future;
    final cleanup = SyncUtils.resetDevice();
    for (var i = 0; i < 100 && !await SessionCleanup.instance.pending; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await SessionCleanup.instance.pending, isTrue);
    release.complete();
    await rejected;
    expect(await cleanup, isTrue);
    expect(await ModelSetting.getRaw('old_work'), isEmpty);
  });

  for (final deleting in [false, true]) {
    test(
        'late settings ${deleting ? 'deletion' : 'save'} cannot change a new session cache',
        () async {
      expect(await SessionCleanup.instance.resume(), isTrue);
      final key = AppString.foregroundSyncIntervalMinutes.string;
      if (deleting) await ModelSetting.set(key, '15');
      final observer = await openDatabase((await fixture.db).path,
          readOnly: true, singleInstance: false);
      final entered = Completer<void>(), release = Completer<void>();
      final readRevision = SessionWork.readRevision!;
      SessionWork.readRevision = () async {
        final revision = await readRevision();
        // A separate WAL reader sees this mutation only after SQL commits.
        // Pause cache publication at that boundary, without relying on probe
        // counts or holding a transaction that would prevent cleanup.
        final rows =
            await observer.query('settings', where: 'id = ?', whereArgs: [key]);
        final committed = deleting
            ? rows.isEmpty
            : rows.isNotEmpty && rows.single['value'] == '30';
        if (committed && !entered.isCompleted) {
          entered.complete();
          await release.future;
        }
        return revision;
      };
      final oldMutation =
          (deleting ? ModelSetting.delete(key) : ModelSetting.set(key, '30'))
              .then<Object?>((_) => null, onError: (Object error) => error);
      try {
        await entered.future.timeout(const Duration(seconds: 10));
        expect(await SessionCleanup.instance.request(), isTrue);
        await ModelSetting.set(key, '7');
        release.complete();
        final outcome = await oldMutation;
        expect(await ModelSetting.getRaw(key), '7');
        expect(ModelSetting.foregroundSyncIntervalMinutes, 7);
        expect(outcome, isA<SessionInvalidated>());
        expect(fixture.secrets, isEmpty);
      } finally {
        if (!release.isCompleted) release.complete();
        await oldMutation;
        await observer.close();
      }
    });
  }

  test('a platform key write in flight finishes before cleanup deletes keys',
      () async {
    await SessionCleanup.instance.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SyncFixture.secure, (call) async {
      if (call.method == 'write') {
        entered.complete();
        await release.future;
        fixture.secrets[call.arguments['key']] = call.arguments['value'];
      } else if (call.method == 'deleteAll') {
        fixture.secrets.clear();
      }
      return null;
    });
    final oldWrite = SessionWork.run(
        () => SecureStorage().write(key: 'late_key', value: 'retired-secret'));
    final rejected = expectLater(oldWrite, throwsA(isA<SessionInvalidated>()));
    await entered.future;
    final cleanup = SyncUtils.resetDevice();
    for (var i = 0; i < 100 && !await SessionCleanup.instance.pending; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await SessionCleanup.instance.pending, isTrue);
    release.complete();
    await rejected;
    expect(await cleanup, isTrue);
    expect(fixture.secrets, isEmpty);
  });

  test(
      'an advanced durable revision invalidates cached UI after ordinary reads',
      () async {
    expect(await SessionCleanup.instance.resume(), isTrue);
    await File('${fixture.directory.path}/fife-session-state.json')
        .writeAsString(
            jsonEncode({'revision': 'other-isolate', 'pending': false}));
    // A resumed Explorer may read metadata before the root lifecycle handler.
    await ModelSetting.getRaw('unrelated');
    final events = <EventKey>[];
    final subscription = EventStream().events.listen((event) {
      events.add(event.key);
    });
    try {
      expect(await SessionCleanup.instance.resume(), isTrue);
      expect(
          events,
          containsAllInOrder([
            EventKey.sessionInvalidated,
            EventKey.signout,
          ]));
    } finally {
      await subscription.cancel();
    }
  });

  test('failed marker persistence cannot reopen the account before retry',
      () async {
    final parent = File('${fixture.directory.path}/blocked-parent');
    await parent.writeAsString('not a directory');
    final cleanup = SessionCleanup.test(
      marker: File('${parent.path}/state.json'),
      actions: [
        SessionCleanupAction('Keys', () async => fixture.secrets.clear())
      ],
    );
    expect(await cleanup.request(), isFalse);
    expect(await cleanup.pending, isTrue);
    expect(SessionWork.active, isFalse);
    await parent.delete();
    await Directory(parent.path).create();
    expect(await cleanup.resume(), isTrue);
    expect(await cleanup.pending, isFalse);
    expect(fixture.secrets, isEmpty);
  });

  for (final method in ['GET', 'POST', 'DELETE']) {
    test(
        'explicit revocation on $method cancels the request and clears locally',
        () async {
      final source = await fixture.text('original.txt', 'preserved');
      final api = BackendApi(
        baseUrlOverride: 'https://api.example.test/api',
        signedEmailIdProvider: () async => 'fixture@example.test',
        accessTokenProvider: () async => 'fixture-token',
        httpClient: MockClient((request) async {
          expect(request.headers['device_uuid'], isNotEmpty);
          return http.Response(
              '{"success":0,"message":8,"reason":"device_revoked"}', 200);
        }),
      );
      try {
        final request = switch (method) {
          'POST' => api.post(endpoint: '/sync', jsonBody: {}),
          'DELETE' => api.delete(endpoint: '/storages/modify'),
          _ => api.get(endpoint: '/sync'),
        };
        await expectLater(request, throwsA(isA<SessionInvalidated>()));
        expect(fixture.secrets, isEmpty);
        expect(await ModelProfile.get(), isNull);
        expect(await source.readAsString(), 'preserved');
      } finally {
        api.close();
      }
    });
  }

  test('a competing cleanup cannot replay over a later login', () async {
    final marker = File('${fixture.directory.path}/shared-cleanup.json');
    final entered = Completer<void>();
    final release = Completer<void>();
    var duplicateDeletions = 0;
    final first = SessionCleanup.test(marker: marker, actions: [
      SessionCleanupAction('First cleanup', () async {
        fixture.secrets.clear();
        await StorageSqlite.instance.clearDb();
        entered.complete();
        await release.future;
      }),
    ]);
    final second = SessionCleanup.test(marker: marker, actions: [
      SessionCleanupAction('Competing cleanup', () async {
        duplicateDeletions++;
        await StorageSqlite.instance.clearDb();
      }),
    ]);
    // Independent coordinators share the on-disk locks, like app/service
    // isolates. Maintenance here avoids sharing their in-memory work guards.
    await SessionWork.maintain(() async {
      final firstRequest = first.request();
      await entered.future;
      final secondRequest = second.request();
      // The competing lock acquisition may time out; it must remain retryable.
      await secondRequest;
      release.complete();
      expect(await firstRequest, isTrue);
    });
    expect(await first.resume(), isTrue);
    await (await ModelProfile.fromMap(
            {'id': 'new-account', 'email': 'new@example.test'}))
        .insert();
    expect(await second.resume(), isTrue);
    expect(duplicateDeletions, 0);
    expect((await ModelProfile.get())?.id, 'new-account');
  });

  test('simultaneous independent coordinators perform one cleanup', () async {
    final marker = File('${fixture.directory.path}/simultaneous-cleanup.json');
    var deletions = 0;
    SessionCleanup coordinator() =>
        SessionCleanup.test(marker: marker, actions: [
          SessionCleanupAction('Account data', () async {
            deletions++;
            await StorageSqlite.instance.clearDb();
          }),
        ]);
    final first = coordinator();
    final second = coordinator();
    await SessionWork.maintain(() async {
      await Future.wait([first.request(), second.request()]);
      expect(await first.resume(), isTrue);
      expect(await second.resume(), isTrue);
    });
    expect(deletions, 1);
    expect(await ModelProfile.get(), isNull);
  });

  test('a delayed metadata page cannot restore retired rows or cursors',
      () async {
    await SessionCleanup.instance.initialize();
    final entered = Completer<void>();
    final release = Completer<void>();
    final database = await fixture.db;
    final delayed = SessionWork.run(() async {
      entered.complete();
      await release.future;
      await StorageSqlite.applySyncPageInDatabase(database, [
        const SyncPageMutation.upsertIfNewer(
            table: 'items',
            id: 'retired-item',
            row: {'id': 'retired-item', 'name': 'private', 'updated_at': 10},
            remoteUpdatedAt: 10),
      ], {
        'retired-cursor': 10
      });
    });
    await entered.future;
    final rejected = expectLater(delayed, throwsA(isA<SessionInvalidated>()));
    expect(await SyncUtils.resetDevice(), isTrue);
    release.complete();
    await rejected;
    expect(await StorageSqlite.instance.getAll('items'), isEmpty);
    expect(await StorageSqlite.instance.getWithId('states', 'retired-cursor'),
        isEmpty);
  });

  for (final response in [
    {'success': 0, 'message': 1},
    {'success': 0, 'message': 8},
    {'success': 0, 'message': 1, 'reason': 'device_revoked'},
    {'success': 1, 'message': 8, 'reason': 'device_revoked'},
  ]) {
    test(
        'a generic or inconsistent data error preserves the account: $response',
        () async {
      final before = Map.of(fixture.secrets);
      final api = BackendApi(
        baseUrlOverride: 'https://api.example.test/api',
        signedEmailIdProvider: () async => 'fixture@example.test',
        accessTokenProvider: () async => 'fixture-token',
        httpClient:
            MockClient((_) async => http.Response(jsonEncode(response), 200)),
      );
      try {
        expect(await api.get(endpoint: '/b2/get-upload-url'), response);
        expect(fixture.secrets, before);
        expect((await ModelProfile.get())?.id, 'fixture-user');
      } finally {
        api.close();
      }
    });
  }
}
