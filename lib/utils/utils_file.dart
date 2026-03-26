import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_vault_bb/services/service_logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

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
    if (size <= 1000 * 1024 * 1024) return 25 * 1024 * 1024;
    return 50 * 1024 * 1024;
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
Future<bool> downloadFileStream({
  required String url,
  required Map<String, String>? headers,
  required IOSink fileOut,
  required ProgressCallback? onProgress,
}) async {
  final client = HttpClient();
  AppLogger logger = AppLogger(prefixes: ["Downloader"]);
  bool success = false;
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
      success = true;
    }
  } catch (e, s) {
    logger.error("Failed", error: e.toString(), stackTrace: s);
  } finally {
    // 6. Guarantee cleanup of network and file resources
    client.close(force: true);
    await fileOut.flush();
    await fileOut.close();
  }
  return success;
}
