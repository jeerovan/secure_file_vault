import 'dart:io';
import 'dart:typed_data';

import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadStreamResult', () {
    test('classifies transient failures as retryable', () {
      for (final status in [401, 403, 429, 500, 503]) {
        final result = DownloadStreamResult.httpFailure(status);

        expect(result.succeeded, isFalse);
        expect(result.isRetryable, isTrue, reason: 'status $status');
      }

      expect(
        const DownloadStreamResult.transportFailure().isRetryable,
        isTrue,
      );
    });

    test('does not classify confirmed absence as retryable', () {
      final result = DownloadStreamResult.httpFailure(404);

      expect(result.succeeded, isFalse);
      expect(result.failureKind, DownloadFailureKind.notFound);
      expect(result.isRetryable, isFalse);
    });
  });

  group('UploadFileResult', () {
    test('classifies transient provider failures as retryable', () {
      for (final status in [401, 403, 408, 429, 500, 503]) {
        expect(
          UploadFileResult.httpFailure(status, const {}).isRetryable,
          isTrue,
          reason: 'status $status',
        );
      }
    });

    test('classifies other client errors as blocked', () {
      final result = UploadFileResult.httpFailure(413, const {});
      expect(result.isRetryable, isFalse);
      expect(result.failureKind, UploadFailureKind.otherHttp);
    });
  });

  test('download timeout returns retryable transport failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        request.response.write('late');
        await request.response.close();
      } catch (_) {}
    });
    final directory = await Directory.systemTemp.createTemp('fife-timeout-');
    final sink = File('${directory.path}/download').openWrite();
    try {
      final result = await downloadFileStream(
        url: 'http://${server.address.host}:${server.port}/file',
        headers: null,
        fileOut: sink,
        onProgress: null,
        timeout: const Duration(milliseconds: 30),
      );
      expect(result.succeeded, isFalse);
      expect(result.failureKind, DownloadFailureKind.transport);
      expect(result.isRetryable, isTrue);
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('upload timeout returns retryable transport failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      try {
        await request.drain<void>();
        request.response.write('late');
        await request.response.close();
      } catch (_) {}
    });
    try {
      final result = await uploadFileBytes(
        method: 'PUT',
        bytes: Uint8List.fromList([1, 2, 3]),
        url: 'http://${server.address.host}:${server.port}/file',
        headers: null,
        timeout: const Duration(milliseconds: 30),
      );
      expect(result.succeeded, isFalse);
      expect(result.failureKind, UploadFailureKind.transport);
      expect(result.isRetryable, isTrue);
    } finally {
      await server.close(force: true);
    }
  });

  test('safe move never deletes a destination directory', () async {
    final directory = await Directory.systemTemp.createTemp('fife-move-');
    final source = File('${directory.path}/source')..writeAsStringSync('data');
    final destination = Directory('${directory.path}/destination')
      ..createSync();
    try {
      await expectLater(
        moveFileSafely(source.path, destination.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.exists(), isTrue);
      expect(await source.exists(), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('safe move preserves an existing destination file', () async {
    final directory = await Directory.systemTemp.createTemp('fife-move-');
    final source = File('${directory.path}/source')..writeAsStringSync('new');
    final destination = File('${directory.path}/destination')
      ..writeAsStringSync('existing');
    try {
      await expectLater(
        moveFileSafely(source.path, destination.path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await destination.readAsString(), 'existing');
      expect(await source.readAsString(), 'new');
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
