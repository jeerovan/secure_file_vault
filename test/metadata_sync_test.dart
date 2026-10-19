import 'dart:convert';
import 'dart:typed_data';

import 'package:file_vault_bb/models/model_change.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_state.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/services/service_sync_budget.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  late CryptoUtils crypto;
  late Uint8List masterKey;
  setUp(() async {
    fixture = await SyncFixture.create();
    crypto = CryptoUtils(fixture.sodium);
    masterKey = base64Decode(fixture.secrets[AppString.masterKey.string]!);
  });
  tearDown(() async => fixture.dispose());

  http.Response response(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200);

  Future<T> withApi<T>(Future<T> Function() action,
      Future<http.Response> Function(http.Request) handler) async {
    AppHttpClients.closeAll();
    try {
      return await http.runWithClient(action, () => MockClient(handler));
    } finally {
      AppHttpClients.closeAll();
    }
  }

  Map<String, dynamic> fileChange({
    String id = 'remote-hash',
    int rowId = 1,
    int timestamp = 10,
    int updatedAt = 20,
    int deleted = 0,
  }) =>
      {
        '1': rowId,
        '3': timestamp,
        '6': id,
        '7': 1,
        '8': 1,
        '9': 1,
        '10': 6,
        '11': 7,
        '12': '{}',
        '13': updatedAt,
        '14': deleted,
      };

  Map<String, dynamic> itemChange(Map<String, dynamic> data,
      {int rowId = 1, int timestamp = 10, int updatedAt = 20}) {
    final encrypted = crypto.getEncryptedBytesMap(
        Uint8List.fromList(utf8.encode(jsonEncode(data))), masterKey);
    return {
      '1': rowId,
      '3': timestamp,
      '7': encrypted[AppString.textCipher.string],
      '8': encrypted[AppString.textNonce.string],
      '9': encrypted[AppString.keyCipher.string],
      '10': encrypted[AppString.keyNonce.string],
      '11': updatedAt,
    };
  }

  test('metadata push encrypts private item data and never exports bookmarks',
      () async {
    await fixture.text('private filename.txt', 'contents');
    await fixture.scan();
    // Include a sync-root change, whose local bookmark must be stripped.
    final root = await fixture.root;
    await root.update(['name']);
    final sent = <Map<String, dynamic>>[];
    await withApi(() async {
      expect(await SyncUtils.pushMapChanges(), isTrue);
      expect(await ModelChange.all(), isEmpty);
    }, (request) async {
      expect(request.method, 'POST');
      expect(request.url.path, endsWith('/sync'));
      expect(request.body, isNot(contains('private filename.txt')));
      expect(request.body, isNot(contains('fixture-bookmark')));
      final groups = jsonDecode(request.body)['table_maps'] as List;
      for (final group in groups) {
        if (group['table'] != 'items') continue;
        for (final change in group['changes']) {
          final plain = crypto.getDecryptedBytesFromMap(
              Map<String, dynamic>.from(change), masterKey)!;
          sent.add(jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
        }
      }
      return response({'success': 1});
    });
    expect(sent.map((m) => m['name']), contains('private filename.txt'));
    expect(sent.singleWhere((m) => m['id'] == root.id)['bookmark'], '');
  });

  test('failed metadata push retains all durable changes for a later retry',
      () async {
    await fixture.text('pending.txt', 'never lose this change');
    await fixture.scan();
    final before = await fixture.snapshot();
    await withApi(() async {
      expect(await SyncUtils.pushMapChanges(), isFalse);
    }, (_) async => http.Response('offline', 503));
    expect(await fixture.snapshot(), before);
    await withApi(() async {
      expect(await SyncUtils.pushMapChanges(), isTrue);
    }, (_) async => response({'success': 1}));
    expect(await ModelChange.all(), isEmpty);
  });

  test(
      'an edit committed during push remains queued until its own acknowledgment',
      () async {
    await fixture.text('edit.txt', 'one');
    await fixture.scan();
    var calls = 0;
    await withApi(() async {
      expect(await SyncUtils.pushMapChanges(), isFalse);
    }, (request) async {
      calls++;
      if (calls == 1) {
        final item = await fixture.item('edit.txt');
        final change = (await ModelChange.get('items|${item.id}'))!;
        final data = Map<String, dynamic>.of(change.data)
          ..['name'] = 'new name.txt';
        await (await fixture.db).update(
            'changes',
            {
              'data': jsonEncode(data),
              'updated_at': change.updatedAt + 1,
            },
            where: 'id = ?',
            whereArgs: [change.id]);
        return response({'success': 1});
      }
      return http.Response('lost connection', 503);
    });
    final changes = await ModelChange.all();
    expect(changes.length, 1);
    expect(changes.single.data['name'], 'new name.txt');
  });

  test(
      'fetch applies encrypted items, file parts and profile with durable cursors',
      () async {
    var calls = 0;
    await withApi(() async {
      expect(await SyncUtils.fetchMapChanges(), isTrue);
    }, (request) async {
      calls++;
      if (calls > 1) {
        expect(request.url.queryParameters[AppString.lastFileId.string], '1');
        expect(request.url.queryParameters[AppString.lastItemId.string], '2');
        expect(request.url.queryParameters[AppString.lastPartId.string], '3');
        return response({'success': 1, 'data': {}});
      }
      return response({
        'success': 1,
        'data': {
          'files': [fileChange()],
          'items': [
            itemChange({
              'id': 'remote-item',
              'parent_id': SyncFixture.rootId,
              'root_id': SyncFixture.rootId,
              'name': 'remote.txt',
              'file_hash': 'remote-hash',
              'size': 5,
              'updated_at': 20,
              'deleted': 0,
            }, rowId: 2)
          ],
          'parts': [
            {
              '1': 3,
              '3': 10,
              '6': 'remote-hash',
              '7': 1,
              '8': 40,
              '9': 'wrapped-key',
              '10': 'nonce',
              '11': {'sha1': 'checksum'},
              '12': 20,
              '13': 0,
              '14': 1,
            }
          ],
          'profiles': [
            {
              '1': 4,
              '3': 10,
              '4': 'fixture-user',
              '5': 'Updated name',
              '8': 'image-url',
              '9': 123,
            }
          ],
        }
      });
    });
    expect((await ModelItem.get('remote-item'))?.name, 'remote.txt');
    expect((await ModelFile.get('remote-hash'))?.storageId, 7);
    expect((await ModelPart.get('remote-hash_1'))?.data['sha1'], 'checksum');
    expect((await ModelProfile.get())?.username, 'Updated name');
    expect(await ModelState.get(AppString.lastProfileId.string), '4');
    expect(await ModelChange.all(), isEmpty,
        reason: 'Applying server changes cannot echo them back as local edits');
  });

  test('same-timestamp pages advance by row ID and do not skip later rows',
      () async {
    var calls = 0;
    await withApi(() async {
      expect(await SyncUtils.fetchMapChanges(), isTrue);
    }, (request) async {
      final expectedId = calls == 0 ? '0' : calls.toString();
      expect(
          request.url.queryParameters[AppString.lastFileId.string], expectedId);
      calls++;
      return response({
        'success': 1,
        'data': {
          'files': calls <= 2
              ? [fileChange(id: 'hash-$calls', rowId: calls, timestamp: 50)]
              : [],
        }
      });
    });
    expect(await ModelFile.get('hash-1'), isNotNull);
    expect(await ModelFile.get('hash-2'), isNotNull);
    expect(await ModelState.get(AppString.lastFileTS.string), '50');
    expect(await ModelState.get(AppString.lastFileId.string), '2');
  });

  test('malformed encrypted row rolls back its entire page and every cursor',
      () async {
    final before = await fixture.snapshot();
    await withApi(() async {
      expect(await SyncUtils.fetchMapChanges(), isFalse);
    },
        (_) async => response({
              'success': 1,
              'data': {
                'files': [fileChange()],
                'items': [
                  {
                    '1': 2,
                    '3': 10,
                    '7': 'invalid base64',
                    '8': '',
                    '9': '',
                    '10': '',
                    '11': 20
                  }
                ],
              }
            }));
    expect(await fixture.snapshot(), before);
    expect(await ModelState.get(AppString.lastFileId.string, defaultValue: '0'),
        '0');
    expect(await ModelFile.get('remote-hash'), isNull);
  });

  test(
      'older remote updates and tombstones cannot overwrite a newer local file',
      () async {
    await (await fixture.db).insert('files', {
      'id': 'remote-hash',
      'parts': 3,
      'uploaded_at': 50,
      'updated_at': 100,
    });
    var calls = 0;
    await withApi(() async {
      expect(await SyncUtils.fetchMapChanges(), isTrue);
    },
        (_) async => response({
              'success': 1,
              'data': {
                'files': calls++ == 0
                    ? [
                        fileChange(updatedAt: 20),
                        fileChange(rowId: 2, updatedAt: 21, deleted: 1)
                      ]
                    : [],
              }
            }));
    final file = (await ModelFile.get('remote-hash'))!;
    expect(file.parts, 3);
    expect(file.uploadedAt, 50);
    expect(file.updatedAt, 100);
  });

  test('page limit preserves committed progress and resumes from its cursor',
      () async {
    final budget = SyncBudget(
        deadline: DateTime.now().add(const Duration(minutes: 1)),
        maxMetadataPages: 1);
    addTearDown(budget.dispose);
    await withApi(() async {
      expect(await budget.run(SyncUtils.fetchMapChanges), isFalse);
    },
        (_) async => response({
              'success': 1,
              'data': {
                'files': [fileChange()]
              }
            }));
    expect(await ModelFile.get('remote-hash'), isNotNull);
    expect(await ModelState.get(AppString.lastFileId.string), '1');
    await withApi(() async {
      expect(await SyncUtils.fetchMapChanges(), isTrue);
    }, (request) async {
      expect(request.url.queryParameters[AppString.lastFileId.string], '1');
      return response({'success': 1, 'data': {}});
    });
  });

  test(
      'remote deletion waits for downloads and never deletes an external source',
      () async {
    final source =
        await fixture.text('external.txt', 'owner source must survive');
    await fixture.scan();
    final item = await fixture.item('external.txt');
    final clientTimestamp = item.updatedAt + 1;
    final deletion =
        itemChange({...item.toMap(), 'deleted': 1}, updatedAt: clientTimestamp);
    await ModelItemTask.addTask(item.id, ItemTask.download.value);
    final lease = (await ExclusiveOperationCoordinator.tryAcquire(
        TaskManager.downloadOperationId(item.id)))!;
    var calls = 0;
    Future<http.Response> serve(http.Request _) async => response({
          'success': 1,
          'data': {
            'items': calls++ == 0 ? [deletion] : []
          },
        });
    try {
      await withApi(() async {
        expect(await SyncUtils.fetchMapChanges(), isFalse);
      }, serve);
      expect(await ModelItem.get(item.id), isNotNull);
      expect(await ModelItemTask.get(item.id), isNotNull);
    } finally {
      await lease.release();
    }
    calls = 0;
    await withApi(() async {
      expect(await SyncUtils.fetchMapChanges(), isTrue);
    }, serve);
    expect(await ModelItem.get(item.id), isNull);
    expect(await ModelItemTask.get(item.id), isNull);
    expect(await source.readAsString(), 'owner source must survive');
  });

  test('failed fetch can retry without losing pending local modifications',
      () async {
    await fixture.text('pending.txt', 'offline edit');
    await fixture.scan();
    final before = await fixture.snapshot();
    await withApi(() async {
      expect(await SyncUtils.fetchMapChanges(), isFalse);
    }, (_) async => http.Response('unavailable', 503));
    expect(await fixture.snapshot(), before);
  });
}
