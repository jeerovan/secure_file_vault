import 'dart:io';

import 'package:file_vault_bb/storage/local_item_access.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async => fixture.dispose());

  Future<String> prepare() async {
    await fixture.text('nested/file.txt', 'original');
    await fixture.scan();
    return (await fixture.item('nested/file.txt')).id;
  }

  Future<void> rejected(String id) async {
    var ran = false;
    await expectLater(
        LocalItemAccess.withAccess(id, (_) async => ran = true),
        throwsA(isA<PlatformException>()
            .having((e) => e.code, 'code', 'FOLDER_UNAVAILABLE')));
    expect(ran, isFalse);
  }

  test('regular selected paths remain accessible through a guarded scope',
      () async {
    final id = await prepare();
    final contents = await LocalItemAccess.withAccess(
        id, (path) => File(path).readAsString());
    expect(contents, 'original');
  });

  for (final dangling in [false, true]) {
    test(
        '${dangling ? 'dangling' : 'existing'} file link cannot escape the root',
        () async {
      final id = await prepare();
      final file = File('${fixture.source.path}/nested/file.txt');
      final outside = File('${fixture.directory.path}/outside.txt');
      if (!dangling) await outside.writeAsString('outside source');
      await file.delete();
      await Link(file.path).create(outside.path);
      await rejected(id);
      expect(await outside.exists(), !dangling);
      if (!dangling) expect(await outside.readAsString(), 'outside source');
      if (Platform.isMacOS || Platform.isIOS) {
        expect(fixture.accessCalls.skip(fixture.accessCalls.length - 2),
            ['startAccessing', 'stopAccessing']);
      }
    }, skip: Platform.isWindows);
  }

  test('replacing the selected root with a link cannot grant outside access',
      () async {
    final id = await prepare();
    await fixture.source.rename('${fixture.directory.path}/original-root');
    final outside =
        await Directory('${fixture.directory.path}/outside').create();
    await Link(fixture.source.path).create(outside.path);
    await rejected(id);
    expect(await outside.list().isEmpty, isTrue);
  }, skip: Platform.isWindows);

  test('lexical traversal and sibling-prefix paths are rejected', () async {
    final id = await prepare();
    for (final name in [
      '../../escape.txt',
      '../../source-sibling/escape.txt'
    ]) {
      await (await fixture.db)
          .update('items', {'name': name}, where: 'id = ?', whereArgs: [id]);
      await rejected(id);
    }
  });

  Future<void> foreignFile({String name = 'remote.txt'}) async {
    final db = await fixture.db;
    await db.insert('items', {'id': 'fife', 'name': 'FiFe', 'is_folder': 1});
    await db.insert('items', {
      'id': 'foreign',
      'name': 'Other device',
      'parent_id': 'fife',
      'is_folder': 1,
    });
    await db.insert('items', {
      'id': 'remote',
      'name': name,
      'parent_id': 'foreign',
      'file_hash': 'remote-hash',
    });
  }

  test('remote copies can be created within the app-managed directory',
      () async {
    await foreignFile();
    await LocalItemAccess.withAccess('remote', (path) async {
      expect(path, startsWith('${fixture.directory.path}/FiFe/'));
      final file = File(path);
      await file.parent.create(recursive: true);
      await file.writeAsString('remote contents');
    });
    expect(fixture.accessCalls, isEmpty);
    expect(
        await File('${fixture.directory.path}/FiFe/Other device/remote.txt')
            .readAsString(),
        'remote contents');
  });

  test('remote metadata cannot traverse outside the app-managed directory',
      () async {
    await foreignFile(name: '../../escape.txt');
    await rejected('remote');
    expect(
        await File('${fixture.directory.path}/escape.txt').exists(), isFalse);
  });

  test('remote copies cannot follow a replaced managed child directory link',
      () async {
    await foreignFile();
    final outside =
        await Directory('${fixture.directory.path}/outside').create();
    await Link('${fixture.directory.path}/FiFe/Other device')
        .create(outside.path);
    await rejected('remote');
    expect(await outside.list().isEmpty, isTrue);
  }, skip: Platform.isWindows);

  test('missing metadata cannot accidentally grant access to a relative path',
      () async => rejected('unknown-item'));
}
