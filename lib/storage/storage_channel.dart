import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

class ChannelStorage {
  static const MethodChannel _channel =
      MethodChannel('com.jeerovan.fife/channel_storage');

  static bool hasUsableBookmark(String? bookmark) =>
      bookmark != null && bookmark.isNotEmpty && bookmark != 'sandboxed';

  static Future<Map<String, String>?> pickDirectory(
      {String? initialDirectory}) async {
    final Map<String, dynamic>? args =
        initialDirectory != null ? {'path': initialDirectory} : null;
    final result = await _channel.invokeMethod('pickDirectory', args);
    if (result != null) {
      return Map<String, String>.from(result);
    }
    return null;
  }

  static Future<String?> startAccessing(String bookmarkBase64) async {
    final accessPath = await _channel
        .invokeMethod<String>('startAccessing', {'bookmark': bookmarkBase64});
    // Apple bookmarks follow moves into Recently Deleted, where the folder
    // may still exist and be readable. Do not scan, read or publish into it.
    // iOS trash-directory APIs can also miss this case (Apple DTS 813329).
    // Match reserved path components, not ordinary names such as "Trash".
    if (accessPath != null &&
        path.posix.split(path.posix.normalize(accessPath)).any(
            (component) => component == '.Trash' || component == '.Trashes')) {
      // Native access was acquired; callers receiving null own no lease.
      await stopAccessing(accessPath);
      return null;
    }
    return accessPath;
  }

  static Future<void> stopAccessing(String path) async {
    await _channel.invokeMethod('stopAccessing', {'path': path});
  }
}
