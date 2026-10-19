// Run on Samsung with the normal .env/local-account build flags and
// --dart-define=FIFE_QA_FOLDER=/storage/emulated/0/Documents/FiFe-Release-QA-...
// This uses the signed-in account and real API/bucket. It never resets them.
// Use a fresh fixture folder per run; edited versions remain for inspection.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:file_vault_bb/ui/pages/page_explorer.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_test/flutter_test.dart';

const fixtureHashes = {
  'empty.txt':
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
  'hello-unicode.txt':
      '6a0c96725e2e7f7ce7118398cd55ca23daef4337464bbb720741ab390c5d899f',
  'binary-4097.bin':
      '56e6d6ffdd545e415b8dec49fab26c4fa6398fffab11fb59bd461e73cfb78e74',
  'multipart-36MiB.bin':
      'a65286703182f0fc42e8589e2d45c060ee797f12e435b9f09475ef9da7a7faa0',
};

void report(String stage, [Map<String, Object?> details = const {}]) {
  debugPrint('FIFE_RELEASE_QA ${jsonEncode({'stage': stage, ...details})}');
}

void require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> waitFor(String description, Future<bool> Function() predicate,
    {Duration timeout = const Duration(minutes: 8)}) async {
  final watch = Stopwatch()..start();
  while (!await predicate()) {
    if (watch.elapsed > timeout) throw TimeoutException(description, timeout);
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

Future<String> hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  const rootPath = String.fromEnvironment('FIFE_QA_FOLDER');
  require(
      Platform.isAndroid &&
          RegExp(r'^/storage/emulated/0/Documents/FiFe-Release-QA-[A-Za-z0-9-]+$')
              .hasMatch(rootPath),
      'An explicit dedicated Android QA folder is required');
  final rootDirectory = Directory(rootPath);
  final backups = Directory('$rootPath/.qa-originals');
  // Restore only this test's generated sources before startup reconciliation
  // if an earlier test run was interrupted during download.
  for (final name in fixtureHashes.keys) {
    final backup = File('${backups.path}/$name');
    final original = File('$rootPath/$name');
    if (await backup.exists() && !await original.exists()) {
      await backup.rename(original.path);
    }
    require(
        await original.exists() && await hash(original) == fixtureHashes[name],
        'Fixture source mismatch: $name');
  }
  await application.main();
  unawaited(runChecks(LiveWidgetController(binding), rootDirectory, backups)
      .catchError((Object error, StackTrace stack) {
    report('failed', {'error': error.toString()});
  }));
}

Future<void> runChecks(LiveWidgetController controller, Directory rootDirectory,
    Directory backups) async {
  require(!simulateTesting() && localTesting(),
      'Requires the real local-testing account, with simulation disabled');
  require(
      isLocalTestingEmail(' JEEVAN@JEERO.ONE ') &&
          !isLocalTestingEmail('someone@example.test'),
      'Local-email classification failed');
  require(await getSignedInEmailId() == localTestEmailId,
      'The local account must already be signed in');
  require((await BackendApi().get(endpoint: '/keys'))['success'] == 1,
      'Local API did not authenticate the account');
  await waitFor('Explorer did not open',
      () async => find.byType(FilePane).evaluate().isNotEmpty);
  await waitFor('Startup sync did not finish',
      () async => !await isRecordOrSyncInProgress());
  report('preflight_passed', {'local_auth': true, 'simulation': false});

  var root = await ModelItem.syncFolderExists(rootDirectory.path);
  if (root == null) {
    // Supply the selected folder to the existing confirmation flow; all
    // reconciliation, encryption, transfer and metadata code stays unchanged.
    final dynamic explorer = controller.state(find.byType(FilePane));
    explorer.addFolderConfirm(rootDirectory.path, 'sandboxed');
    await controller.pump();
    final loc = AppLocalizations.of(controller.element(find.byType(FilePane)))!;
    await controller.tap(find.text(loc.confirm));
    await waitFor(
        'Test sync root was not registered',
        () async =>
            await ModelItem.syncFolderExists(rootDirectory.path) != null);
    root = await ModelItem.syncFolderExists(rootDirectory.path);
  }
  final qaRoot = root!;
  final expectedHashes = Map<String, String>.of(fixtureHashes);
  report('upload_started');
  var items = <ModelItem>[];
  await waitFor('Fixture discovery did not finish', () async {
    items = await ModelItem.getDisplayItems(qaRoot);
    return fixtureHashes.keys.every((name) => items.any((i) => i.name == name));
  });
  items = items.where((i) => fixtureHashes.containsKey(i.name)).toList();
  var lastReport = DateTime.now();
  await waitFor('Fixture upload did not finish', () async {
    var completed = 0;
    for (final item in items) {
      final file =
          item.fileHash == null ? null : await ModelFile.get(item.fileHash!);
      if (file != null &&
          file.uploadedAt > 0 &&
          await ModelItemTask.get(item.id) == null) {
        completed++;
      }
    }
    if (DateTime.now().difference(lastReport) > const Duration(seconds: 10)) {
      report('upload_progress', {'complete': completed, 'total': items.length});
      lastReport = DateTime.now();
    }
    return completed == fixtureHashes.length;
  });
  for (final item in items) {
    final file = (await ModelFile.get(item.fileHash!))!;
    if (item.name == 'multipart-36MiB.bin') {
      require(file.parts == 2, 'Multipart upload did not contain two parts');
    }
    if (item.name == 'empty.txt') {
      require(file.parts == 0, 'Empty file has parts');
    }
    if (item.size > 0) {
      require(file.providerId == 2, 'Unexpected upload provider');
    }
  }
  report('upload_passed', {'files': items.length, 'multipart_parts': 2});

  require(await FlutterForegroundTask.isRunningService,
      'Enable the foreground sync service before this automatic-sync check');
  final interval = await ModelSetting.getForegroundSyncIntervalMinutes();
  final oldHashes = {for (final item in items) item.id: item.fileHash};
  await File('${rootDirectory.path}/empty.txt')
      .writeAsString('Empty file now has content from the Samsung edit test.');
  final sameSize = File('${rootDirectory.path}/hello-unicode.txt');
  final originalTime = (await sameSize.stat()).modified;
  await sameSize.writeAsBytes(List<int>.filled(await sameSize.length(), 66),
      flush: true);
  await sameSize.setLastModified(originalTime);
  await File('${rootDirectory.path}/binary-4097.bin')
      .writeAsBytes(const [], flush: true);
  final largeSource = File('${rootDirectory.path}/multipart-36MiB.bin');
  final previous =
      (await largeSource.openRead(18 * 1024 * 1024, 18 * 1024 * 1024 + 1).first)
          .single;
  final large = await largeSource.open(mode: FileMode.writeOnlyAppend);
  try {
    await large.setPosition(18 * 1024 * 1024);
    await large.writeByte(previous ^ 1);
    await large.flush();
  } finally {
    await large.close();
  }
  for (final name in expectedHashes.keys) {
    expectedHashes[name] = await hash(File('${rootDirectory.path}/$name'));
    require(expectedHashes[name] != fixtureHashes[name],
        'Edit did not change the fixture: $name');
  }
  // No manual sync or reconciliation is invoked here: the native foreground
  // service must discover edits at the owner's saved interval and upload them.
  report('auto_edit_started', {
    'interval_minutes': interval,
    'files': items.length,
    'same_size_preserved_mtime': true,
  });
  await waitFor('Scheduled modified-file re-upload did not finish', () async {
    final updated = <ModelItem>[];
    for (final previous in items) {
      final current = await ModelItem.get(previous.id);
      if (current == null ||
          current.name != previous.name ||
          current.fileHash == oldHashes[previous.id]) {
        return false;
      }
      final file = current.fileHash == null
          ? null
          : await ModelFile.get(current.fileHash!);
      if (file == null ||
          file.uploadedAt <= 0 ||
          await ModelItemTask.get(current.id) != null) {
        return false;
      }
      updated.add(current);
    }
    items = updated;
    return true;
  }, timeout: Duration(minutes: interval + 8));
  for (final item in items) {
    require(
        item.size == await File('${rootDirectory.path}/${item.name}').length(),
        'Updated metadata has the wrong file length');
    final oldFile = await ModelFile.get(oldHashes[item.id]!);
    require(oldFile != null && oldFile.uploadedAt > 0,
        'Previous uploaded version metadata was lost');
    final current = (await ModelFile.get(item.fileHash!))!;
    const expectedParts = {
      'empty.txt': 1,
      'hello-unicode.txt': 1,
      'binary-4097.bin': 0,
      'multipart-36MiB.bin': 2,
    };
    require(current.parts == expectedParts[item.name],
        'Modified file has the wrong part count');
  }
  report('auto_edit_passed', {
    'files': items.length,
    'identities_preserved': true,
    'empty_transitions': true,
    'multipart_edit': true,
  });

  final serviceWasRunning = await FlutterForegroundTask.isRunningService;
  try {
    // Exercise the normal manual download with scheduled reconciliation stopped
    // while this test's source bytes are held safely in its own backup folder.
    if (serviceWasRunning) await ServiceForeground.instance.stop();
    await waitFor('Upload activity did not stop',
        () async => !await isRecordOrSyncInProgress());
    await backups.create();
    for (final name in expectedHashes.keys) {
      final source = File('${rootDirectory.path}/$name');
      final backup = File('${backups.path}/$name');
      require(!await backup.exists(), 'A fixture backup already exists');
      await source.rename(backup.path);
    }
    await waitFor('Test folder is not visible in explorer',
        () async => find.text(qaRoot.name).evaluate().isNotEmpty);
    await controller.tap(find.text(qaRoot.name).first);
    await waitFor(
        'Test file rows did not open',
        () async => items.every(
            (item) => find.byKey(ValueKey(item.id)).evaluate().isNotEmpty));
    await controller.longPress(find.byKey(ValueKey(items.first.id)));
    for (final item in items.skip(1)) {
      await controller.tap(find.byKey(ValueKey(item.id)));
    }
    final loc = AppLocalizations.of(controller.element(find.byType(FilePane)))!;
    await controller.tap(find.byTooltip(loc.download));
    report('download_started', {'files': items.length});
    await waitFor('Fixture download did not finish', () async {
      for (final item in items) {
        final file = File('${rootDirectory.path}/${item.name}');
        if (await ModelItemTask.get(item.id) != null ||
            !await file.exists() ||
            await hash(file) != expectedHashes[item.name]) {
          return false;
        }
      }
      return true;
    });
    report('download_passed', {
      'files': items.length,
      'sha256_matches': true,
      'latest_edited_version': true,
    });
  } finally {
    for (final name in expectedHashes.keys) {
      final backup = File('${backups.path}/$name');
      final original = File('${rootDirectory.path}/$name');
      if (!await backup.exists()) continue;
      if (!await original.exists()) {
        await backup.rename(original.path);
      } else if (await hash(original) == expectedHashes[name]) {
        await backup.delete();
      }
    }
    if (await backups.exists() && await backups.list().isEmpty) {
      await backups.delete();
    }
    if (serviceWasRunning) await ServiceForeground.instance.start();
  }
  report('passed', {
    'files': items.length,
    'modified_file_auto_sync': true,
    'foreground_service_restored': serviceWasRunning
  });
}
