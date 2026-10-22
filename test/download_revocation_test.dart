import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/services/service_session_cleanup.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';
import 'support/transfer_api.dart';

class PausedRename extends Fake implements File {
  PausedRename(this.file, this.entered, this.release);
  final File file;
  final Completer<void> entered;
  final Completer<void> release;
  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) =>
      file.open(mode: mode);
  @override
  Stream<List<int>> openRead([int? start, int? end]) =>
      file.openRead(start, end);
  @override
  IOSink openWrite(
          {FileMode mode = FileMode.write, Encoding encoding = utf8}) =>
      file.openWrite(mode: mode, encoding: encoding);
  @override
  Future<File> rename(String destination) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return file.rename(destination);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('cleanup and final download publication cannot overlap', () async {
    final fixture = await SyncFixture.create();
    final renameEntered = Completer<void>();
    final allowRename = Completer<void>();
    final secureDeletionEntered = Completer<void>();
    final allowSecureDeletion = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        const MethodChannel('purchases_flutter'), (call) async => false);
    try {
      expect(await SessionCleanup.instance.resume(), isTrue);
      final api = TransferApi();
      await api.run(() async {
        await fixture.text('restore.txt', 'revoked plaintext');
        await fixture.scan();
        final item = await fixture.item('restore.txt');
        for (var step = 0; step < 8; step++) {
          final task = await ModelItemTask.get(item.id);
          if (task == null) break;
          await TaskManager().checkInitUpload(task);
        }
        expect(await ModelItemTask.get(item.id), isNull);
        final destination = File('${fixture.source.path}/restore.txt');
        await destination.delete();
        await ModelItemTask.addTask(item.id, ItemTask.download.value);
        final task = (await ModelItemTask.get(item.id))!;
        messenger.setMockMethodCallHandler(SyncFixture.secure, (call) async {
          final key = call.arguments?['key'] as String?;
          switch (call.method) {
            case 'read':
              return fixture.secrets[key];
            case 'readAll':
              return Map<String, String>.of(fixture.secrets);
            case 'containsKey':
              return fixture.secrets.containsKey(key);
            case 'write':
              fixture.secrets[key!] = call.arguments['value'] as String;
            case 'delete':
              fixture.secrets.remove(key);
            case 'deleteAll':
              if (!secureDeletionEntered.isCompleted) {
                secureDeletionEntered.complete();
              }
              await allowSecureDeletion.future;
              fixture.secrets.clear();
          }
          return null;
        });
        await IOOverrides.runZoned(() async {
          Object? downloadError;
          final download =
              SessionWork.run(() => TaskManager().checkInitDownload(task))
                  .catchError((Object error) {
            downloadError = error;
          });
          Future<bool>? cleanup;
          try {
            await renameEntered.future.timeout(const Duration(seconds: 10));
            cleanup = SessionCleanup.instance.request();
            // Let cleanup attempt its lock while the real filesystem rename is
            // paused. It must either precede publication or follow it in full.
            await Future<void>.delayed(const Duration(milliseconds: 100));
            expect(secureDeletionEntered.isCompleted, isFalse,
                reason: 'Cleanup must wait for an already publishing file');
            expect(SessionWork.active, isTrue);
            allowRename.complete();
            await secureDeletionEntered.future
                .timeout(const Duration(seconds: 10));
            expect(SessionWork.active, isFalse);
            expect(await destination.readAsString(), 'revoked plaintext');
            allowSecureDeletion.complete();
            await download.timeout(const Duration(seconds: 10));
            expect(await cleanup, isTrue);
            expect(downloadError, anyOf(isNull, isA<SessionInvalidated>()));
            // A completed external download is user data and must survive;
            // no filesystem operation can still publish after invalidation.
            expect(await destination.readAsString(), 'revoked plaintext');
          } finally {
            if (!allowRename.isCompleted) allowRename.complete();
            if (!allowSecureDeletion.isCompleted) {
              allowSecureDeletion.complete();
            }
            await download;
            if (cleanup != null) await cleanup;
          }
        }, createFile: (path) {
          final real = Zone.root.run(() => File(path));
          return path.endsWith('/assembled.partial')
              ? PausedRename(real, renameEntered, allowRename)
              : real;
        });
        expect(await ModelItem.get(item.id), isNull);
      });
    } finally {
      await fixture.dispose();
      messenger.setMockMethodCallHandler(
          const MethodChannel('purchases_flutter'), null);
    }
  });

  test('revocation during a no-op startup resume still clears private data',
      () async {
    final fixture = await SyncFixture.create();
    final entered = Completer<void>(), release = Completer<void>();
    var cleanups = 0;
    final cleaner = SessionCleanup.test(
        marker: File('${fixture.directory.path}/startup-cleanup.json'),
        actions: [
          SessionCleanupAction('Clear private keys', () async {
            cleanups++;
            fixture.secrets.clear();
          })
        ]);
    Future<void>? publication;
    Future<bool>? startup, revoked, repeated;
    try {
      expect(await cleaner.resume(), isTrue);
      final originalRevision = SessionWork.revision;
      publication = cleaner.withPublication(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      startup = cleaner.resume();
      revoked = cleaner.request();
      repeated = cleaner.request();
      release.complete();
      await publication;
      expect(await startup, isTrue);
      expect(await revoked, isTrue);
      expect(await repeated, isTrue);
      expect(cleanups, 1);
      expect(fixture.secrets.isEmpty, isTrue);
      expect(SessionWork.revision, isNot(originalRevision));
    } finally {
      if (!release.isCompleted) release.complete();
      await publication;
      await startup;
      await revoked;
      await repeated;
      await fixture.dispose();
    }
  });

  test('joined cleanup requests cannot replay over a newer local session',
      () async {
    final fixture = await SyncFixture.create();
    final entered = Completer<void>(), release = Completer<void>();
    var cleanups = 0;
    final cleaner = SessionCleanup.test(
        marker: File('${fixture.directory.path}/joined-cleanup.json'),
        actions: [
          SessionCleanupAction('Clear private keys', () async {
            cleanups++;
            fixture.secrets.clear();
          })
        ]);
    Future<void>? publication;
    Future<bool>? first, joined;
    try {
      expect(await cleaner.resume(), isTrue);
      publication = cleaner.withPublication(() async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      first = cleaner.request();
      joined = cleaner.request();
      release.complete();
      await publication;
      expect(await first, isTrue);
      final currentRevision = SessionWork.revision;
      fixture.secrets['new-session-key'] = 'new-private-fixture-key';
      expect(await joined, isTrue);
      expect(cleanups, 1);
      expect(SessionWork.revision, currentRevision);
      expect(fixture.secrets.containsKey('new-session-key'), isTrue);
    } finally {
      if (!release.isCompleted) release.complete();
      await publication;
      await first;
      await joined;
      await fixture.dispose();
    }
  });

  test('independent coordinators wait for publication beyond lock timeout',
      () async {
    final fixture = await SyncFixture.create();
    final entered = Completer<void>();
    final release = Completer<void>();
    final events = <String>[];
    final marker = File('${fixture.directory.path}/shared-publication.json');
    final publisher = SessionCleanup.test(marker: marker, actions: []);
    final cleaner = SessionCleanup.test(marker: marker, actions: [
      SessionCleanupAction('Clear keys', () async {
        events.add('cleanup');
        fixture.secrets.clear();
      })
    ]);
    Future<void>? publication;
    Future<bool>? cleanup;
    try {
      expect(await publisher.resume(), isTrue);
      publication = SessionWork.run(() => publisher.withPublication(() async {
            entered.complete();
            await release.future;
            await fixture.text('completed.txt', 'committed external download');
            events.add('publication');
          }));
      await entered.future;
      cleanup = cleaner.request();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(events, isEmpty);
      expect(await cleaner.pending, isFalse);
      release.complete();
      await publication;
      expect(await cleanup, isTrue);
      expect(events, ['publication', 'cleanup']);
      expect(await File('${fixture.source.path}/completed.txt').readAsString(),
          'committed external download');
    } finally {
      if (!release.isCompleted) release.complete();
      await publication;
      await cleanup;
      await fixture.dispose();
    }
  });

  test('cleanup that wins first prevents a queued external publication',
      () async {
    final fixture = await SyncFixture.create();
    final ready = Completer<void>();
    final release = Completer<void>();
    final deleting = Completer<void>();
    final finishCleanup = Completer<void>();
    final marker = File('${fixture.directory.path}/cleanup-first.json');
    final cleaner = SessionCleanup.test(marker: marker, actions: [
      SessionCleanupAction('Clear keys', () async {
        deleting.complete();
        await finishCleanup.future;
        fixture.secrets.clear();
      })
    ]);
    Future<bool>? cleanup;
    try {
      expect(await cleaner.resume(), isTrue);
      final oldWork = SessionWork.run(() async {
        ready.complete();
        await release.future;
        await cleaner.withPublication(() async =>
            fixture.text('must-not-exist.txt', 'retired plaintext'));
      });
      final rejected = expectLater(oldWork, throwsA(isA<SessionInvalidated>()));
      await ready.future;
      cleanup = cleaner.request();
      await deleting.future;
      release.complete();
      await rejected;
      expect(await File('${fixture.source.path}/must-not-exist.txt').exists(),
          isFalse);
    } finally {
      if (!release.isCompleted) release.complete();
      if (!finishCleanup.isCompleted) finishCleanup.complete();
      await cleanup;
      await fixture.dispose();
    }
  });
}
