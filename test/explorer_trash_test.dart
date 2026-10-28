import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/ui/pages/page_trash.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 50; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 200));
    if (ready()) return;
  }
  expect(ready(), isTrue);
}

Future<void> openTrash(WidgetTester tester) async {
  await tester.tap(find.byType(PopupMenuButton<int>));
  await pumpUntil(tester, () => find.text('Trash').evaluate().isNotEmpty);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Trash'));
  await tester.tap(find.text('Trash'));
  await pumpUntil(tester, () => find.byType(PageTrash).evaluate().isNotEmpty);
  await tester.pump(const Duration(milliseconds: 200));
}

Future<ValueNotifier<bool>> setUpExplorer(WidgetTester tester) async {
  final directory = await Directory.systemTemp.createTemp('fife-trash-');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const storage = MethodChannel('com.jeerovan.fife/channel_storage');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
  messenger.setMockMethodCallHandler(storage,
      (call) async => call.method == 'startAccessing' ? directory.path : null);
  await StorageSqlite.initialize(ExecutionMode.mainApp);
  final db = await StorageSqlite.instance.database;
  ModelSetting.settingJson = {AppString.deviceHash.string: 'device'};
  await db.insert(
      'settings', {'id': AppString.deviceHash.string, 'value': 'device'});
  await db.insert('items', {
    'id': 'device',
    'name': 'Test device',
    'is_folder': 1,
    'archived_at': 0,
  });
  await db.insert('items', {
    'id': 'location',
    'parent_id': 'device',
    'root_id': 'location',
    'name': 'Original location',
    'is_folder': 1,
    'archived_at': 0,
    'path': directory.path,
    'bookmark': 'fixture-bookmark',
  });
  await db.insert('items', {
    'id': 'folder',
    'parent_id': 'location',
    'root_id': 'location',
    'name': 'Restorable folder',
    'is_folder': 1,
    'archived_at': 0,
  });
  final showExplorer = ValueNotifier(true);
  addTearDown(() async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await StorageSqlite.instance.close();
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(storage, null);
      ModelSetting.settingJson = {};
      showExplorer.dispose();
      await directory.delete(recursive: true);
    });
  });
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: ValueListenableBuilder<bool>(
        valueListenable: showExplorer,
        builder: (context, visible, child) =>
            visible ? FilePane(onThemeChange: (_) {}) : const SizedBox.shrink(),
      ),
    ),
  ));
  await pumpUntil(tester,
      () => find.byKey(const ValueKey('location')).evaluate().isNotEmpty);
  await tester.tap(find.byKey(const ValueKey('location')));
  await pumpUntil(
      tester, () => find.byKey(const ValueKey('folder')).evaluate().isNotEmpty);
  return showExplorer;
}

void main() {
  testWidgets('returning from Trash shows the restored folder in its location',
      (tester) async {
    await tester.runAsync(() async {
      await setUpExplorer(tester);
      final gesture = await tester
          .startGesture(tester.getCenter(find.byKey(const ValueKey('folder'))));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await gesture.up();
      await pumpUntil(
          tester, () => find.byTooltip('Archive backup').evaluate().isNotEmpty);
      await tester.tap(find.byTooltip('Archive backup'));
      await pumpUntil(
          tester, () => find.byType(AlertDialog).evaluate().isNotEmpty);
      expect((await ModelItem.get('folder'))!.archivedAt, 0);
      await tester.tap(find.widgetWithText(FilledButton, 'Archive backup'));
      await pumpUntil(tester,
          () => find.byKey(const ValueKey('folder')).evaluate().isEmpty);
      expect((await ModelItem.get('folder'))!.archivedAt, greaterThan(0));

      await openTrash(tester);
      await pumpUntil(
          tester, () => find.text('Restorable folder').evaluate().isNotEmpty);
      await tester.tap(find.text('Restorable folder'));
      await tester.pump();
      await tester.tap(find.byTooltip('Recover'));
      await pumpUntil(
          tester, () => find.text('No items.').evaluate().isNotEmpty);
      expect((await ModelItem.get('folder'))!.archivedAt, 0);

      await tester.tap(find.byTooltip('Back'));
      await pumpUntil(tester,
          () => find.byKey(const ValueKey('folder')).evaluate().isNotEmpty);
      final restored = tester
          .widget<FileListItem>(find.byKey(const ValueKey('folder')))
          .item;
      expect(restored.parentId, 'location');
      expect(restored.archivedAt, 0);
      expect(find.text('Original location'), findsOneWidget);

      // Visiting Trash again without changing anything keeps the same location.
      await openTrash(tester);
      await tester.tap(find.byTooltip('Back'));
      await pumpUntil(tester,
          () => find.byKey(const ValueKey('folder')).evaluate().isNotEmpty);
      expect(find.text('Original location'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  testWidgets('returning from Trash after Explorer is disposed is safe',
      (tester) async {
    await tester.runAsync(() async {
      final showExplorer = await setUpExplorer(tester);
      await openTrash(tester);
      showExplorer.value = false;
      await tester.pump();
      expect(find.byType(FilePane, skipOffstage: false), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await pumpUntil(tester,
          () => find.byType(PageTrash, skipOffstage: false).evaluate().isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}
