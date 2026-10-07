import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resume reloads same-ID metadata and keeps the current folder',
      (tester) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('fife-editor-');
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
      addTearDown(() async {
        await StorageSqlite.instance.close();
        messenger.setMockMethodCallHandler(paths, null);
        messenger.setMockMethodCallHandler(storage, null);
        await directory.delete(recursive: true);
      });
      await db.insert(
          'settings', {'id': AppString.deviceHash.string, 'value': 'device'});
      ModelSetting.settingJson = {AppString.deviceHash.string: 'device'};
      addTearDown(() => ModelSetting.settingJson = {});
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
      final source = File('${directory.path}/hello.txt');
      await source.writeAsBytes(List.filled(50, 65));
      var scans = 0;
      Completer<void>? scanGate;
      Future<void> pump() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        await tester.pump();
      }

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: FilePane(
          onThemeChange: (_) {},
          reconcileOnResume: () async {
            scans++;
            await scanGate?.future;
            final file = (await ModelItem.get('file'))!;
            file.size = await source.length();
            file.fileHash = 'after';
            await file.update(['size', 'file_hash']);
          },
        )),
      ));
      for (var i = 0; i < 30 && find.text('nested').evaluate().isEmpty; i++) {
        await pump();
      }
      await tester.tap(find.text('nested').first);
      for (var i = 0;
          i < 30 && find.byKey(const ValueKey('file')).evaluate().isEmpty;
          i++) {
        await pump();
      }
      expect(
          tester
              .widget<FileListItem>(find.byKey(const ValueKey('file')))
              .item
              .size,
          50);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      // Editors may replace the original file atomically.
      final replacement = File('${directory.path}/replacement.txt');
      await replacement.writeAsBytes(List.filled(70, 66));
      await replacement.rename(source.path);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pump();
      await pump();

      expect(scans, 1);
      final item =
          tester.widget<FileListItem>(find.byKey(const ValueKey('file'))).item;
      expect(item.size, 70);
      expect(item.fileHash, 'after');
      expect(item.parentId, 'folder');
      expect(item.archivedAt, 0);
      expect(find.byKey(const ValueKey('file')), findsOneWidget);
      expect(find.text('nested'), findsOneWidget);

      // Repeated resume notifications coalesce while one scan is active.
      scanGate = Completer<void>();
      for (var i = 0; i < 3; i++) {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      }
      expect(scans, 2);
      scanGate.complete();
      scanGate = null;
      for (var i = 0; i < 30 && scans < 3; i++) {
        await pump();
      }
      expect(scans, 3);
      for (var i = 0; i < 5; i++) {
        await pump();
      }

      // Disposal during a pending scan cannot schedule another scan or update UI.
      scanGate = Completer<void>();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(scans, 4);
      await tester.pumpWidget(const SizedBox.shrink());
      scanGate.complete();
      scanGate = null;
      await pump();
      expect(scans, 4);
    });
  });
}
