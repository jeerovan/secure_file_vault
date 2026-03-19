import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

class FileSplitter {
  final File file;
  final int fileSize;
  late List<int> partSizes; // Store calculated part sizes

  FileSplitter(
    this.file,
  ) : fileSize = file.lengthSync() {
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
    int partIndex = partNumber - 1;
    if (partIndex < 0 || partIndex >= partSizes.length) {
      return null;
    }

    RandomAccessFile raf = await file.open(mode: FileMode.read);
    int offset = partSizes
        .sublist(0, partIndex)
        .fold(0, (sum, element) => sum + element);
    int partSize = partSizes[partIndex];

    await raf.setPosition(offset); // Seek to the correct position
    Uint8List partBytes = await raf.read(partSize);
    await raf.close();

    return partBytes;
  }

  /// Returns the start (inclusive) and end (exclusive) byte indices for a given part.
  ({int start, int end}) getStartEndIndexForPart(int partNumber) {
    int partIndex = partNumber - 1;

    // Calculate start offset by summing previous part sizes
    int start = partSizes
        .sublist(0, partIndex)
        .fold(0, (sum, element) => sum + element);

    // Calculate exclusive end index
    int end = start + partSizes[partIndex];

    return (start: start, end: end);
  }
}

class FileDownloader {
  final Dio _dio = Dio();

  Future<bool> downloadFile({
    required String url,
    required String fileName,
    Function(int, int)? onProgress,
  }) async {
    try {
      // 1. Check Permissions
      final hasPermission = await _requestPermission();
      if (!hasPermission) {
        print("Permission denied");
        return false;
      }

      // 2. Get the correct download path
      final savePath = await _getSavePath(fileName);
      if (savePath == null) return false;

      print("Downloading to: $savePath");

      // 3. Download
      await _dio.download(
        url,
        savePath,
        onReceiveProgress: onProgress,
      );

      print("Download completed: $savePath");
      return true;
    } catch (e) {
      print("Download failed: $e");
      return false;
    }
  }

  Future<bool> _requestPermission() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      // On Android 13+ (SDK 33), WRITE_EXTERNAL_STORAGE is deprecated.
      // Apps can write to the Downloads folder without explicit permission
      // if using standard file APIs to create new files.
      if (androidInfo.version.sdkInt >= 33) {
        return true;
      }

      final status = await Permission.storage.request();
      return status.isGranted;
    }
    // iOS/Desktop usually don't need explicit storage permission
    // to write to their own container/downloads.
    return true;
  }

  Future<String?> _getSavePath(String fileName) async {
    Directory? directory;

    try {
      if (Platform.isAndroid) {
        // Direct approach for Android to ensure it goes to the public Downloads folder
        // path_provider sometimes returns internal app storage on Android
        directory = Directory('/storage/emulated/0/Download');

        // Fallback if the hardcoded path doesn't exist (unlikely on standard phones)
        if (!await directory.exists()) {
          directory = await getExternalStorageDirectory();
        }
      } else if (Platform.isIOS) {
        // On iOS, we save to ApplicationDocumentsDirectory.
        // With UIFileSharingEnabled in Info.plist, this is visible in the "Files" app.
        directory = await getApplicationDocumentsDirectory();
      } else {
        // Desktop (Windows/Mac/Linux)
        directory = await getDownloadsDirectory();
      }

      if (directory != null) {
        // Ensure the directory exists (helpful for desktop)
        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }
        return "${directory.path}/$fileName";
      }
    } catch (e) {
      print("Error getting path: $e");
    }
    return null;
  }
}
