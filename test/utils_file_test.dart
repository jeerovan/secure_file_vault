import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FileSplitter', () {
    const mib = 1024 * 1024;
    for (final sample in [
      (size: 0, expected: <int>[]),
      (size: 1, expected: <int>[1]),
      (size: 25 * mib, expected: <int>[25 * mib]),
      (size: 25 * mib + 1, expected: <int>[25 * mib + 1]),
      (size: 35 * mib, expected: <int>[25 * mib, 10 * mib]),
      (size: 50 * mib + 1, expected: <int>[25 * mib, 25 * mib + 1]),
    ]) {
      test('covers all ${sample.size} bytes without gaps or overlaps', () {
        final splitter = FileSplitter(fileSize: sample.size);
        expect(splitter.partSizes, sample.expected);
        var position = 0;
        for (var part = 1; part <= splitter.partSizes.length; part++) {
          final range = splitter.getStartEndIndexForPart(part);
          expect(range.start, position);
          expect(range.end, greaterThan(range.start));
          position = range.end;
        }
        expect(position, sample.size);
      });
    }
  });

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

  for (final size in [0, 1, 65553, 2 * 1024 * 1024 + 31]) {
    test('PUT and chunked GET preserve $size binary bytes', () async {
      final bytes = Uint8List.fromList(
          List<int>.generate(size, (i) => (i * 17 + 11) & 255));
      final stored = BytesBuilder(copy: false);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        if (request.method == 'PUT') {
          await for (final chunk in request) {
            stored.add(chunk);
          }
          request.response.statusCode = HttpStatus.noContent;
        } else {
          final content = stored.toBytes();
          for (var start = 0; start < content.length; start += 4093) {
            final end = (start + 4093).clamp(0, content.length);
            request.response.add(content.sublist(start, end));
          }
        }
        await request.response.close();
      });
      final directory =
          await Directory.systemTemp.createTemp('fife-roundtrip-');
      final source = File('${directory.path}/source')..writeAsBytesSync(bytes);
      final restored = File('${directory.path}/restored');
      final url = 'http://${server.address.host}:${server.port}/release.bin';
      final progress = <int>[];
      try {
        final upload = await uploadFileStream(
            method: 'PUT', file: source, url: url, headers: null);
        expect(upload.succeeded, isTrue);
        expect(stored.length, size);
        final download = await downloadFileStream(
            url: url,
            headers: null,
            fileOut: restored.openWrite(),
            onProgress: (received, total) => progress.add(received));
        expect(download.succeeded, isTrue);
        expect(await restored.length(), size);
        expect(sha256.convert(await restored.readAsBytes()),
            sha256.convert(bytes));
        if (size > 0) {
          expect(progress.last, size);
          for (var i = 1; i < progress.length; i++) {
            expect(progress[i], greaterThan(progress[i - 1]));
          }
        }
      } finally {
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    });
  }

  for (final status in [401, 403, 404, 429, 503]) {
    test('HTTP $status download never writes the error body as file data',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response
          ..statusCode = status
          ..write('provider error, not file bytes');
        await request.response.close();
      });
      final directory =
          await Directory.systemTemp.createTemp('fife-http-failure-');
      final restored = File('${directory.path}/restored');
      try {
        final result = await downloadFileStream(
          url: 'http://${server.address.host}:${server.port}/release.bin',
          headers: null,
          fileOut: restored.openWrite(),
          onProgress: null,
        );
        expect(result.succeeded, isFalse);
        expect(result.statusCode, status);
        expect(result.isRetryable, status != 404);
        expect(await restored.length(), 0);
      } finally {
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    });
  }

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

  test('remote deletion removes a downloaded file inside the managed root',
      () async {
    final directory = await Directory.systemTemp.createTemp('fife-delete-');
    final managedRoot = Directory('${directory.path}/FiFe')..createSync();
    final downloaded = File('${managedRoot.path}/folder/file.bin')
      ..createSync(recursive: true)
      ..writeAsStringSync('downloaded');
    try {
      expect(
        await deleteManagedFileIfExists(
          filePath: downloaded.path,
          managedRootPath: managedRoot.path,
        ),
        isTrue,
      );
      expect(await downloaded.exists(), isFalse);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('remote deletion accepts an already missing managed file', () async {
    final directory = await Directory.systemTemp.createTemp('fife-delete-');
    final managedRoot = Directory('${directory.path}/FiFe')..createSync();
    try {
      expect(
        await deleteManagedFileIfExists(
          filePath: '${managedRoot.path}/missing.bin',
          managedRootPath: managedRoot.path,
        ),
        isTrue,
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('remote deletion preserves user-owned files outside managed storage',
      () async {
    final directory = await Directory.systemTemp.createTemp('fife-delete-');
    final managedRoot = Directory('${directory.path}/FiFe')..createSync();
    final external = File('${directory.path}/external.bin')
      ..writeAsStringSync('user-owned');
    try {
      expect(
        await deleteManagedFileIfExists(
          filePath: external.path,
          managedRootPath: managedRoot.path,
        ),
        isFalse,
      );
      expect(await external.readAsString(), 'user-owned');
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('remote file deletion never recursively removes a directory', () async {
    final directory = await Directory.systemTemp.createTemp('fife-delete-');
    final managedRoot = Directory('${directory.path}/FiFe')..createSync();
    final unexpectedDirectory = Directory('${managedRoot.path}/file.bin')
      ..createSync();
    try {
      await expectLater(
        deleteManagedFileIfExists(
          filePath: unexpectedDirectory.path,
          managedRootPath: managedRoot.path,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await unexpectedDirectory.exists(), isTrue);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
