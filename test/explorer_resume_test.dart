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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
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
