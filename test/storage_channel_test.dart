import 'package:file_vault_bb/storage/storage_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.jeerovan.fife/channel_storage');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('legacy placeholder is not accepted as a persistent bookmark', () {
    expect(ChannelStorage.hasUsableBookmark(null), isFalse);
    expect(ChannelStorage.hasUsableBookmark(''), isFalse);
    expect(ChannelStorage.hasUsableBookmark('sandboxed'), isFalse);
    expect(ChannelStorage.hasUsableBookmark('base64-bookmark'), isTrue);
  });

  test('resolved access path is used for balanced release', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'startAccessing') return '/resolved/folder';
      if (call.method == 'stopAccessing') return true;
      return null;
    });

    final resolvedPath = await ChannelStorage.startAccessing('bookmark');
    expect(resolvedPath, '/resolved/folder');
    await ChannelStorage.stopAccessing(resolvedPath!);

    expect(calls, hasLength(2));
    expect(calls.first.method, 'startAccessing');
    expect(calls.first.arguments, {'bookmark': 'bookmark'});
    expect(calls.last.method, 'stopAccessing');
    expect(calls.last.arguments, {'path': '/resolved/folder'});
  });
}
