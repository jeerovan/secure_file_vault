import 'dart:io';

/// A final asynchronous log write can finish while recursive cleanup walks a
/// fixture tree. Retry that directory-not-empty race and Windows' temporary
/// sharing violation after handles/mocks are released; other errors still fail.
Future<void> deleteTestDirectory(Directory directory) async {
  for (var attempt = 0; attempt < 8; attempt++) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on FileSystemException catch (error) {
      // Another asynchronous teardown may finish between exists and delete.
      // Absence is the required outcome; never hide an error if data remains.
      if (error.osError?.errorCode == 2 && !await directory.exists()) return;
      final transient = {39, 66, 145}.contains(error.osError?.errorCode) ||
          (Platform.isWindows && error.osError?.errorCode == 32);
      if (!transient || attempt == 7) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}
