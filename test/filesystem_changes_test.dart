import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/services/service_sync_budget.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() async => fixture.dispose());

  Future<void> scan() async {
    expect((await fixture.scan()).status, ReconciliationStatus.completed);
    expect(await (await fixture.db).query('states'), isEmpty,
        reason: 'Every completed scan releases its operation leases');
  }

  test('discovers nested, empty, binary and Unicode files and queues uploads',
      () async {
    await fixture.text('nested/合同 & résumé.txt', 'version one');
    await fixture.write('empty.txt', []);
    await fixture.write('binary.bin', [0, 255, 1, 128]);
    await fixture.text('.hidden/private.txt', 'excluded');
    await fixture.text('nested/.private.txt', 'excluded');
    await scan();
    expect((await fixture.items()).map((i) => i.name).toSet(),
        {'nested', '合同 & résumé.txt', 'empty.txt', 'binary.bin'});
    final files = (await fixture.items()).where((i) => !i.isFolder).toList();
    for (final file in files) {
      final stored = (await ModelFile.get(file.fileHash!))!;
      expect(stored.parts, file.size == 0 ? 0 : 1);
      expect(stored.uploadedAt, 0);
      expect((await ModelItemTask.get(file.id))?.task, ItemTask.upload.value);
    }
  });

  test('unchanged scans keep identities and do not queue another uploaded copy',
      () async {
    await fixture.text('one.txt', 'already backed up');
    await scan();
    await fixture.markUploaded();
    final before = await fixture.snapshot();
    await scan();
    await scan();
    expect(await fixture.snapshot(), before);
  });

  for (final edit in [
    (
      name: 'same-size edit with preserved mtime',
      before: 'AAAA',
      after: 'BBBB'
    ),
    (name: 'growing file', before: 'small', after: 'a much larger replacement'),
    (name: 'shrinking file', before: 'a large original', after: 'x'),
    (name: 'empty to nonempty', before: '', after: 'created contents'),
    (name: 'nonempty to empty', before: 'remove contents', after: ''),
  ]) {
    test('${edit.name} keeps item identity and queues the new content hash',
        () async {
      final source = await fixture.text('edit.txt', edit.before);
      await scan();
      final original = await fixture.item('edit.txt');
      await fixture.markUploaded();
      final modified = (await source.stat()).modified;
      await source.writeAsString(edit.after, flush: true);
      await source.setLastModified(modified);
      await scan();
      final current = await fixture.item('edit.txt');
      expect(current.id, original.id);
      expect(current.fileHash, isNot(original.fileHash));
      expect(current.size, await source.length());
      expect((await ModelFile.get(original.fileHash!))?.itemCount, 0);
      expect((await ModelFile.get(original.fileHash!))?.uploadedAt, 1);
      expect((await ModelFile.get(current.fileHash!))?.uploadedAt, 0);
      final task = (await ModelItemTask.get(current.id))!;
      expect(task.state, TransferTaskState.pending);
      expect(task.task, ItemTask.upload.value);
      await scan();
      expect((await (await fixture.db).query('item_tasks')).length, 1);
    });
  }

  test('editor atomic replacement is an edit of the same path and identity',
      () async {
    final file = await fixture.text('document.txt', 'old document');
    await scan();
    final original = await fixture.item('document.txt');
    await fixture.markUploaded();
    final temporary = await fixture.text('.editor-save', 'new document');
    await temporary.rename(file.path);
    await scan();
    final current = await fixture.item('document.txt');
    expect(current.id, original.id);
    expect(current.fileHash, isNot(original.fileHash));
    expect((await fixture.items()).length, 1);
    expect(await ModelItemTask.get(current.id), isNotNull);
  });

  test('editing one duplicate preserves the other and both content counts',
      () async {
    await fixture.text('a.txt', 'shared content');
    await fixture.text('b.txt', 'shared content');
    await scan();
    final a = await fixture.item('a.txt');
    final b = await fixture.item('b.txt');
    expect(a.fileHash, b.fileHash);
    await fixture.markUploaded();
    await fixture.text('a.txt', 'new independent content');
    await scan();
    expect((await fixture.item('b.txt')).fileHash, b.fileHash);
    expect((await ModelFile.get(b.fileHash!))?.itemCount, 1);
    expect(
        (await ModelFile.get((await fixture.item('a.txt')).fileHash!))
            ?.itemCount,
        1);
    expect(await ModelItemTask.get(a.id), isNotNull);
    expect(await ModelItemTask.get(b.id), isNull);
  });

  test('reverting to an already uploaded version reuses the stored content',
      () async {
    await fixture.text('edit.txt', 'original');
    await scan();
    final original = await fixture.item('edit.txt');
    await fixture.markUploaded();
    await fixture.text('edit.txt', 'replacement');
    await scan();
    await fixture.markUploaded();
    await fixture.text('edit.txt', 'original');
    await scan();
    final current = await fixture.item('edit.txt');
    expect(current.id, original.id);
    expect(current.fileHash, original.fileHash);
    expect(await ModelItemTask.get(current.id), isNull);
    expect((await ModelFile.get(original.fileHash!))?.itemCount, 1);
  });

  test('new edits unblock a source-change failure without consuming retries',
      () async {
    await fixture.text('edit.txt', 'original');
    await scan();
    final original = await fixture.item('edit.txt');
    final task = (await ModelItemTask.get(original.id))!;
    await task.markBlocked('upload_source_changed');
    await fixture.text('edit.txt', 'stable replacement');
    await scan();
    final current = (await ModelItemTask.get(original.id))!;
    expect(current.state, TransferTaskState.pending);
    expect(current.lastError, isNull);
    expect(current.attemptCount, 0);
  });

  for (final destination in [
    'renamed.txt',
    'ORIGINAL.txt',
    'folder/moved.txt'
  ]) {
    test('rename/move to $destination preserves identity without re-upload',
        () async {
      final source = await fixture.text('original.txt', 'unique contents');
      await scan();
      final original = await fixture.item('original.txt');
      await fixture.markUploaded();
      final target = File('${fixture.source.path}/$destination');
      await target.parent.create(recursive: true);
      await source.rename(target.path);
      await scan();
      final current = await fixture.item(destination);
      expect(current.id, original.id);
      expect(current.fileHash, original.fileHash);
      expect(await ModelItemTask.get(current.id), isNull);
      expect(await ModelItem.getPathForItem(current.id), target.path);
    });
  }

  test('renamed nested folder retains its identity and child identities',
      () async {
    await fixture.text('old/a.txt', 'first');
    await fixture.text('old/nested/b.txt', 'second');
    await scan();
    final folder = await fixture.item('old');
    final child = await fixture.item('old/nested/b.txt');
    await fixture.markUploaded();
    await Directory('${fixture.source.path}/old')
        .rename('${fixture.source.path}/new');
    await scan();
    expect((await fixture.item('new')).id, folder.id);
    expect((await fixture.item('new/nested/b.txt')).id, child.id);
    expect(await (await fixture.db).query('item_tasks'), isEmpty);
  });

  test('copy retains original identity and reuses uploaded content', () async {
    final source = await fixture.text('original.txt', 'shared content');
    await scan();
    final original = await fixture.item('original.txt');
    await fixture.markUploaded();
    await source.copy('${fixture.source.path}/copy.txt');
    await scan();
    final copy = await fixture.item('copy.txt');
    expect(copy.id, isNot(original.id));
    expect((await fixture.item('original.txt')).id, original.id);
    expect(copy.fileHash, original.fileHash);
    expect((await ModelFile.get(original.fileHash!))?.itemCount, 2);
    expect(await (await fixture.db).query('item_tasks'), isEmpty);
  });

  test('ambiguous identical missing files cannot donate an arbitrary identity',
      () async {
    await fixture.text('one.txt', 'identical');
    await fixture.text('two.txt', 'identical');
    await scan();
    final oldIds = (await fixture.items()).map((i) => i.id).toSet();
    await fixture.markUploaded();
    await File('${fixture.source.path}/one.txt').delete();
    await File('${fixture.source.path}/two.txt').delete();
    await fixture.text('three.txt', 'identical');
    await scan();
    final newItem = await fixture.item('three.txt');
    expect(oldIds, isNot(contains(newItem.id)));
    for (final id in oldIds) {
      expect(await ModelItem.get(id), isNotNull,
          reason: 'Existing backed-up copies remain recoverable');
    }
  });

  test('deleted uploaded files remain available as backups', () async {
    final file = await fixture.text('backup.txt', 'recover me');
    await scan();
    final original = await fixture.item('backup.txt');
    await fixture.markUploaded();
    await file.delete();
    await scan();
    expect((await ModelItem.get(original.id))?.fileHash, original.fileHash);
    expect((await ModelFile.get(original.fileHash!))?.uploadedAt, 1);
    expect(await ModelItemTask.get(original.id), isNull);
  });

  test('deleted pending source is removed when its upload validates the path',
      () async {
    final file = await fixture.text('pending.txt', 'never uploaded');
    await scan();
    final original = await fixture.item('pending.txt');
    await file.delete();
    await scan();
    final task = (await ModelItemTask.get(original.id))!;
    await TaskManager().checkInitUpload(task);
    expect(await ModelItem.get(original.id), isNull);
    expect(await ModelItemTask.get(original.id), isNull);
    expect(await ModelFile.get(original.fileHash!), isNull);
  });

  test('missing unqueued and unuploaded metadata is removed', () async {
    final file = await fixture.text('unsaved.txt', 'never uploaded');
    await scan();
    final original = await fixture.item('unsaved.txt');
    await (await fixture.db).delete('item_tasks');
    await file.delete();
    await scan();
    expect(await ModelItem.get(original.id), isNull);
    expect(await ModelFile.get(original.fileHash!), isNull);
  });

  test('deleting a nested tree retains backed-up children and their parents',
      () async {
    await fixture.text('folder/nested/backup.txt', 'recoverable');
    await scan();
    await fixture.markUploaded();
    final before = await fixture.snapshot();
    await Directory('${fixture.source.path}/folder').delete(recursive: true);
    await scan();
    final after = await fixture.snapshot();
    for (final snapshot in [before, after]) {
      snapshot['items'] = snapshot['items']!
          .map((row) => Map<String, Object?>.from(row)..remove('scan_state'))
          .toList();
    }
    expect(after, before);
  });

  test('temporarily unavailable root cannot be interpreted as mass deletion',
      () async {
    await fixture.text('pending.txt', 'keep metadata and task');
    await scan();
    final before = await fixture.snapshot();
    final moved = await fixture.source.rename('${fixture.directory.path}/off');
    expect((await fixture.scan()).status, ReconciliationStatus.unavailable);
    expect(await fixture.snapshot(), before);
    await moved.rename(fixture.source.path);
    await scan();
    expect((await fixture.items()).length, 1);
  });

  test('denied folder access leaves every metadata and queue row unchanged',
      () async {
    await fixture.text('pending.txt', 'keep metadata and task');
    await scan();
    final before = await fixture.snapshot();
    fixture.accessAllowed = false;
    expect((await fixture.scan()).status, ReconciliationStatus.unavailable);
    expect(await fixture.snapshot(), before);
    fixture.accessAllowed = true;
    await scan();
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('bounded partial background scan does not publish or prune any row',
      () async {
    await fixture.text('before.txt', 'pending');
    await scan();
    final before = await fixture.snapshot();
    await fixture.text('new.txt', 'not published by partial scan');
    final budget = SyncBudget(
        deadline: DateTime.now().add(const Duration(minutes: 1)),
        maxScanItems: 1);
    addTearDown(budget.dispose);
    expect(
        (await budget.run(fixture.scan)).status, ReconciliationStatus.partial);
    expect(await fixture.snapshot(), before);
    await scan();
    expect((await fixture.items()).length, 2);
  });

  test('overlapping scans wait for the root lease without duplicate work',
      () async {
    final gate = Completer<void>();
    final entered = Completer<void>();
    fixture.beforeRead = (key) async {
      if (key == AppString.fileHashKey.string && !entered.isCompleted) {
        entered.complete();
        await gate.future;
      }
    };
    await fixture.text('new.txt', 'one upload');
    final first = fixture.scan();
    await entered.future;
    expect((await fixture.scan()).status, ReconciliationStatus.busy);
    gate.complete();
    expect((await first).status, ReconciliationStatus.completed);
    expect((await fixture.items()).length, 1);
    expect((await (await fixture.db).query('item_tasks')).length, 1);
  });

  test('busy metadata lease defers the scan and the next scan recovers',
      () async {
    await fixture.text('new.txt', 'one upload');
    final lease = (await ExclusiveOperationCoordinator.tryAcquire('metadata'))!;
    try {
      expect((await fixture.scan()).status, ReconciliationStatus.busy);
      expect(await fixture.items(), isEmpty);
    } finally {
      await lease.release();
    }
    await scan();
    expect((await fixture.items()).length, 1);
  });

  test('file disappearing between listing and hashing leaves the scan intact',
      () async {
    final file = await fixture.text('race.txt', 'original');
    await scan();
    final before = await fixture.snapshot();
    fixture.beforeRead = (key) async {
      if (key == AppString.fileHashKey.string && await file.exists()) {
        await file.delete();
      }
    };
    expect((await fixture.scan()).status, ReconciliationStatus.partial);
    expect(await fixture.snapshot(), before);
    fixture.beforeRead = null;
    await fixture.text('race.txt', 'original');
    await scan();
  });

  test('database publication failure rolls back discovery and queue changes',
      () async {
    await fixture.text('before.txt', 'original');
    await scan();
    final before = await fixture.snapshot();
    await fixture.text('after.txt', 'new');
    final db = await fixture.db;
    await db.execute("CREATE TRIGGER fail_fixture BEFORE INSERT ON items "
        "WHEN NEW.name = 'after.txt' BEGIN SELECT RAISE(ABORT, 'fixture'); END");
    expect((await fixture.scan()).status, ReconciliationStatus.failed);
    expect(await fixture.snapshot(), before);
    await db.execute('DROP TRIGGER fail_fixture');
    await scan();
    expect((await fixture.items()).length, 2);
  });

  test('symbolic links cannot introduce outside content or directory cycles',
      () async {
    await fixture.text('inside.txt', 'allowed');
    final outside = await File('${fixture.directory.path}/outside.txt')
        .writeAsString('excluded');
    await Link('${fixture.source.path}/outside-link').create(outside.path);
    await Link('${fixture.source.path}/cycle').create(fixture.source.path);
    await scan();
    expect((await fixture.items()).map((i) => i.name), ['inside.txt']);
  }, skip: Platform.isWindows);

  test('streaming hash path discovers and detects changes in a large file',
      () async {
    const length = 10 * 1024 * 1024 + 1;
    final source = await fixture.write('large.bin', List.filled(length, 65));
    await scan();
    final original = await fixture.item('large.bin');
    await fixture.markUploaded();
    final handle = await source.open(mode: FileMode.writeOnlyAppend);
    await handle.setPosition(length ~/ 2);
    await handle.writeByte(66);
    await handle.close();
    await scan();
    final current = await fixture.item('large.bin');
    expect(current.id, original.id);
    expect(current.size, length);
    expect(current.fileHash, isNot(original.fileHash));
    expect(await ModelItemTask.get(current.id), isNotNull);
  });
}
