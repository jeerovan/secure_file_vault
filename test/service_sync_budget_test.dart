import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_sync_budget.dart';
import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:file_vault_bb/utils/utils_transfer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SyncBudget budget({Duration Function()? elapsed, int maxScanItems = 256}) {
    final value = SyncBudget(
        deadline: DateTime.now().add(const Duration(seconds: 20)),
        elapsed: elapsed,
        maxScanItems: maxScanItems);
    addTearDown(value.dispose);
    return value;
  }

  test('deadline includes earlier elapsed time and aborts I/O exactly once',
      () async {
    var elapsed = Duration.zero;
    var aborts = 0;
    final value = budget(elapsed: () => elapsed);
    value.onCancel(() => aborts++);
    await value.run(() async {
      expect(SyncBudget.current, same(value));
      SyncBudget.check();
      elapsed = const Duration(seconds: 21);
      expect(SyncBudget.check, throwsA(isA<BackgroundSyncInterrupted>()));
      value.cancel('expiration');
      expect(aborts, 1);
    });
    expect(SyncBudget.current, isNull);
    SyncBudget.check(); // Foreground work remains unlimited.
  });

  test('insufficient part budget rejects work before starting it', () async {
    final value = budget(elapsed: () => const Duration(seconds: 17));
    await value.run(() async {
      expect(() => SyncBudget.check(reserve: const Duration(seconds: 5)),
          throwsA(isA<BackgroundSyncInterrupted>()));
    });
  });

  test('part estimate is conservative for unknown, slow, and invalid rates',
      () {
    const bytes = 25 * 1024 * 1024;
    expect(TransferConcurrencyPolicy.estimatePartDuration(bytes),
        const Duration(seconds: 27));
    expect(
        TransferConcurrencyPolicy.estimatePartDuration(bytes,
            observedBytesPerSecond: 0),
        const Duration(seconds: 27));
    expect(
        TransferConcurrencyPolicy.estimatePartDuration(bytes,
            observedBytesPerSecond: 2 * 1024 * 1024),
        const Duration(seconds: 27));
    expect(TransferConcurrencyPolicy.estimatePartDuration(0),
        const Duration(seconds: 2));
    expect(TransferConcurrencyPolicy.estimatePartDuration(-1),
        const Duration(seconds: 2));
    expect(
        TransferConcurrencyPolicy.estimatePartDuration(bytes,
            observedBytesPerSecond: 20 * 1024 * 1024),
        const Duration(seconds: 5));
  });

  test('expiration awaits execution unwind before closing storage', () async {
    final value = budget();
    final stopped = Completer<void>();
    final events = <String>[];
    value.onCancel(stopped.complete);
    final result = value.run(() => runBackgroundWorkerSafely(
          task: () async {
            await stopped.future;
            try {
              SyncBudget.check();
            } finally {
              events.add('rollback');
            }
            return true;
          },
          cleanupActions: [
            BackgroundCleanupAction('storage', () => events.add('close'))
          ],
          onError: (_, __, ___) {},
        ));
    value.cancel('expiration');
    expect(await result, isFalse);
    expect(events, ['rollback', 'close']);
  });

  test('oversized scan is partial and foreground still sees all children',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('fife-bounded-scan-');
    addTearDown(() => directory.delete(recursive: true));
    for (var i = 0; i < 5; i++) {
      await File('${directory.path}/$i.txt').writeAsString('fixture');
    }
    final limited = await budget(maxScanItems: 3)
        .run(() => ReconciliationService.inspectSource(directory.path));
    expect(limited.status, ReconciliationStatus.partial);
    final full = await ReconciliationService.inspectSource(directory.path);
    expect(full.status, ReconciliationStatus.completed);
    expect(full.relativePaths, hasLength(5));
  });

  test('expiration aborts a stalled download and closes its output', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final directory =
        await Directory.systemTemp.createTemp('fife-stalled-download-');
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(() => server.close(force: true));
    final value = budget();
    final received = Completer<void>();
    final subscription = server.listen((request) {
      received.complete(); // Deliberately leave the response open.
    });
    addTearDown(subscription.cancel);
    final target = File('${directory.path}/output.partial');
    final result = value.run(() => downloadFileStream(
          url: 'http://127.0.0.1:${server.port}/fixture',
          headers: null,
          fileOut: target.openWrite(),
          onProgress: null,
        ));
    await received.future;
    value.cancel('expiration');
    expect(
        (await result.timeout(const Duration(seconds: 2))).succeeded, isFalse);
    expect(await target.readAsBytes(), isEmpty);
    await target.rename('${directory.path}/closed.partial');
  });

  test('expiration aborts a stalled upload without an unhandled response error',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final directory =
        await Directory.systemTemp.createTemp('fife-stalled-upload-');
    addTearDown(() => directory.delete(recursive: true));
    addTearDown(() => server.close(force: true));
    addTearDown(AppHttpClients.closeAll);
    final file = await File('${directory.path}/fixture')
        .writeAsBytes(List.filled(65536, 65));
    final value = budget();
    final received = Completer<void>();
    final subscription = server.listen((request) {
      request.listen((_) {}, onDone: received.complete);
    });
    addTearDown(subscription.cancel);
    value.onCancel(AppHttpClients.closeAll);
    final result = value.run(() => uploadFileStream(
          method: 'POST',
          file: file,
          headers: null,
          url: 'http://127.0.0.1:${server.port}/fixture',
        ));
    await received.future;
    value.cancel('expiration');
    expect(
        (await result.timeout(const Duration(seconds: 2))).succeeded, isFalse);
  });
}
