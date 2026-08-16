import 'package:file_vault_bb/storage/storage_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy placeholder is not accepted as a persistent bookmark', () {
    expect(ChannelStorage.hasUsableBookmark(null), isFalse);
    expect(ChannelStorage.hasUsableBookmark(''), isFalse);
    expect(ChannelStorage.hasUsableBookmark('sandboxed'), isFalse);
    expect(ChannelStorage.hasUsableBookmark('base64-bookmark'), isTrue);
  });
}
