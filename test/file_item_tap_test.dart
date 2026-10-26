import 'dart:io';

import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/services/service_file_viewer.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'item_selection_actions_test.dart' show withSelectionFixture;

class TestFileViewer extends FileViewerPlatform {
  FileViewResult result = FileViewResult.unsupported;
  final paths = <String>[];
  Future<FileViewResult> Function(String)? handle;
  Future<void> Function()? onCancel;
  int cancels = 0;

  @override
  Future<FileViewResult> open(String path) async {
    paths.add(path);
    return handle == null ? result : await handle!(path);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    await onCancel?.call();
  }
}

void main() {
  late FileViewerPlatform previous;
  late TestFileViewer viewer;
  setUp(() {
    previous = FileViewerPlatform.instance;
    viewer = TestFileViewer();
    FileViewerPlatform.instance = viewer;
  });
  tearDown(() => FileViewerPlatform.instance = previous);

  for (final search in [false, true]) {
    testWidgets(
        '${search ? "Search" : "Explorer"}: tap uses the resolved local bookmark, not the missing old path',
        (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.createCopy('local');
        final moved = await fixture.source
            .rename('${fixture.directory.path}/moved-source');
        fixture.resolvedRootPath = moved.path;
        viewer.handle = (path) async {
          expect(path, '${moved.path}/local-sample.txt');
          expect(await File(path).readAsString(), 'preserve this content');
          expect(fixture.scopeHolds, greaterThan(0));
          return FileViewResult.unsupported;
        };
        await fixture.mount(search: search);
        await tester.tap(find.byKey(const ValueKey('local')));
        await fixture.waitFor(() =>
            viewer.paths.isNotEmpty ||
            find.text('Long press to download').evaluate().isNotEmpty);
        expect(viewer.paths, ['${moved.path}/local-sample.txt']);
        await fixture.waitFor(() => find
            .text('No supported application to view this file.')
            .evaluate()
            .isNotEmpty);
        expect(find.text('Long press to download'), findsNothing);
        await fixture.waitFor(() => fixture.accessesReleased);
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);

    for (final remote in [false, true]) {
      final id = remote ? 'remote' : 'local';
      final label = '${search ? "Search" : "Explorer"} $id';
      for (final result in [
        FileViewResult.opened,
        FileViewResult.unsupported,
        FileViewResult.denied,
        FileViewResult.failed,
        FileViewResult.cancelled,
      ]) {
        testWidgets('$label: present file handles native $result',
            (tester) async {
          viewer.result = result;
          await withSelectionFixture(tester, (fixture) async {
            final file = await fixture.createCopy(id);
            await fixture.mount(search: search, remote: remote);
            final db = await StorageSqlite.instance.database;
            final before = await db.query('items', orderBy: 'id');
            await tester.tap(find.byKey(ValueKey(id)));
            await fixture.waitFor(() => viewer.paths.isNotEmpty);
            await fixture.waitFor(() => fixture.accessesReleased);
            for (var i = 0; i < 3; i++) {
              await fixture.pump();
            }
            expect(viewer.paths, [file.path]);
            final expected = switch (result) {
              FileViewResult.unsupported =>
                'No supported application to view this file.',
              FileViewResult.denied =>
                'Unable to access this file. Check its folder permissions and try again.',
              FileViewResult.failed =>
                'Unable to open this file. Please try again.',
              _ => null,
            };
            if (expected != null) expect(find.text(expected), findsOneWidget);
            expect(find.text('Long press to download'), findsNothing);
            expect(await file.readAsString(), 'preserve this content');
            expect(await db.query('items', orderBy: 'id'), before);
            expect(await db.query('item_tasks'), isEmpty);
          });
        });
      }

      for (final backedUp in [true, false]) {
        testWidgets('$label: missing file requires a completed cloud backup',
            (tester) async {
          await withSelectionFixture(tester, (fixture) async {
            final db = await StorageSqlite.instance.database;
            if (!backedUp) {
              await db.update('files', {'uploaded_at': 0},
                  where: 'id = ?', whereArgs: ['$id-content']);
            }
            await fixture.mount(search: search, remote: remote);
            await tester.tap(find.byKey(ValueKey(id)));
            await fixture.waitFor(() => find
                .text(backedUp
                    ? 'Long press to download'
                    : 'This file is not available on this device or in a completed backup.')
                .evaluate()
                .isNotEmpty);
            expect(viewer.paths, isEmpty);
            expect(await db.query('item_tasks'), isEmpty);
          });
        });
      }

      testWidgets('$label: file disappears during native open', (tester) async {
        await withSelectionFixture(tester, (fixture) async {
          final file = await fixture.createCopy(id);
          viewer.handle = (_) async {
            await file.delete();
            return FileViewResult.missing;
          };
          await fixture.mount(search: search, remote: remote);
          await tester.tap(find.byKey(ValueKey(id)));
          await fixture.waitFor(
              () => find.text('Long press to download').evaluate().isNotEmpty);
          expect(viewer.paths, [file.path]);
        });
      });

      testWidgets(
          '$label: native missing response cannot mislabel present data',
          (tester) async {
        viewer.result = FileViewResult.missing;
        await withSelectionFixture(tester, (fixture) async {
          final file = await fixture.createCopy(id);
          await fixture.mount(search: search, remote: remote);
          await tester.tap(find.byKey(ValueKey(id)));
          await fixture.waitFor(() => find
              .text(
                  'Unable to access this file. Check its folder permissions and try again.')
              .evaluate()
              .isNotEmpty);
          expect(await file.exists(), isTrue);
          expect(find.text('Long press to download'), findsNothing);
        });
      });

      testWidgets('$label: empty file still reaches the native viewer',
          (tester) async {
        await withSelectionFixture(tester, (fixture) async {
          final file = await fixture.createCopy(id);
          await file.writeAsBytes([]);
          await fixture.mount(search: search, remote: remote);
          await tester.tap(find.byKey(ValueKey(id)));
          await fixture.waitFor(() => find
              .text('No supported application to view this file.')
              .evaluate()
              .isNotEmpty);
          expect(viewer.paths, [file.path]);
          expect(await file.length(), 0);
        });
      });

      testWidgets('$label: repeat taps do not duplicate a held viewer',
          (tester) async {
        await withSelectionFixture(tester, (fixture) async {
          await fixture.createCopy(id);
          final finish = fixture.gate();
          viewer.handle = (_) async {
            await finish.future;
            return FileViewResult.opened;
          };
          await fixture.mount(search: search, remote: remote);
          await tester.tap(find.byKey(ValueKey(id)));
          await fixture.waitFor(() => viewer.paths.length == 1);
          if (!remote && (Platform.isIOS || Platform.isMacOS)) {
            expect(fixture.scopeHolds, greaterThan(0));
          }
          await tester.tap(find.byKey(ValueKey(id)));
          await fixture.pump();
          expect(viewer.paths.length, 1);
          finish.complete();
          await fixture.waitFor(() => fixture.accessesReleased);
        });
      });

      testWidgets('$label: selection taps do not open a file', (tester) async {
        await withSelectionFixture(tester, (fixture) async {
          await fixture.createCopy(id);
          await fixture.mount(search: search, remote: remote);
          await fixture.select(id);
          await tester.tap(find.byKey(ValueKey(id)));
          await fixture.pump();
          expect(viewer.paths, isEmpty);
        });
      });
    }

    testWidgets(
        '${search ? "Search" : "Explorer"}: changed ancestry cannot open an old source',
        (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.createCopy('local');
        await fixture.mount(search: search);
        await fixture.waitFor(() => fixture.accessesReleased);
        fixture.beforeAccess = () async {
          fixture.beforeAccess = null;
          final db = await StorageSqlite.instance.database;
          await db.update('items', {'parent_id': 'other-device'},
              where: 'id = ?', whereArgs: ['local-root']);
        };
        await tester.tap(find.byKey(const ValueKey('local')));
        await fixture.waitFor(() => find
            .text(
                'This file is not available on this device or in a completed backup.')
            .evaluate()
            .isNotEmpty);
        expect(viewer.paths, isEmpty);
        await fixture.waitFor(() => fixture.accessesReleased);
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);

    testWidgets(
        '${search ? "Search" : "Explorer"}: backgrounding during access prevents late presentation',
        (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.createCopy('local');
        await fixture.mount(search: search);
        await fixture.waitFor(() => fixture.accessesReleased);
        final entered = fixture.gate();
        final resume = fixture.gate();
        fixture.beforeAccess = () async {
          if (!entered.isCompleted) entered.complete();
          await resume.future;
        };
        await tester.tap(find.byKey(const ValueKey('local')));
        await entered.future;
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        try {
          resume.complete();
          await fixture.waitFor(() => fixture.accessesReleased);
          expect(viewer.paths, isEmpty);
          expect(find.text('Long press to download'), findsNothing);
        } finally {
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
        }
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);

    testWidgets(
        '${search ? "Search" : "Explorer"}: denied bookmark is not missing',
        (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.createCopy('local');
        await fixture.mount(search: search);
        await fixture.waitFor(() => fixture.accessesReleased);
        fixture.denyAccess = true;
        await tester.tap(find.byKey(const ValueKey('local')));
        await fixture.waitFor(() => find
            .text(
                'Unable to access this file. Check its folder permissions and try again.')
            .evaluate()
            .isNotEmpty);
        expect(viewer.paths, isEmpty);
        expect(find.text('Long press to download'), findsNothing);
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);

    testWidgets(
        '${search ? "Search" : "Explorer"}: navigation during access prevents late presentation',
        (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.createCopy('local');
        await fixture.mount(search: search);
        await fixture.waitFor(() => fixture.accessesReleased);
        final entered = fixture.gate();
        final resume = fixture.gate();
        fixture.beforeAccess = () async {
          if (!entered.isCompleted) entered.complete();
          await resume.future;
        };
        await tester.tap(find.byKey(const ValueKey('local')));
        await entered.future;
        final context = tester.element(find.byKey(const ValueKey('local')));
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Another screen'))));
        await fixture.pump();
        resume.complete();
        await fixture.waitFor(() => fixture.accessesReleased);
        expect(viewer.paths, isEmpty);
        expect(find.text('Another screen'), findsOneWidget);
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);

    testWidgets(
        '${search ? "Search" : "Explorer"}: disposal cancels late presentation',
        (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.createCopy('local');
        await fixture.mount(search: search);
        await fixture.waitFor(() => fixture.accessesReleased);
        final entered = fixture.gate();
        final resume = fixture.gate();
        fixture.beforeAccess = () async {
          if (!entered.isCompleted) entered.complete();
          await resume.future;
        };
        await tester.tap(find.byKey(const ValueKey('local')));
        await entered.future;
        await tester.pumpWidget(const SizedBox.shrink());
        resume.complete();
        await fixture.waitFor(() => fixture.accessesReleased);
        expect(viewer.paths, isEmpty);
      });
    }, skip: !Platform.isMacOS && !Platform.isIOS);

    testWidgets(
        '${search ? "Search" : "Explorer"}: expiry cancels the viewer and releases access',
        (tester) async {
      await withSelectionFixture(tester, (fixture) async {
        await fixture.createCopy('local');
        final finish = fixture.gate();
        viewer.handle = (_) async {
          await finish.future;
          return FileViewResult.cancelled;
        };
        viewer.onCancel = () async {
          if (!finish.isCompleted) finish.complete();
        };
        await fixture.mount(search: search);
        await tester.tap(find.byKey(const ValueKey('local')));
        await fixture.waitFor(() => viewer.paths.isNotEmpty);
        try {
          SessionWork.invalidate('file-viewer-expired');
          await fixture.waitFor(() => fixture.accessesReleased);
          expect(viewer.cancels, 1);
          expect(find.text('Long press to download'), findsNothing);
        } finally {
          SessionWork.complete('file-viewer-expired');
        }
      });
    });
  }
}
