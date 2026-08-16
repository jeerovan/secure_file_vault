import 'dart:io';
import 'dart:async';

import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:http/http.dart' as http_lib;

class FileSplitter {
  final File? file;
  final int fileSize;
  late final List<int> partSizes; // Made final for immutability

  /// Creates a FileSplitter.
  ///
  /// You must provide either [file] or [fileSize].
  /// If [file] is provided, its size is read synchronously and overrides [fileSize].
  FileSplitter({this.file, int? fileSize})
      : assert(file != null || fileSize != null,
            'Either file or fileSize must be provided.'),
        fileSize = file != null ? file.lengthSync() : fileSize! {
    partSizes = _calculatePartSizes(); // Precompute part sizes
  }

  /// Determines the part sizes based on the file size
  List<int> _calculatePartSizes() {
    int maxPartSize = _getMaxPartSize(fileSize);
    List<int> parts = [];
    int remainingSize = fileSize;
    const int minPartSize = 10 * 1024 * 1024;

    while (remainingSize > maxPartSize) {
      parts.add(maxPartSize);
      remainingSize -= maxPartSize;
    }
    if (remainingSize > 0) {
      parts.add(remainingSize);
    }

    // If last part is less than min, merge with previous
    if (parts.length > 1 && parts.last < minPartSize) {
      parts[parts.length - 2] += parts.last;
      parts.removeLast();
    }
    return parts;
  }

  /// Returns max part size based on file size
  int _getMaxPartSize(int size) {
    if (size <= 500 * 1024 * 1024) return 25 * 1024 * 1024;
    if (size <= 1000 * 1024 * 1024) return 50 * 1024 * 1024;
    return 90 * 1024 * 1024;
  }

  /// Returns the start (inclusive) and end (exclusive) byte indices for a given part.
  ({int start, int end}) getStartEndIndexForPart(int partNumber) {
    int partIndex = partNumber - 1;

    // Optimized: No longer creates a sublist in memory
    int start = 0;
    for (int i = 0; i < partIndex; i++) {
      start += partSizes[i];
    }

    // Calculate exclusive end index
    int end = start + partSizes[partIndex];

    return (start: start, end: end);
  }
}

typedef ProgressCallback = void Function(int received, int total);
typedef AsyncProgressCallback = FutureOr<void> Function(int sent, int total);

enum DownloadFailureKind {
  authorization,
  notFound,
  rateLimited,
  server,
  otherHttp,
  transport,
}

class DownloadStreamResult {
  final bool succeeded;
  final int? statusCode;
  final DownloadFailureKind? failureKind;

  const DownloadStreamResult._({
    required this.succeeded,
    this.statusCode,
    this.failureKind,
  });

  const DownloadStreamResult.success() : this._(succeeded: true);

  const DownloadStreamResult.transportFailure()
      : this._(
          succeeded: false,
          failureKind: DownloadFailureKind.transport,
        );

  factory DownloadStreamResult.httpFailure(int statusCode) {
    final kind = switch (statusCode) {
      401 || 403 => DownloadFailureKind.authorization,
      404 => DownloadFailureKind.notFound,
      429 => DownloadFailureKind.rateLimited,
      >= 500 => DownloadFailureKind.server,
      _ => DownloadFailureKind.otherHttp,
    };
    return DownloadStreamResult._(
      succeeded: false,
      statusCode: statusCode,
      failureKind: kind,
    );
  }

  bool get isRetryable => switch (failureKind) {
        DownloadFailureKind.authorization ||
        DownloadFailureKind.rateLimited ||
        DownloadFailureKind.server ||
        DownloadFailureKind.transport =>
          true,
        _ => false,
      };
}

enum UploadFailureKind {
  authorization,
  rateLimited,
  server,
  otherHttp,
  transport,
  invalidRequest,
  unexpected,
}

class UploadFileResult {
  final bool succeeded;
  final int? statusCode;
  final UploadFailureKind? failureKind;
  final Map<String, dynamic> data;

  const UploadFileResult._({
    required this.succeeded,
    required this.data,
    this.statusCode,
    this.failureKind,
  });

  factory UploadFileResult.success(Map<String, dynamic> data) =>
      UploadFileResult._(succeeded: true, data: data);

  factory UploadFileResult.httpFailure(
    int statusCode,
    Map<String, dynamic> data,
  ) {
    final kind = switch (statusCode) {
      401 || 403 => UploadFailureKind.authorization,
      408 || 429 => UploadFailureKind.rateLimited,
      >= 500 => UploadFailureKind.server,
      _ => UploadFailureKind.otherHttp,
    };
    return UploadFileResult._(
      succeeded: false,
      data: data,
      statusCode: statusCode,
      failureKind: kind,
    );
  }

  factory UploadFileResult.failure(UploadFailureKind kind) =>
      UploadFileResult._(succeeded: false, data: const {}, failureKind: kind);

  bool get isRetryable => switch (failureKind) {
        UploadFailureKind.authorization ||
        UploadFailureKind.rateLimited ||
        UploadFailureKind.server ||
        UploadFailureKind.transport =>
          true,
        _ => false,
      };
}

/// Downloads a file as a stream directly to an [IOSink] to prevent memory overuse.
Future<DownloadStreamResult> downloadFileStream({
  required String url,
  required Map<String, String>? headers,
  required IOSink fileOut,
  required ProgressCallback? onProgress,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final client = HttpClient();
  client.connectionTimeout = timeout;
  AppLogger logger = AppLogger(prefixes: ["Downloader"]);
  DownloadStreamResult result = const DownloadStreamResult.transportFailure();
  try {
    // 1. Initialize the GET request
    final request = await client.getUrl(Uri.parse(url)).timeout(timeout);

    // 2. Attach any provided headers (e.g., Auth tokens, custom Cloud sync headers)
    if (headers != null) {
      headers.forEach((key, value) {
        request.headers.add(key, value);
      });
    }

    // 3. Execute the request
    final response = await request.close().timeout(timeout);

    // 4. Ensure the request was successful
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Note: contentLength will be -1 if the server doesn't send a Content-Length header
      final total = response.contentLength;
      int received = 0;

      // 5. Stream the response directly into the IOSink chunk by chunk
      await for (final List<int> chunk in response.timeout(timeout)) {
        fileOut.add(chunk);
        received += chunk.length;
        // Trigger the callback for your UI's progress bar
        if (onProgress != null) {
          onProgress(received, total);
        }
      }
      result = const DownloadStreamResult.success();
    } else {
      result = DownloadStreamResult.httpFailure(response.statusCode);
    }
  } catch (e, s) {
    logger.error("Failed", error: e.toString(), stackTrace: s);
  } finally {
    // 6. Guarantee cleanup of network and file resources
    client.close(force: true);
    await fileOut.flush();
    await fileOut.close();
  }
  return result;
}

Future<UploadFileResult> uploadFileStream({
  required String method,
  required File file,
  required String url,
  required Map<String, String>? headers,
  AsyncProgressCallback? onProgress,
  http_lib.Client? httpClient,
  Duration timeout = const Duration(seconds: 30),
}) async {
  AppLogger logger = AppLogger(prefixes: ["Uploader"]);
  Map<String, dynamic> data = {};
  http_lib.StreamedRequest? request;
  try {
    final contentLength = await file.length();
    request = http_lib.StreamedRequest(method, Uri.parse(url));

    if (headers != null) {
      request.headers.addAll(headers);
    }
    request.contentLength = contentLength;

    final client = httpClient ?? AppHttpClients.transfer;
    final responseFuture = client.send(request);
    var sent = 0;
    var lastReportedPercent = -1;
    final uploadStream = file.openRead().asyncMap<List<int>>((chunk) async {
      sent += chunk.length;
      final percent = contentLength == 0 ? 100 : sent * 100 ~/ contentLength;
      if (onProgress != null && percent != lastReportedPercent) {
        lastReportedPercent = percent;
        await onProgress(sent, contentLength);
      }
      return chunk;
    });

    await request.sink.addStream(uploadStream.timeout(timeout));
    await request.sink.close();
    var streamedResponse = await responseFuture.timeout(timeout);
    var response =
        await http_lib.Response.fromStream(streamedResponse).timeout(timeout);

    // Check response
    if (response.statusCode >= 200 && response.statusCode < 300) {
      safeParseJson(response.body, data, logger);
      return UploadFileResult.success(data);
    } else {
      safeParseJson(response.body, data, logger);
      return UploadFileResult.httpFailure(response.statusCode, data);
    }
  } on SocketException catch (e, s) {
    // Handle no internet connection / DNS failures
    logger.error("Upload Failed: No Internet Connection",
        error: e, stackTrace: s);
    return UploadFileResult.failure(UploadFailureKind.transport);
  } on TimeoutException catch (e, s) {
    logger.error("Upload Failed: Timeout", error: e, stackTrace: s);
    return UploadFileResult.failure(UploadFailureKind.transport);
  } on FormatException catch (e, s) {
    // Handle malformed URLs or JSON
    logger.error("Upload Failed: Format Exception", error: e, stackTrace: s);
    return UploadFileResult.failure(UploadFailureKind.invalidRequest);
  } catch (e, s) {
    // Catch-all for unexpected errors
    logger.error("Upload Failed: Unexpected Error", error: e, stackTrace: s);
    return UploadFileResult.failure(UploadFailureKind.unexpected);
  } finally {
    try {
      await request?.sink.close();
    } catch (_) {}
  }
}
