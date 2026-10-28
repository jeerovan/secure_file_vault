import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/item_selection_actions.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/ui/pages/page_search.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  testWidgets('missing FiFe root is restored without replacing vault items',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      final db = await StorageSqlite.instance.database;
      await db.delete('items', where: 'id = ?', whereArgs: ['fife']);
      final before = await db.query('items', orderBy: 'id');
      final changes = await db.query('changes', orderBy: 'id');
      await fixture.mount();
      final trail =
          tester.widget<BreadcrumbTrail>(find.byType(BreadcrumbTrail));
      expect(trail.parentChilds.map((item) => item.id),
          ['fife', 'device', 'local-root']);
      expect(trail.parentChilds.first.name, 'FiFe');
      expect((await ModelItem.get('fife'))!.isFolder, isTrue);
      expect(
          await db.query('items',
              where: 'id != ?', whereArgs: ['fife'], orderBy: 'id'),
          before);
      expect(await db.query('changes', orderBy: 'id'), changes);
      await tester.tap(find.descendant(
          of: find.byType(BreadcrumbTrail), matching: find.text('FiFe')));
      await fixture.waitFor(() =>
          find.byKey(const ValueKey('other-device')).evaluate().isNotEmpty);
      expect(await ModelItem.isLocalPath('local'), isTrue);
      expect(await ModelItem.isLocalPath('remote'), isFalse);
    });
  });

  for (final search in [false, true]) {
    for (final remote in [false, true]) {
      for (final exists in [false, true]) {
        testWidgets(
            '${search ? "Search" : "Explorer"}: ${remote ? "remote" : "local"} '
            '${exists ? "present" : "missing"} file offers eligible actions',
            (tester) async {
          await withSelectionFixture(tester, (fixture) async {
            if (exists) await fixture.createCopy(remote ? 'remote' : 'local');
            await fixture.mount(search: search, remote: remote);
            await fixture.select(remote ? 'remote' : 'local');
            fixture.expectActions(
                delete: remote && exists,
                archive: !remote && !exists,
                download: !exists);
          });
        });
      }
    }
  }

  for (final remote in [false, true]) {
    for (final exists in [false, true]) {
      testWidgets(
          'Explorer: ${remote ? "remote" : "local"} '
          '${exists ? "present" : "missing"} folder offers eligible actions',
          (tester) async {
        await withSelectionFixture(tester, (fixture) async {
          final id = remote ? 'remote-folder' : 'local-folder';
          if (exists) {
            await Directory(await ModelItem.getPathForItem(id))
                .create(recursive: true);
          }
          await fixture.mount(remote: remote);
          await fixture.select(id);
          fixture.expectActions(
              delete: remote && exists,
              archive: !remote && !exists,
              download: false);
        });
      });
    }
  }

  for (final search in [false, true]) {
    testWidgets(
        '${search ? "Search" : "Explorer"}: deleting a remote copy '
        'retains source bytes and cloud metadata', (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        final source = await fixture.createCopy('local');
        final downloaded = await fixture.createCopy('remote');
        await fixture.mount(search: search, remote: true);
        await fixture.select('remote');
        await fixture.tapAction('Delete');
        await fixture
            .waitFor(() => find.byTooltip('Cancel').evaluate().isEmpty);
        expect(await downloaded.exists(), isFalse);
        expect(await source.readAsString(), 'preserve this content');
        expect((await ModelItem.get('remote'))!.archivedAt, 0);
        final db = await StorageSqlite.instance.database;
        expect((await db.query('files')).length, 2);
        expect(await db.query('changes'), isEmpty);
      });
    });

    testWidgets(
        '${search ? "Search" : "Explorer"}: absent local file archives '
        'while retaining its cloud record', (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.mount(search: search);
        await fixture.select('local');
        await fixture.tapAction('Archive');
        await fixture
            .waitFor(() => find.byTooltip('Cancel').evaluate().isEmpty);
        expect((await ModelItem.get('local'))!.archivedAt, greaterThan(0));
        await fixture.waitFor(
            () => find.byKey(const ValueKey('local')).evaluate().isEmpty);
        expect((await ModelItem.get('remote'))!.archivedAt, 0);
        final db = await StorageSqlite.instance.database;
        expect((await db.query('files')).length, 2);
      });
    });

    testWidgets(
        '${search ? "Search" : "Explorer"}: file restored after selection '
        'cannot be archived through a stale button', (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.mount(search: search);
        await fixture.select('local');
        await fixture.waitForAction('Archive');
        final restored = await fixture.createCopy('local');
        await fixture.tapAction('Archive');
        await fixture
            .waitFor(() => find.byTooltip('Archive').evaluate().isEmpty);
        await fixture.pump();
        expect((await ModelItem.get('local'))!.archivedAt, 0);
        expect(await restored.readAsString(), 'preserve this content');
        fixture.expectActions(delete: false, archive: false, download: false);
      });
    });

    testWidgets(
        '${search ? "Search" : "Explorer"}: resume refreshes action '
        'eligibility while preserving selection', (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        final source = await fixture.createCopy('local');
        await fixture.mount(search: search);
        await fixture.select('local');
        await source.delete();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await fixture
            .waitFor(() => find.byTooltip('Archive').evaluate().isNotEmpty);
        fixture.expectActions(delete: false, archive: true, download: true);
        expect(fixture.row('local').selectedItemsNotifier.value.single.id,
            'local');
      });
    });
  }

  testWidgets('remote folder deletion removes only its downloaded subtree',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      final folderPath = await ModelItem.getPathForItem('remote-folder');
      final child =
          await File('$folderPath/sub/child.txt').create(recursive: true);
      await child.writeAsString('downloaded child');
      final source = await fixture.createCopy('local');
      await fixture.mount(remote: true);
      await fixture.select('remote-folder');
      await fixture.tapAction('Delete');
      await fixture.waitFor(() => find.byTooltip('Cancel').evaluate().isEmpty);
      expect(await Directory(folderPath).exists(), isFalse);
      expect((await ModelItem.get('remote-folder'))!.archivedAt, 0);
      expect(await source.readAsString(), 'preserve this content');
    });
  });

  testWidgets(
      'mixed-origin Search selection cannot archive or delete either item',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await fixture.createCopy('remote');
      await fixture.mount(search: true);
      await fixture.select('local');
      fixture.row('remote').onTap();
      for (var i = 0; i < 6; i++) {
        await fixture.pump();
      }
      fixture.expectActions(delete: false, archive: false, download: false);
      fixture.row('remote').onTap();
      await fixture
          .waitFor(() => find.byTooltip('Archive').evaluate().isNotEmpty);
      fixture.expectActions(delete: false, archive: true, download: true);
    });
  });

  testWidgets('local file replaced by a directory is not treated as missing',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await Directory(await ModelItem.getPathForItem('local')).create();
      await fixture.mount();
      await fixture.select('local');
      fixture.expectActions(delete: false, archive: false, download: false);
    });
  });

  testWidgets('late local check cannot overwrite a newer remote selection',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await fixture.createCopy('remote');
      await fixture.mount(search: true);
      final entered = Completer<void>();
      final release = fixture.gate();
      fixture.beforeAccess = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      fixture.row('local').onLongPress();
      await fixture.waitFor(() => entered.isCompleted);
      fixture.beforeAccess = null;
      fixture.row('remote').onTap();
      fixture.row('local').onTap();
      await fixture
          .waitFor(() => find.byTooltip('Delete').evaluate().isNotEmpty);
      release.complete();
      await fixture.pump();
      await fixture.pump();
      fixture.expectActions(delete: true, archive: false, download: false);
    });
  }, skip: !Platform.isIOS && !Platform.isMacOS);

  testWidgets('disposal during action checks releases its folder access',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await fixture.mount();
      final entered = Completer<void>();
      final release = fixture.gate();
      fixture.beforeAccess = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      fixture.row('local').onLongPress();
      await fixture.waitFor(() => entered.isCompleted);
      await tester.pumpWidget(const SizedBox.shrink());
      release.complete();
      await fixture.waitFor(() => fixture.accessesReleased);
      expect(fixture.scopeHolds, 0);
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isIOS && !Platform.isMacOS);

  testWidgets(
      'source folder changed after selection cannot delete a local original',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      final original = await fixture.createCopy('local');
      final copy = await fixture.createCopy('remote');
      await fixture.mount(remote: true);
      await fixture.select('remote');
      final db = await StorageSqlite.instance.database;
      await db.update('items', {'parent_id': 'device'},
          where: 'id = ?', whereArgs: ['remote-root']);
      final newSource = await fixture.createCopy('remote');
      await fixture.tapAction('Delete');
      await fixture.waitFor(() => find.byTooltip('Delete').evaluate().isEmpty);
      await fixture.pump();
      expect(await original.exists(), isTrue);
      expect(await newSource.exists(), isTrue);
      expect(await copy.exists(), isTrue);
      expect((await ModelItem.get('remote'))!.archivedAt, 0);
    });
  });

  testWidgets('handlers reject remote archival and local source deletion',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      final source = await fixture.createCopy('local');
      final copy = await fixture.createCopy('remote');
      final selection =
          ValueNotifier<Set<ModelItem>>({(await ModelItem.get('remote'))!});
      final actions = ItemSelectionActions(selection);
      try {
        expect(await actions.perform(ItemSelectionAction.archive), isFalse);
        selection.value = {(await ModelItem.get('local'))!};
        expect(await actions.perform(ItemSelectionAction.deleteLocal), isFalse);
        expect((await ModelItem.get('remote'))!.archivedAt, 0);
        expect(await source.exists(), isTrue);
        expect(await copy.exists(), isTrue);
      } finally {
        actions.dispose();
        selection.dispose();
      }
    });
  });

  testWidgets(
      'download queues only confirmed missing files and preserves metadata',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      final selection =
          ValueNotifier<Set<ModelItem>>({(await ModelItem.get('remote'))!});
      final actions = ItemSelectionActions(selection);
      try {
        expect(await actions.perform(ItemSelectionAction.download), isTrue);
        expect(
            (await ModelItemTask.get('remote'))!.task, ItemTask.download.value);
        final source = await fixture.createCopy('local');
        selection.value = {(await ModelItem.get('local'))!};
        expect(await actions.perform(ItemSelectionAction.download), isFalse);
        expect(await ModelItemTask.get('local'), isNull);
        expect(await source.readAsString(), 'preserve this content');
        expect((await ModelItem.get('remote'))!.archivedAt, 0);
      } finally {
        actions.dispose();
        selection.dispose();
      }
    });
  });

  testWidgets('changing selection immediately cancels an obsolete action',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      final selection =
          ValueNotifier<Set<ModelItem>>({(await ModelItem.get('local'))!});
      final actions = ItemSelectionActions(selection);
      try {
        final pending = actions.perform(ItemSelectionAction.archive);
        selection.value = {(await ModelItem.get('remote'))!};
        expect(await pending, isFalse);
        expect((await ModelItem.get('local'))!.archivedAt, 0);
        expect((await ModelItem.get('remote'))!.archivedAt, 0);
      } finally {
        actions.dispose();
        selection.dispose();
      }
    });
  });

  testWidgets('a background refresh does not cancel a valid archive action',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      final selection =
          ValueNotifier<Set<ModelItem>>({(await ModelItem.get('local'))!});
      final actions = ItemSelectionActions(selection);
      try {
        final pending = actions.perform(ItemSelectionAction.archive);
        await actions.refresh();
        expect(await pending, isTrue);
        expect((await ModelItem.get('local'))!.archivedAt, greaterThan(0));
      } finally {
        actions.dispose();
        selection.dispose();
      }
    });
  });

  testWidgets(
      'disconnected source file offers Download without source deletion',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await fixture.mount();
      fixture.denyAccess = true;
      await fixture.select('local');
      fixture.expectActions(delete: false, archive: false, download: true);
      expect((await ModelItem.get('local'))!.archivedAt, 0);
    });
  }, skip: !Platform.isIOS && !Platform.isMacOS);

  testWidgets('disconnected root selection offers Reconnect Download Archive',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await fixture.mount();
      fixture.denyAccess = true;
      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await fixture.waitFor(
          () => find.byKey(const ValueKey('local-root')).evaluate().isNotEmpty);
      fixture.row('local-root').onLongPress();
      await fixture.waitForAction('Reconnect');
      fixture.expectActions(delete: false, archive: true, download: true);
      expect(fixture.row('local-root').selectedItemsNotifier.value.single.id,
          'local-root');
    });
  }, skip: !Platform.isIOS && !Platform.isMacOS);

  testWidgets('permission lost after selection prevents local archival',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await fixture.mount();
      await fixture.select('local');
      await fixture.waitForAction('Archive');
      fixture.denyAccess = true;
      await fixture.tapAction('Archive');
      await fixture.waitFor(() => find.byTooltip('Archive').evaluate().isEmpty);
      await fixture.pump();
      expect((await ModelItem.get('local'))!.archivedAt, 0);
      fixture.expectActions(delete: false, archive: false, download: true);
    });
  }, skip: !Platform.isIOS && !Platform.isMacOS);

  testWidgets(
      'source folder changed during access lookup cannot expose Archive',
      (tester) async {
    await withSelectionFixture(tester, (fixture) async {
      await fixture.mount();
      fixture.beforeAccess = () async {
        fixture.beforeAccess = null;
        final db = await StorageSqlite.instance.database;
        await db.update('items', {'parent_id': 'other-device'},
            where: 'id = ?', whereArgs: ['local-root']);
      };
      await fixture.select('local');
      expect(find.byTooltip('Archive'), findsNothing);
      expect((await ModelItem.get('local'))!.archivedAt, 0);
    });
  }, skip: !Platform.isIOS && !Platform.isMacOS);
}

Future<void> withSelectionFixture(
    WidgetTester tester, Future<void> Function(SelectionFixture) body) async {
  await tester.runAsync(() async {
    final directory = await Directory.systemTemp.createTemp('fife-actions-');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const storage = MethodChannel('com.jeerovan.fife/channel_storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    final db = await StorageSqlite.instance.database;
    await StorageSqlite.instance.clearDb();
    ModelSetting.settingJson = {AppString.deviceHash.string: 'device'};
    await db.insert(
        'settings', {'id': AppString.deviceHash.string, 'value': 'device'});
    for (final id in ['fife', 'device', 'other-device']) {
      await db.insert('items', {
        'id': id,
        'name': id,
        'is_folder': 1,
        'parent_id': id == 'fife' ? null : 'fife',
        'archived_at': 0,
      });
    }
    final source = await Directory('${directory.path}/source').create();
    for (final origin in ['local', 'remote']) {
      await db.insert('files', {'id': '$origin-content', 'uploaded_at': 100});
      await db.insert('items', {
        'id': '$origin-root',
        'name': '$origin-root',
        'parent_id': origin == 'local' ? 'device' : 'other-device',
        'root_id': '$origin-root',
        'is_folder': 1,
        'path': source.path,
        'bookmark': 'fixture-bookmark',
        'archived_at': 0,
      });
      for (final folder in [false, true]) {
        await db.insert('items', {
          'id': folder ? '$origin-folder' : origin,
          'name': folder ? '$origin-folder' : '$origin-sample.txt',
          'parent_id': '$origin-root',
          'root_id': '$origin-root',
          'is_folder': folder ? 1 : 0,
          'file_hash': folder ? null : '$origin-content',
          'archived_at': 0,
        });
      }
    }
    // Native path-provider calls can bypass the method-channel fixture
    // override, leaving downloaded copies outside systemTemp.
    // Remove only this fixture's cache subtree, inside the guarded test app.
    final downloadedRoot =
        Directory(await ModelItem.getPathForItem('remote-root'));
    if (await downloadedRoot.exists()) {
      await downloadedRoot.delete(recursive: true);
    }
    final copyToken =
        base64UrlEncode(utf8.encode('local-root')).replaceAll('=', '');
    final managedRoot = Directory(
        '${await ModelItem.getPathForItem('fife')}/.downloads/$copyToken');
    if (await managedRoot.exists()) await managedRoot.delete(recursive: true);
    final fixture = SelectionFixture(tester, directory, source);
    messenger.setMockMethodCallHandler(storage, (call) async {
      if (call.method == 'startAccessing') {
        fixture.pendingAccess++;
        try {
          await fixture.beforeAccess?.call();
          if (fixture.denyAccess) {
            throw PlatformException(code: 'ACCESS_DENIED');
          }
          fixture.scopeHolds++;
          return fixture.resolvedRootPath ?? source.path;
        } finally {
          fixture.pendingAccess--;
        }
      }
      if (call.method == 'stopAccessing') {
        fixture.scopeHolds--;
        return true;
      }
      return null;
    });
    try {
      await body(fixture);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final gate in fixture.gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await fixture.pump();
      await fixture.pump();
      // Widget disposal suppresses stale results, but its already-running
      // filesystem reads still need to finish and release their bookmarks.
      await fixture.waitFor(() => fixture.accessesReleased);
      expect(fixture.scopeHolds, 0);
      if (await downloadedRoot.exists()) {
        await downloadedRoot.delete(recursive: true);
      }
      if (await managedRoot.exists()) await managedRoot.delete(recursive: true);
      await StorageSqlite.instance.close();
      ModelSetting.clear();
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(storage, null);
      await directory.delete(recursive: true);
    }
  });
}

class SelectionFixture {
  SelectionFixture(this.tester, this.directory, this.source);
  final WidgetTester tester;
  final Directory directory;
  final Directory source;
  String? resolvedRootPath;
  bool denyAccess = false;
  int scopeHolds = 0;
  int pendingAccess = 0;
  bool get accessesReleased => pendingAccess == 0 && scopeHolds == 0;
  Future<void> Function()? beforeAccess;
  final gates = <Completer<void>>[];

  Completer<void> gate() {
    final gate = Completer<void>();
    gates.add(gate);
    return gate;
  }

  Future<File> createCopy(String id) async {
    final file =
        await File(await ModelItem.getPathForItem(id)).create(recursive: true);
    await file.writeAsString('preserve this content');
    return file;
  }

  Future<void> pump() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> waitFor(bool Function() ready) async {
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
      await pump();
    }
    expect(ready(), isTrue);
  }

  Future<void> waitForAction(String name) =>
      waitFor(() => find.byTooltip(name).evaluate().isNotEmpty);

  Future<void> tapAction(String name) async {
    await waitForAction(name);
    await tester.tap(find.byTooltip(name));
  }

  FileListItem row(String id) =>
      tester.widget<FileListItem>(find.byKey(ValueKey(id)));

  Future<void> mount({bool search = false, bool remote = false}) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: search
            ? const SearchScreen()
            : FilePane(onThemeChange: (_) {}, reconcileOnStart: () async {}),
      ),
    ));
    if (search) {
      await tester.enterText(find.byType(TextField), 'sample');
      await Future<void>.delayed(const Duration(milliseconds: 550));
    } else {
      await waitFor(
          () => find.byKey(const ValueKey('local-root')).evaluate().isNotEmpty);
      if (remote) {
        await tester.tap(find.byIcon(LucideIcons.arrowLeft));
        await waitFor(() =>
            find.byKey(const ValueKey('other-device')).evaluate().isNotEmpty);
        row('other-device').onTap();
        await waitFor(() =>
            find.byKey(const ValueKey('remote-root')).evaluate().isNotEmpty);
      }
      row(remote ? 'remote-root' : 'local-root').onTap();
    }
    await waitFor(() => find
        .byKey(ValueKey(remote ? 'remote' : 'local'))
        .evaluate()
        .isNotEmpty);
    // A visible row may still be resolving its initial bookmark. Fault hooks
    // installed by callers must target the subsequent user action, not that
    // unfinished render (which can race differently in a larger test run).
    await waitFor(() => find
        .descendant(
            of: find.byKey(ValueKey(remote ? 'remote' : 'local')),
            matching: find.byType(CircularProgressIndicator))
        .evaluate()
        .isEmpty);
    await waitFor(() => accessesReleased);
  }

  Future<void> select(String id) async {
    row(id).onLongPress();
    // Selection is immediate; allow SQLite and scoped filesystem observations
    // to finish before asserting which toolbar actions are available.
    for (var i = 0; i < 6; i++) {
      await pump();
    }
  }

  void expectActions(
      {required bool delete, required bool archive, required bool download}) {
    expect(find.byTooltip('Delete'), delete ? findsOneWidget : findsNothing);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is Tooltip &&
            (widget.message == 'Archive' ||
                widget.message == 'Archive backup')),
        archive ? findsOneWidget : findsNothing);
    expect(
        find.byTooltip('Download'), download ? findsOneWidget : findsNothing);
  }
}
