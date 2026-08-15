import 'dart:io';

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
    final directory = await Directory.systemTemp.createTemp('fife-upload-');
    final source = File('${directory.path}/source');
    await source.writeAsBytes([1, 2, 3]);
    try {
      final result = await uploadFileStream(
        method: 'PUT',
        file: source,
        url: 'http://${server.address.host}:${server.port}/file',
        headers: null,
        timeout: const Duration(milliseconds: 30),
      );
      expect(result.succeeded, isFalse);
      expect(result.failureKind, UploadFailureKind.transport);
      expect(result.isRetryable, isTrue);
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });

  test('upload streams complete file and reports monotonic progress', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var received = 0;
    server.listen((request) async {
      await for (final chunk in request) {
        received += chunk.length;
      }
      request.response
        ..statusCode = HttpStatus.ok
        ..write('{}');
      await request.response.close();
    });
    final directory = await Directory.systemTemp.createTemp('fife-stream-');
    final source = File('${directory.path}/source');
    const size = 512 * 1024;
    await source.writeAsBytes(List<int>.filled(size, 7));
    final progress = <int>[];
    try {
      final result = await uploadFileStream(
        method: 'PUT',
        file: source,
        url: 'http://${server.address.host}:${server.port}/file',
        headers: null,
        onProgress: (sent, total) => progress.add(sent),
      );

      expect(result.succeeded, isTrue);
      expect(received, size);
      expect(progress, isNotEmpty);
      expect(progress.last, size);
      for (var index = 1; index < progress.length; index++) {
        expect(progress[index], greaterThan(progress[index - 1]));
      }
    } finally {
      await server.close(force: true);
      await directory.delete(recursive: true);
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
