import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  for (final failure in ['ACCESS_DENIED', 'STALE_BOOKMARK', 'RESOLVE_ERROR']) {
    testWidgets('sync root warns when its stored bookmark fails: $failure',
        (tester) async {
      await _withPresenceFixture(tester, (fixture) async {
        fixture.denyAccess = true;
        fixture.accessError = failure;
        await fixture.mount(itemId: 'root');
        await fixture.expectFolderWarning(true);
        expect((await ModelItem.get('root'))!.bookmark, 'fixture-bookmark');
        expect(await fixture.source.readAsString(), 'source stays on device');
        expect(fixture.scopeHolds, 0);
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);
  }

  testWidgets('missing sync-root directory warns despite a stored bookmark',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      fixture.resolvedPath = '${fixture.source.parent.path}/missing';
      await fixture.mount(itemId: 'root');
      await fixture.expectFolderWarning(true);
      expect(fixture.scopeHolds, 0);
      expect(await ModelItem.get('file'), isNotNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('moved accessible root uses resolved path and has no warning',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      await fixture.db.update('items', {'path': '/old-container/selected'},
          where: 'id = ?', whereArgs: ['root']);
      await fixture.mount(itemId: 'root');
      await fixture.expectFolderWarning(false);
      expect(fixture.accessAttempts, greaterThan(0));
      expect(fixture.scopeHolds, 0);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('reconnected same root removes warning on the next snapshot',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      fixture.denyAccess = true;
      await fixture.mount(itemId: 'root');
      await fixture.expectFolderWarning(true);
      fixture.denyAccess = false;
      await ModelItem.updateBookmark('root', 'fresh-bookmark');
      await fixture.mount(itemId: 'root');
      await fixture.expectFolderWarning(false);
      expect((await ModelItem.get('file'))!.fileHash, 'uploaded-content');
      expect(fixture.scopeHolds, 0);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('remote and nested folders do not ask for a root bookmark',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      fixture.denyAccess = true;
      for (final parent in ['other-device', 'another-folder']) {
        await fixture.db.update('items', {'parent_id': parent},
            where: 'id = ?', whereArgs: ['root']);
        await fixture.mount(itemId: 'root');
        await fixture.expectFolderWarning(false);
      }
      expect(fixture.accessAttempts, 0);
    });
  });

  testWidgets('selected file stays green after upload releases folder access',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      // Simulate the upload holding the Files-picker security scope. The
      // indicator initially succeeds even without acquiring its own access.
      fixture.scopeHolds = 1;
      await fixture.mount(
          status: TaskStatus(
              task: ItemTask.upload.value,
              progress: 50,
              state: TransferTaskState.running));
      await fixture.expectColor(Colors.green);
      expect(fixture.scopeHolds, 1);
      fixture.scopeHolds--;
      await fixture.mount();
      await fixture.expectColor(Colors.green);
      expect(fixture.scopeHolds, 0);
      expect(await fixture.source.readAsString(), 'source stays on device');
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('bookmark-resolved moved folder shows its existing file green',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      await fixture.db.update('items', {'path': '/old-container/selected'},
          where: 'id = ?', whereArgs: ['root']);
      await fixture.mount();
      await fixture.expectColor(Colors.green);
      expect(fixture.scopeHolds, 0);
      expect((await ModelItem.get('file'))!.fileHash, 'uploaded-content');
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('denied folder access is unknown rather than a missing red file',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      fixture.denyAccess = true;
      await fixture.mount();
      await fixture.expectColor(Colors.grey.shade400);
      expect(fixture.scopeHolds, 0);
      expect(await ModelItem.get('file'), isNotNull);
      expect(await fixture.source.readAsString(), 'source stays on device');
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets(
      'confirmed deleted local file is red while its cloud copy remains',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      await fixture.source.delete();
      await fixture.mount();
      await fixture.expectColor(Colors.red);
      expect(fixture.scopeHolds, 0);
      expect((await fixture.db.query('files')).single['uploaded_at'], 100);
      expect(await ModelItem.get('file'), isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('restored folder permission refreshes the badge to green',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      fixture.denyAccess = true;
      await fixture.mount();
      await fixture.expectColor(Colors.grey.shade400);
      fixture.denyAccess = false;
      await fixture.mount();
      await fixture.expectColor(Colors.green);
      expect(fixture.scopeHolds, 0);
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('download completion changes a missing local file back to green',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      await fixture.source.delete();
      await fixture.mount(
          status: TaskStatus(
              task: ItemTask.download.value,
              progress: 50,
              state: TransferTaskState.running));
      await fixture.expectColor(Colors.red);
      await fixture.source.writeAsString('restored bytes');
      await fixture.mount();
      await fixture.expectColor(Colors.green);
      expect(fixture.scopeHolds, 0);
      expect(await fixture.source.readAsString(), 'restored bytes');
    });
  });

  testWidgets('another device copy uses app storage and needs no folder lease',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      await fixture.db.insert('items',
          {'id': 'other-device', 'name': 'Other device', 'is_folder': 1});
      await fixture.db.update('items', {'parent_id': 'other-device'},
          where: 'id = ?', whereArgs: ['root']);
      final downloaded = await File(await ModelItem.getPathForItem('file'))
          .create(recursive: true);
      await downloaded.writeAsString('another device copy');
      fixture.denyAccess = true;
      await fixture.mount();
      await fixture.expectColor(Colors.green);
      await downloaded.delete();
      await fixture.mount();
      await fixture.expectColor(Colors.red);
      expect(fixture.scopeHolds, 0);
      expect(await fixture.source.readAsString(), 'source stays on device');
    });
  });

  testWidgets('file permission error is unknown and releases folder access',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      fixture.probe =
          (_, __) async => throw const FileSystemException('Permission denied');
      await fixture.mount();
      await fixture.expectColor(Colors.grey.shade400);
      expect(fixture.scopeHolds, 0);
      expect(await ModelItem.get('file'), isNotNull);
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets('late absence result cannot overwrite a newer restored file',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      // An upload holds access so this race is independent of the separate
      // missing-scope bug. Hold an older real absence observation in flight.
      fixture.scopeHolds = 1;
      await fixture.source.delete();
      final observedOldFile = Completer<void>();
      final releaseOldFile = Completer<void>();
      fixture.gates.add(releaseOldFile);
      fixture.probe = (file, allowed) async {
        final observed = allowed && await file.exists();
        if (!observedOldFile.isCompleted) observedOldFile.complete();
        await releaseOldFile.future;
        return observed;
      };
      await fixture.mount(
          status: TaskStatus(
              task: ItemTask.download.value,
              progress: 50,
              state: TransferTaskState.running));
      await fixture.waitUntil(() => observedOldFile.isCompleted);
      fixture.probe = null;
      await fixture.source.writeAsString('source stays on device');
      await fixture.mount();
      await fixture.expectColor(Colors.green);
      releaseOldFile.complete();
      await fixture
          .waitUntil(() => fixture.probesStarted == fixture.probesCompleted);
      await fixture.pump();
      expect(fixture.color, Colors.green);
      fixture.scopeHolds--;
      expect(fixture.scopeHolds, 0);
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);

  testWidgets(
      'disposal during a file check releases access without updating UI',
      (tester) async {
    await _withPresenceFixture(tester, (fixture) async {
      final entered = Completer<void>();
      final release = Completer<void>();
      fixture.gates.add(release);
      fixture.probe = (_, allowed) async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
        return allowed;
      };
      await fixture.mount();
      await fixture.waitUntil(() => entered.isCompleted);
      await tester.pumpWidget(const SizedBox.shrink());
      release.complete();
      await fixture.waitUntil(() =>
          fixture.probesStarted == fixture.probesCompleted &&
          fixture.scopeHolds == 0);
      expect(fixture.scopeHolds, 0);
      expect(tester.takeException(), isNull);
    });
  }, skip: !Platform.isMacOS && !Platform.isIOS);
}

Future<void> _withPresenceFixture(WidgetTester tester,
    Future<void> Function(_PresenceFixture fixture) body) async {
  await tester.runAsync(() async {
    final directory = await Directory.systemTemp.createTemp('fife-presence-');
    final source = await File('${directory.path}/selected/file.txt')
        .create(recursive: true);
    await source.writeAsString('source stays on device');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    const storage = MethodChannel('com.jeerovan.fife/channel_storage');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    final db = await StorageSqlite.instance.database;
    // Native runs use a separately guarded app/container. Reset only its
    // fixture database between cases when the native path provider is active.
    await StorageSqlite.instance.clearDb();
    ModelSetting.settingJson = {AppString.deviceHash.string: 'device'};
    await db.insert(
        'settings', {'id': AppString.deviceHash.string, 'value': 'device'});
    await db
        .insert('items', {'id': 'device', 'name': 'device', 'is_folder': 1});
    await db.insert('items', {
      'id': 'root',
      'parent_id': 'device',
      'root_id': 'root',
      'name': 'selected',
      'path': source.parent.path,
      'bookmark': 'fixture-bookmark',
      'is_folder': 1,
    });
    await db.insert('items', {
      'id': 'file',
      'parent_id': 'root',
      'root_id': 'root',
      'name': 'file.txt',
      'file_hash': 'uploaded-content',
    });
    await db.insert('files', {'id': 'uploaded-content', 'uploaded_at': 100});
    final fixture = _PresenceFixture(tester, source, db);
    messenger.setMockMethodCallHandler(storage, (call) async {
      switch (call.method) {
        case 'startAccessing':
          fixture.accessAttempts++;
          if (fixture.denyAccess) {
            throw PlatformException(code: fixture.accessError);
          }
          fixture.scopeHolds++;
          return fixture.resolvedPath ?? source.parent.path;
        case 'stopAccessing':
          fixture.scopeHolds--;
          expect(fixture.scopeHolds, greaterThanOrEqualTo(0));
          return true;
        default:
          throw StateError('Unexpected folder operation');
      }
    });
    final previousIo = IOOverrides.current;
    // Flutter frame callbacks run in the binding's zone. A zone-only override
    // would miss the actual row render and incorrectly pass this regression.
    IOOverrides.global = _ScopedOverrides(fixture, previousIo);
    try {
      await body(fixture);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final gate in fixture.gates) {
        if (!gate.isCompleted) gate.complete();
      }
      await fixture.pump();
      await fixture
          .waitUntil(() => fixture.probesStarted == fixture.probesCompleted);
      IOOverrides.global = previousIo;
      await StorageSqlite.instance.close();
      ModelSetting.clear();
      messenger.setMockMethodCallHandler(paths, null);
      messenger.setMockMethodCallHandler(storage, null);
      fixture.selected.dispose();
      fixture.multiSelect.dispose();
      await directory.delete(recursive: true);
    }
  });
}

class _PresenceFixture {
  _PresenceFixture(this.tester, this.source, this.db);
  final WidgetTester tester;
  final File source;
  final Database db;
  final selected = ValueNotifier<Set<ModelItem>>({});
  final multiSelect = ValueNotifier(false);
  int scopeHolds = 0;
  bool denyAccess = false;
  String accessError = 'ACCESS_DENIED';
  String? resolvedPath;
  int accessAttempts = 0;
  int probesStarted = 0;
  int probesCompleted = 0;
  Future<bool> Function(File, bool)? probe;
  final gates = <Completer<void>>[];

  Future<void> mount({TaskStatus? status, String itemId = 'file'}) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: FileListItem(
          key: const ValueKey('presence-row'),
          item: (await ModelItem.get(itemId))!,
          taskStatus: status,
          selectedItemsNotifier: selected,
          isMultiSelectNotifier: multiSelect,
          onTap: () {},
          onLongPress: () {},
        ),
      ),
    ));
  }

  Color? get color {
    final badge = find.descendant(
        of: find.byKey(const ValueKey('presence-row')),
        matching: find.byWidgetPredicate((widget) =>
            widget is Container &&
            widget.constraints?.maxWidth == 12 &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle));
    return (tester.widget<Container>(badge).decoration as BoxDecoration).color;
  }

  Future<void> pump() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> expectColor(Color expected) async {
    // Allow a refresh to complete even if the previous rendered state already
    // happens to match the new expectation (notably when upload ends).
    await pump();
    await pump();
    // Grey is also the initial loading color. Wait for the row's cloud-state
    // spinner to disappear so an unknown-state assertion cannot dispose its
    // SQLite fixture while the presence check still has pending reads.
    bool ready() =>
        color == expected &&
        find
            .descendant(
                of: find.byKey(const ValueKey('presence-row')),
                matching: find.byType(CircularProgressIndicator))
            .evaluate()
            .isEmpty;
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
      await pump();
    }
    expect(ready(), isTrue,
        reason: 'File state must finish loading before fixture teardown');
    expect(color, expected,
        reason: 'Folder leases: $scopeHolds; file probes: '
            '$probesStarted started, $probesCompleted completed');
  }

  Future<void> expectFolderWarning(bool expected) async {
    await pump();
    await waitUntil(() =>
        find.byType(CircularProgressIndicator).evaluate().isEmpty &&
        find.byIcon(LucideIcons.alertCircle).evaluate().isNotEmpty == expected);
    expect(find.byIcon(LucideIcons.alertCircle),
        expected ? findsOneWidget : findsNothing);
    expect(tester.takeException(), isNull);
  }

  Future<void> waitUntil(bool Function() ready) async {
    final elapsed = Stopwatch()..start();
    while (!ready() && elapsed.elapsed < const Duration(seconds: 10)) {
      await pump();
    }
    expect(ready(), isTrue);
  }
}

final class _ScopedOverrides extends IOOverrides {
  _ScopedOverrides(this.fixture, this.parent);
  final _PresenceFixture fixture;
  final IOOverrides? parent;

  @override
  File createFile(String path) {
    IOOverrides.global = parent;
    try {
      final file = File(path);
      // Model an existing file outside the iOS sandbox: permission is held
      // only for the duration of an explicit folder-access lease.
      return path == fixture.source.path && (Platform.isIOS || Platform.isMacOS)
          ? _ScopedFile(file, fixture)
          : file;
    } finally {
      IOOverrides.global = this;
    }
  }
}

class _ScopedFile extends Fake implements File {
  _ScopedFile(this.file, this.fixture);
  final File file;
  final _PresenceFixture fixture;

  @override
  String get path => file.path;

  @override
  Future<bool> exists() async {
    fixture.probesStarted++;
    final allowed = fixture.scopeHolds > 0;
    final probe = fixture.probe;
    try {
      return probe != null
          ? await probe(file, allowed)
          : allowed && await file.exists();
    } finally {
      fixture.probesCompleted++;
    }
  }
}
