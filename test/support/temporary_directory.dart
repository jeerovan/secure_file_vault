import 'dart:io';

/// A final asynchronous log write can finish while recursive cleanup walks a
/// fixture tree. Retry only that directory-not-empty race, after handles and
/// platform mocks have been released; permission and other errors still fail.
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
      if (!{39, 66, 145}.contains(error.osError?.errorCode) || attempt == 7) {
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }
}
