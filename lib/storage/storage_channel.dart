import 'package:flutter/services.dart';

class ChannelStorage {
  static const MethodChannel _channel =
      MethodChannel('com.jeerovan.fife/channel_storage');

  static Future<Map<String, String>?> pickDirectory() async {
    final result = await _channel.invokeMethod('pickDirectory');
    if (result != null) {
      return Map<String, String>.from(result);
    }
    return null;
  }

  static Future<String?> startAccessing(String bookmarkBase64) async {
    return await _channel
        .invokeMethod('startAccessing', {'bookmark': bookmarkBase64});
  }

  static Future<void> stopAccessing(String path) async {
    await _channel.invokeMethod('stopAccessing', {'path': path});
  }
}
