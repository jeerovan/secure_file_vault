import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_vault_bb/services/service_logger.dart';
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

  /// Fetches a specific part of the file as bytes
  Future<Uint8List?> getPart(int partNumber) async {
    if (file == null) {
      throw StateError('Cannot read file part: File object was not provided.');
    }

    int partIndex = partNumber - 1;
    if (partIndex < 0 || partIndex >= partSizes.length) {
      return null;
    }

    RandomAccessFile raf = await file!.open(mode: FileMode.read);

    // Optimized: No longer creates a sublist in memory
    int offset = 0;
    for (int i = 0; i < partIndex; i++) {
      offset += partSizes[i];
    }

    int partSize = partSizes[partIndex];

    await raf.setPosition(offset); // Seek to the correct position
    Uint8List partBytes = await raf.read(partSize);
    await raf.close();

    return partBytes;
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

  /// Returns the number of parts required to cover a given size in bytes.
  int getPartsInSize(int sizeBytes) {
    if (sizeBytes <= 0) return 0;
    if (sizeBytes >= fileSize) return partSizes.length;

    int accumulatedSize = 0;
    int partsCount = 0;

    for (int size in partSizes) {
      accumulatedSize += size;
      partsCount++;
      if (accumulatedSize >= sizeBytes) {
        break;
      }
    }

    return partsCount;
  }
}

typedef ProgressCallback = void Function(int received, int total);

/// Downloads a file as a stream directly to an [IOSink] to prevent memory overuse.
Future<int> downloadFileStream({
  required String url,
  required Map<String, String>? headers,
  required IOSink fileOut,
  required ProgressCallback? onProgress,
}) async {
  final client = HttpClient();
  AppLogger logger = AppLogger(prefixes: ["Downloader"]);
  int state = 0;
  try {
    // 1. Initialize the GET request
    final request = await client.getUrl(Uri.parse(url));

    // 2. Attach any provided headers (e.g., Auth tokens, custom Cloud sync headers)
    if (headers != null) {
      headers.forEach((key, value) {
        request.headers.add(key, value);
      });
    }

    // 3. Execute the request
    final response = await request.close();

    // 4. Ensure the request was successful
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Note: contentLength will be -1 if the server doesn't send a Content-Length header
      final total = response.contentLength;
      int received = 0;

      // 5. Stream the response directly into the IOSink chunk by chunk
      await for (final List<int> chunk in response) {
        fileOut.add(chunk);
        received += chunk.length;
        logger.info('$received of $total');
        // Trigger the callback for your UI's progress bar
        if (onProgress != null) {
          onProgress(received, total);
        }
      }
      state = 1;
    } else {
      state = -1;
    }
  } catch (e, s) {
    logger.error("Failed", error: e.toString(), stackTrace: s);
  } finally {
    // 6. Guarantee cleanup of network and file resources
    client.close(force: true);
    await fileOut.flush();
    await fileOut.close();
  }
  return state;
}

Future<Map<String, dynamic>> uploadFileBytes({
  required String method,
  required Uint8List bytes,
  required String url,
  required Map<String, String>? headers,
}) async {
  AppLogger logger = AppLogger(prefixes: ["Uploader"]);
  Map<String, dynamic> data = {"error": ""};
  try {
    // Create multipart request
    var request = http_lib.Request(method, Uri.parse(url));

    // Add headers
    if (headers != null) {
      request.headers.addAll(headers);
    }

    request.bodyBytes = bytes;

    // Send request and get response
    var streamedResponse = await request.send();
    var response = await http_lib.Response.fromStream(streamedResponse);

    // Check response
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success Range
      safeParseJson(response.body, data, logger);
    } else if (response.statusCode >= 400 && response.statusCode < 500) {
      // Client Error Range (e.g., 400 Bad Request, 401 Unauthorized, 413 Payload Too Large)
      data["error"] =
          'Client Error (${response.statusCode}): ${response.reasonPhrase ?? 'Unknown'}';
      safeParseJson(response.body, data, logger);
    } else if (response.statusCode >= 500) {
      // Server Error Range (e.g., 500 Internal Error, 502 Bad Gateway)
      data["error"] =
          'Server Error (${response.statusCode}): Backup service is currently unavailable.';
      // We generally avoid parsing JSON on 500s as servers often return raw HTML error pages
    } else {
      // Unhandled/Unexpected Status Codes
      data["error"] = 'Unexpected Error: HTTP ${response.statusCode}';
    }
  } on SocketException catch (e, s) {
    // Handle no internet connection / DNS failures
    logger.error("Upload Failed: No Internet Connection",
        error: e, stackTrace: s);
    data["error"] = 'Network Error: Please check your internet connection.';
  } on FormatException catch (e, s) {
    // Handle malformed URLs or JSON
    logger.error("Upload Failed: Format Exception", error: e, stackTrace: s);
    data["error"] = 'Format Error: Failed to process the request or response.';
  } catch (e, s) {
    // Catch-all for unexpected errors
    logger.error("Upload Failed: Unexpected Error", error: e, stackTrace: s);
    data["error"] = e.toString();
  }
  return data;
}
