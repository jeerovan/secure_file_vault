import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  testWidgets(
      'disconnected subfolder Archive confirms, cancels and restores through Trash',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      final db = await StorageSqlite.instance.database;
      await db.insert('items', {
        'id': 'subfolder',
        'parent_id': 'folder',
        'root_id': 'folder',
        'name': 'archive-me',
        'is_folder': 1,
        'archived_at': 0
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel('com.jeerovan.fife/channel_storage'),
              (_) async => null);
      await fixture.mount(() async {});
      await tester.tap(find.text('nested'));
      final row = find.byKey(const ValueKey('subfolder'));
      await fixture.waitFor(row);
      await fixture.longPress(row);
      await fixture.waitFor(find.byTooltip('Archive backup'));
      expect(find.byTooltip('Reconnect'), findsNothing);
      expect(find.byTooltip('Download'), findsOneWidget);
      await tester.tap(find.byTooltip('Archive backup'));
      await fixture.waitFor(find.byType(AlertDialog));
      expect(find.textContaining('Original files and other folders are kept.'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await fixture.pump();
      expect((await ModelItem.get('subfolder'))!.archivedAt, 0);
      await fixture.waitFor(find.byTooltip('Archive backup'));
      await tester.tap(find.byTooltip('Archive backup'));
      await fixture.waitFor(find.byType(AlertDialog));
      await tester.tap(find.widgetWithText(FilledButton, 'Archive backup'));
      for (var i = 0;
          i < 60 && (await ModelItem.get('subfolder'))!.archivedAt == 0;
          i++) {
        await fixture.pump();
      }
      expect((await ModelItem.get('subfolder'))!.archivedAt, greaterThan(0));
      await fixture.waitFor(find.byType(PopupMenuButton<int>));
      await tester.tap(find.byType(PopupMenuButton<int>));
      await fixture.waitFor(find.text('Trash'));
      await fixture.pumpMenu();
      await tester.tap(find.text('Trash'));
      await fixture.waitFor(find.text('archive-me'));
      await fixture.longPress(find.text('archive-me'));
      final strings =
          AppLocalizations.of(tester.element(find.text('archive-me')))!;
      await fixture.waitFor(find.byTooltip(strings.recover));
      await tester.tap(find.byTooltip(strings.recover));
      for (var i = 0;
          i < 60 && (await ModelItem.get('subfolder'))!.archivedAt != 0;
          i++) {
        await fixture.pump();
      }
      expect((await ModelItem.get('subfolder'))!.archivedAt, 0);
      expect((await ModelItem.get('folder'))!.archivedAt, 0);
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('trashed but readable root warns on resume and fresh Explorer',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      var resolved =
          await Directory('${fixture.directory.path}/selected').create();
      await File('${resolved.path}/source.txt').writeAsString('keep source');
      var activeLeases = 0;
      var pickerCalls = 0;
      const channel = MethodChannel('com.jeerovan.fife/channel_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'startAccessing':
            activeLeases++;
            return resolved.path;
          case 'stopAccessing':
            activeLeases--;
            return true;
          case 'pickDirectory':
            pickerCalls++;
            return null;
          default:
            throw StateError('Unexpected storage operation');
        }
      });
      // Compare persisted rows; this fixture has null timestamps, for which
      // ModelItem.fromMap supplies a fresh presentation-time default.
      final db = await StorageSqlite.instance.database;
      final row = find.byKey(const ValueKey('folder'));
      final warning = find.descendant(
          of: row, matching: find.byIcon(LucideIcons.alertCircle));
      await fixture.mount(() async {});
      await fixture.pump();
      expect(warning, findsNothing);
      // Let normal Explorer initialization create its app root before taking
      // the baseline for the deletion/recovery transition under test.
      final before = await db.query('items', orderBy: 'id');

      // Unlike permanent deletion, Files leaves a readable directory whose
      // bookmark follows the move. Only the native resolution is substituted.
      await Directory('${fixture.directory.path}/.Trash').create();
      resolved = await resolved.rename('${fixture.directory.path}/.Trash/root');
      expect(await resolved.exists(), isTrue);
      fixture.resumeRepeatedly();
      await fixture.waitFor(warning);
      await fixture.longPress(row);
      await fixture.waitFor(find.byTooltip('Reconnect'));
      await tester.tap(find.byTooltip('Reconnect'));
      for (var i = 0; i < 30 && pickerCalls == 0; i++) {
        await fixture.pump();
      }
      expect(pickerCalls, 1);
      expect(warning, findsOneWidget);
      expect(await db.query('items', orderBy: 'id'), before);
      expect(fixture.scans, 1, reason: 'Resume must not start another sync');

      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.mount(() async {});
      await fixture.waitFor(warning);
      expect(activeLeases, 0);
      expect(await File('${resolved.path}/source.txt').readAsString(),
          'keep source');

      resolved = await resolved.rename('${fixture.directory.path}/restored');
      fixture.resumeRepeatedly();
      for (var i = 0; i < 30 && warning.evaluate().isNotEmpty; i++) {
        await fixture.pump();
      }
      expect(warning, findsNothing);
      expect(activeLeases, 0);
      expect(await db.query('items', orderBy: 'id'), before);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets(
      'resume refreshes reconnect warning without changing the bookmark',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      var denied = false;
      var pickerCalls = 0;
      var activeLeases = 0;
      const storage = MethodChannel('com.jeerovan.fife/channel_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storage, (call) async {
        switch (call.method) {
          case 'startAccessing':
            if (denied) throw PlatformException(code: 'ACCESS_DENIED');
            activeLeases++;
            return fixture.directory.path;
          case 'stopAccessing':
            activeLeases--;
            return true;
          case 'pickDirectory':
            pickerCalls++;
            return null;
          default:
            throw StateError('Unexpected storage operation');
        }
      });
      final row = find.byKey(const ValueKey('folder'));
      final warning = find.descendant(
          of: row, matching: find.byIcon(LucideIcons.alertCircle));
      await fixture.mount(() async {});
      await fixture.pump();
      expect(warning, findsNothing);
      denied = true;
      fixture.resumeRepeatedly();
      await fixture.waitFor(warning);
      // Long press selects; Reconnect is an explicit toolbar action.
      await fixture.longPress(row);
      await fixture.waitFor(find.byTooltip('Reconnect'));
      await tester.tap(find.byTooltip('Reconnect'));
      for (var i = 0; i < 30 && pickerCalls == 0; i++) {
        await fixture.pump();
      }
      expect(pickerCalls, 1);
      expect(warning, findsOneWidget);
      expect((await ModelItem.get('folder'))!.bookmark, 'fixture-bookmark');
      expect((await ModelItem.get('folder'))!.archivedAt, 0);
      denied = false;
      fixture.resumeRepeatedly();
      for (var i = 0; i < 30 && warning.evaluate().isNotEmpty; i++) {
        await fixture.pump();
      }
      expect(warning, findsNothing);
      expect(activeLeases, 0);
      expect(fixture.scans, 1, reason: 'Resume must not start another sync');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('warning folder tap browses saved contents without a picker',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      var pickerCalls = 0;
      const storage = MethodChannel('com.jeerovan.fife/channel_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storage, (call) async {
        if (call.method == 'pickDirectory') {
          pickerCalls++;
          return null;
        }
        throw PlatformException(code: 'ACCESS_DENIED');
      });
      await fixture.mount(() async {});
      final row = find.byKey(const ValueKey('folder'));
      await fixture.waitFor(find.byIcon(LucideIcons.alertCircle));
      final db = await StorageSqlite.instance.database;
      final before = await db.query('items', orderBy: 'id');
      await tester.tap(row);
      await fixture.waitFor(find.byKey(const ValueKey('file')));
      expect(find.text('hello.txt'), findsOneWidget);
      expect(pickerCalls, 0);
      expect(fixture.file.isMultiSelectNotifier.value, isFalse);
      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await fixture.waitFor(row);
      await fixture.waitFor(find.byIcon(LucideIcons.alertCircle));
      expect(await db.query('items', orderBy: 'id'), before);
      expect(pickerCalls, 0);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets(
      'selected Reconnect is single flight and retains selection on failure or Cancel',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      var pickerCalls = 0;
      final picker = Completer<dynamic>();
      const storage = MethodChannel('com.jeerovan.fife/channel_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storage, (call) async {
        if (call.method == 'startAccessing') {
          throw PlatformException(code: 'ACCESS_DENIED');
        }
        if (call.method == 'pickDirectory') {
          pickerCalls++;
          return pickerCalls == 1 ? picker.future : null;
        }
        return null;
      });
      await fixture.mount(() async {});
      final row = find.byKey(const ValueKey('folder'));
      await fixture.longPress(row);
      await fixture.waitFor(find.byTooltip('Reconnect'));
      await tester.tap(find.byTooltip('Reconnect'));
      for (var i = 0; i < 30 && pickerCalls == 0; i++) {
        await fixture.pump();
      }
      expect(pickerCalls, 1);
      await fixture.longPress(row);
      await fixture.pump();
      expect(pickerCalls, 1);
      expect(
          tester.widget<FileListItem>(row).isMultiSelectNotifier.value, isTrue);
      picker.completeError(PlatformException(code: 'PICKER_BUSY'));
      final strings = AppLocalizations.of(tester.element(row))!;
      await fixture.waitFor(find.text(strings.pleaseTryAgain));
      // The transient snackbar overlays this fixture's bottom toolbar.
      for (var i = 0;
          i < 100 && find.byType(SnackBar).evaluate().isNotEmpty;
          i++) {
        await fixture.pump();
      }
      expect(find.byType(SnackBar), findsNothing);
      await fixture.waitFor(find.byTooltip('Reconnect'));
      await tester.tap(find.byTooltip('Reconnect'));
      for (var i = 0; i < 30 && pickerCalls != 2; i++) {
        await fixture.pump();
      }
      expect(pickerCalls, 2);
      expect(
          tester.widget<FileListItem>(row).isMultiSelectNotifier.value, isTrue);
      expect((await ModelItem.get('folder'))!.bookmark, 'fixture-bookmark');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('accessible folder long press keeps ordinary selection behavior',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      await fixture.mount(() async {});
      final row = find.byKey(const ValueKey('folder'));
      await fixture.longPress(row);
      for (var i = 0;
          i < 30 &&
              !tester.widget<FileListItem>(row).isMultiSelectNotifier.value;
          i++) {
        await fixture.pump();
      }
      final tile = tester.widget<FileListItem>(row);
      expect(tile.isMultiSelectNotifier.value, isTrue);
      expect(tile.selectedItemsNotifier.value.single.id, 'folder');
      await tester.tap(row);
      await fixture.pump();
      expect(tile.isMultiSelectNotifier.value, isFalse);
      expect(tile.selectedItemsNotifier.value, isEmpty);
    });
  });

  testWidgets('successful selected Reconnect refreshes the same folder list',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      final replacement =
          await Directory('${fixture.directory.path}/replacement').create();
      await File('${replacement.path}/hello.txt').writeAsString('fixture');
      var pickerCalls = 0;
      const storage = MethodChannel('com.jeerovan.fife/channel_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storage, (call) async {
        switch (call.method) {
          case 'startAccessing':
            return call.arguments['bookmark'] == 'fresh-bookmark'
                ? replacement.path
                : null;
          case 'stopAccessing':
            return true;
          case 'pickDirectory':
            pickerCalls++;
            return {'path': replacement.path, 'bookmark': 'fresh-bookmark'};
          default:
            throw StateError('Unexpected storage operation');
        }
      });
      await fixture.mount(() async {});
      final row = find.byKey(const ValueKey('folder'));
      await fixture.waitFor(find.byIcon(LucideIcons.alertCircle));
      final db = await StorageSqlite.instance.database;
      final idsBefore = await db.query('items', columns: ['id'], orderBy: 'id');
      await fixture.longPress(row);
      await fixture.waitFor(find.byTooltip('Reconnect'));
      await tester.tap(find.byTooltip('Reconnect'));
      for (var i = 0; i < 50; i++) {
        await fixture.pump();
        if ((await ModelItem.get('folder'))?.bookmark == 'fresh-bookmark' &&
            find.byIcon(LucideIcons.plus).evaluate().isNotEmpty &&
            find.byIcon(LucideIcons.alertCircle).evaluate().isEmpty) {
          break;
        }
      }
      expect(pickerCalls, 1);
      expect(find.byIcon(LucideIcons.alertCircle), findsNothing);
      expect(find.byIcon(LucideIcons.plus), findsOneWidget);
      expect(row, findsOneWidget);
      expect(find.byKey(const ValueKey('file')), findsNothing,
          reason: 'Reconnection must not navigate away from the current list');
      expect(tester.widget<FileListItem>(row).isMultiSelectNotifier.value,
          isFalse);
      expect((await ModelItem.get('folder'))!.path, replacement.path);
      expect((await ModelItem.get('folder'))!.bookmark, 'fresh-bookmark');
      expect(
          await db.query('items', columns: ['id'], orderBy: 'id'), idsBefore);
      await tester.tap(row);
      await fixture.waitFor(find.byKey(const ValueKey('file')));
      expect(pickerCalls, 1);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('late access check cannot open a picker after browsing away',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      final access = Completer<String?>();
      var delayAccess = false;
      var pickerCalls = 0;
      const storage = MethodChannel('com.jeerovan.fife/channel_storage');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storage, (call) async {
        if (call.method == 'startAccessing') {
          return delayAccess ? access.future : null;
        }
        if (call.method == 'pickDirectory') pickerCalls++;
        return null;
      });
      await fixture.mount(() async {});
      await fixture.waitFor(find.byIcon(LucideIcons.alertCircle));
      delayAccess = true;
      final row = find.byKey(const ValueKey('folder'));
      await fixture.longPress(row);
      await tester.tap(row); // Deselect while eligibility is still checking.
      await fixture.pump();
      await tester.tap(row); // Now browse without waiting for the old check.
      await fixture.waitFor(find.byKey(const ValueKey('file')));
      access.complete(null);
      await fixture.pump();
      await fixture.pump();
      expect(pickerCalls, 0);
      expect(find.byKey(const ValueKey('file')), findsOneWidget);
      expect(fixture.file.isMultiSelectNotifier.value, isFalse);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  test('Sync has a translated label in every supported locale', () async {
    for (final locale in L10n.all) {
      final strings = await AppLocalizations.delegate.load(locale);
      expect(strings.sync.trim(), isNotEmpty, reason: locale.toString());
      expect(strings.sync, locale.languageCode == 'en' ? 'Sync' : isNot('Sync'),
          reason: locale.toString());
    }
    final english =
        await AppLocalizations.delegate.load(const Locale('en', 'US'));
    expect(english.sync, 'Sync');
  });

  testWidgets('manual sync is the last menu action and refreshes local files',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      await fixture.mount(() async {}, locale: const Locale('en', 'US'));
      await tester.tap(find.text('nested'));
      await fixture.waitFor(find.byKey(const ValueKey('file')));
      expect(find.byType(AnimatedSyncButton), findsNothing);
      expect(find.text('Sync'), findsNothing);

      final file = (await ModelItem.get('file'))!;
      file.size = 75;
      await file.update(['size']);
      expect(fixture.file.item.size, 50);

      await tester.tap(find.byType(PopupMenuButton<int>));
      await fixture.waitFor(find.text('Sync'));
      final items = tester
          .widgetList<PopupMenuItem<int>>(find.byType(PopupMenuItem<int>));
      expect(
          find.descendant(
              of: find.byWidget(items.last), matching: find.text('Sync')),
          findsOneWidget);
      expect(items.last.enabled, isTrue);
      await tester.ensureVisible(find.text('Sync'));
      await fixture.pumpMenu();
      await tester.tap(find.text('Sync'));
      for (var i = 0; i < 30 && fixture.file.item.size != 75; i++) {
        await fixture.pump();
      }
      expect(fixture.file.item.size, 75);
      expect(fixture.scans, 1);

      fixture.file.onLongPress();
      await fixture.pump();
      expect(find.byType(PopupMenuButton<int>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('sync menu is disabled while syncing and available afterward',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      final startup = fixture.gate();
      await fixture.mount(() => startup.future);
      EventStream().publish(AppEvent(
          type: EventType.system, id: 'fixture', key: EventKey.running));
      await fixture.pump();
      await tester.tap(find.byType(PopupMenuButton<int>));
      await fixture.waitFor(find.text('Sync'));
      final item = tester.widget<PopupMenuItem<int>>(find.ancestor(
          of: find.text('Sync'), matching: find.byType(PopupMenuItem<int>)));
      expect(item.enabled, isFalse);
      await fixture.pumpMenu();
      await fixture.dismissMenu();

      EventStream().publish(AppEvent(
          type: EventType.system, id: 'fixture', key: EventKey.stopped));
      await fixture.waitFor(find.byIcon(LucideIcons.plus));
      await tester.tap(find.byType(PopupMenuButton<int>));
      await fixture.waitFor(find.text('Sync'));
      final ready = tester.widget<PopupMenuItem<int>>(find.ancestor(
          of: find.text('Sync'), matching: find.byType(PopupMenuItem<int>)));
      expect(ready.enabled, isTrue);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('sync refresh keeps selection on the current item snapshot',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      await fixture.mount(() async {});
      await tester.tap(find.text('nested'));
      await fixture.waitFor(find.byKey(const ValueKey('file')));
      final beforeRefresh = fixture.file;
      beforeRefresh.onLongPress();
      await fixture.pump();
      final updated = (await ModelItem.get('file'))!;
      updated.size = 75;
      updated.fileHash = 'changed-after-selection';
      await updated.update(['size', 'file_hash']);
      EventStream().publish(AppEvent(
          type: EventType.system, id: 'fixture', key: EventKey.stopped));
      for (var i = 0; i < 30 && fixture.file.item.size != 75; i++) {
        await fixture.pump();
      }
      final selection = fixture.file.selectedItemsNotifier;
      expect(selection.value, hasLength(1));
      expect(selection.value.single.size, 75,
          reason: 'Info and selection must use refreshed file metadata');
      expect(selection.value.single.fileHash, 'changed-after-selection');
      expect(selection.value.contains(fixture.file.item), isTrue,
          reason: 'The refreshed row must retain its selected appearance');
      beforeRefresh.onTap();
      await fixture.pump();
      expect(selection.value, isEmpty,
          reason: 'An old pointer callback must deselect the same file ID');
      expect(fixture.file.isMultiSelectNotifier.value, isFalse);
    });
  });

  testWidgets('a selected item removed during sync leaves no stale actions',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      await fixture.mount(() async {});
      await tester.tap(find.text('nested'));
      await fixture.waitFor(find.byKey(const ValueKey('file')));
      final row = fixture.file;
      row.onLongPress();
      await fixture.pump();
      await (await StorageSqlite.instance.database)
          .delete('items', where: 'id = ?', whereArgs: ['file']);
      EventStream().publish(AppEvent(
          type: EventType.system, id: 'fixture', key: EventKey.stopped));
      for (var i = 0; i < 30 && row.isMultiSelectNotifier.value; i++) {
        await fixture.pump();
      }
      expect(row.selectedItemsNotifier.value, isEmpty);
      expect(row.isMultiSelectNotifier.value, isFalse);
      expect(find.byTooltip('Info'), findsNothing);
    });
  });

  testWidgets('Sync is last and refreshes both vault root and remote folders',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      final db = await StorageSqlite.instance.database;
      await ModelItem.ensureVaultRoot();
      await db.update('items', {'parent_id': 'fife'},
          where: 'id = ?', whereArgs: ['device']);
      await db.insert('items', {
        'id': 'remote',
        'parent_id': 'fife',
        'name': 'Other device',
        'is_folder': 1,
        'archived_at': 0,
      });
      await db.insert('items', {
        'id': 'remote-child',
        'parent_id': 'remote',
        'root_id': 'remote-child',
        'name': 'Remote folder',
        'is_folder': 1,
        'archived_at': 0,
      });
      await fixture.mount(() async {});
      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await fixture.waitFor(find.byKey(const ValueKey('remote')));

      for (final id in ['remote', 'remote-child']) {
        if (id == 'remote-child') {
          await tester.tap(find.byKey(const ValueKey('remote')));
          await fixture.waitFor(find.byKey(const ValueKey('remote-child')));
          expect(find.byKey(const ValueKey('remote')), findsNothing);
        }
        final item = (await ModelItem.get(id))!;
        final updatedName = '${item.name} updated';
        item.name = updatedName;
        await item.update(['name']);
        expect(find.text(updatedName), findsNothing);

        await tester.tap(find.byType(PopupMenuButton<int>));
        await fixture.waitFor(find.text('Sync'));
        final entries = tester
            .widgetList<PopupMenuItem<int>>(find.byType(PopupMenuItem<int>));
        expect(
            find.descendant(
                of: find.byWidget(entries.last), matching: find.text('Sync')),
            findsOneWidget);
        expect(entries.last.enabled, isTrue);
        await tester.ensureVisible(find.text('Sync'));
        await fixture.pumpMenu();
        await tester.tap(find.text('Sync'));
        await fixture.waitFor(find.text(updatedName));
        await fixture.pumpMenu();
      }
      expect(fixture.scans, 1);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('startup sync runs once; resume refreshes stored metadata only',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      final gate = fixture.gate();
      final source = File('${fixture.directory.path}/hello.txt');
      await source.writeAsBytes(List.filled(50, 65));
      await fixture.mount(() async {
        await gate.future;
        final file = (await ModelItem.get('file'))!;
        file.size = await source.length();
        file.fileHash = 'after';
        await file.update(['size', 'file_hash']);
      });
      expect(fixture.scans, 1);
      await tester.tap(find.text('nested').first);
      await fixture.waitFor(find.byKey(const ValueKey('file')));
      fixture.file.onLongPress();
      await fixture.pump();
      expect(fixture.file.selectedItemsNotifier.value.map((item) => item.id),
          ['file']);

      // An external edit during startup is picked up by that startup scan.
      await source.writeAsBytes(List.filled(70, 66));
      fixture.resumeRepeatedly();
      await fixture.pump();
      expect(fixture.scans, 1);
      expect(fixture.file.item.size, 50);
      gate.complete();
      for (var i = 0; i < 30 && fixture.file.item.size != 70; i++) {
        await fixture.pump();
      }
      expect(fixture.file.item.size, 70);
      expect(fixture.file.item.fileHash, 'after');
      expect(fixture.file.item.parentId, 'folder');
      expect(fixture.file.item.archivedAt, 0);

      // Resume reflects a background DB update, without scanning local files.
      final file = (await ModelItem.get('file'))!;
      file.size = 90;
      await file.update(['size']);
      fixture.resumeRepeatedly();
      for (var i = 0; i < 30 && fixture.file.item.size != 90; i++) {
        await fixture.pump();
      }
      expect(fixture.scans, 1);
      expect(fixture.file.item.size, 90);
      expect(fixture.file.item.parentId, 'folder');
      expect(fixture.file.selectedItemsNotifier.value.map((item) => item.id),
          ['file']);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('failed startup sync is not retried by resume', (tester) async {
    await withExplorer(tester, (fixture) async {
      await fixture.mount(() async => throw StateError('Startup unavailable'));
      fixture.resumeRepeatedly();
      await fixture.pump();
      await fixture.pump();
      expect(fixture.scans, 1);
      expect(find.text('nested'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('disposal during startup cannot queue another sync or update UI',
      (tester) async {
    await withExplorer(tester, (fixture) async {
      final gate = fixture.gate();
      await fixture.mount(() => gate.future);
      fixture.resumeRepeatedly();
      await tester.pumpWidget(const SizedBox.shrink());
      gate.complete();
      await fixture.pump();
      fixture.resumeRepeatedly();
      await fixture.pump();
      expect(fixture.scans, 1);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> withExplorer(WidgetTester tester,
    Future<void> Function(ExplorerFixture fixture) body) async {
  await tester.runAsync(() async {
    final directory = await Directory.systemTemp.createTemp('fife-startup-');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const storage = MethodChannel('com.jeerovan.fife/channel_storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    messenger.setMockMethodCallHandler(
        storage,
        (call) async =>
            call.method == 'startAccessing' ? directory.path : null);
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    final db = await StorageSqlite.instance.database;
    await db.insert(
        'settings', {'id': AppString.deviceHash.string, 'value': 'device'});
    ModelSetting.settingJson = {AppString.deviceHash.string: 'device'};
    await db
        .insert('items', {'id': 'device', 'name': 'device', 'is_folder': 1});
    await db.insert('items', {
      'id': 'folder',
      'parent_id': 'device',
      'root_id': 'folder',
      'name': 'nested',
      'is_folder': 1,
      'path': directory.path,
      'bookmark': 'fixture-bookmark',
    });
    await db.insert('items', {
      'id': 'file',
      'parent_id': 'folder',
      'root_id': 'folder',
      'name': 'hello.txt',
      'size': 50,
      'file_hash': 'before',
    });
    await db.update('items', {'archived_at': 0});
    final fixture = ExplorerFixture(tester, directory);
    try {
      await body(fixture);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final gate in fixture.gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await fixture.pump();
      await fixture.pump();
      await StorageSqlite.instance.close();
      ModelSetting.settingJson = {};
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(storage, null);
      await directory.delete(recursive: true);
    }
  });
}

class ExplorerFixture {
  ExplorerFixture(this.tester, this.directory);
  final WidgetTester tester;
  final Directory directory;
  final List<Completer<void>> gates = [];
  int scans = 0;

  FileListItem get file =>
      tester.widget<FileListItem>(find.byKey(const ValueKey('file')));

  Completer<void> gate() {
    final gate = Completer<void>();
    gates.add(gate);
    return gate;
  }

  Future<void> pump() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
  }

  Future<void> longPress(Finder target) async {
    final gesture = await tester.startGesture(tester.getCenter(target));
    // withExplorer uses runAsync for SQLite/filesystem work. Gesture timers
    // therefore use real time; tester.longPress's fake-clock pump is a tap here.
    await Future<void>.delayed(
        kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pump();
    await gesture.up();
    await pump();
  }

  Future<void> pumpMenu() async {
    await pump();
    await tester.pump(const Duration(milliseconds: 300));
    await pump();
  }

  Future<void> dismissMenu() async {
    await tester.binding.handlePopRoute();
    final entries = find.byType(PopupMenuItem<int>);
    for (var i = 0; i < 30 && entries.evaluate().isNotEmpty; i++) {
      await pump();
    }
    expect(entries, findsNothing);
  }

  Future<void> waitFor(Finder finder) async {
    for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
      await pump();
    }
    expect(finder, findsWidgets);
  }

  Future<void> mount(Future<void> Function() scan, {Locale? locale}) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: FilePane(
        onThemeChange: (_) {},
        reconcileOnStart: () async {
          scans++;
          await scan();
        },
      )),
    ));
    await waitFor(find.text('nested'));
  }

  void resumeRepeatedly() {
    for (var i = 0; i < 3; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  }
}
