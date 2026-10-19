import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  late CryptoUtils crypto;
  late Directory directory;

  setUpAll(() async => crypto = CryptoUtils(await SodiumSumoInit.init()));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fife-crypto-release-');
  });
  tearDown(() => directory.delete(recursive: true));

  for (final size in [0, 1, 4095, 4096, 4097, 65537]) {
    test('authenticated file encryption round-trips $size binary bytes',
        () async {
      final bytes = Uint8List.fromList(
          List<int>.generate(size, (index) => (index * 31 + 17) & 255));
      final source = File('${directory.path}/source')..writeAsBytesSync(bytes);
      final encrypted = File('${directory.path}/encrypted');
      final restored = File('${directory.path}/restored');
      final result = await crypto.encryptFile(source.path, encrypted.path);
      expect(result.isSuccess, isTrue);
      final key = base64Decode(result.getResult()![AppString.key.string]);
      expect(await encrypted.length(), greaterThan(size));
      final decrypted = await crypto.decryptFile(
          encrypted.path, restored.path, key,
          writeMode: FileMode.write);
      expect(decrypted.isSuccess, isTrue);
      expect(await restored.length(), size);
      expect(
          sha256.convert(await restored.readAsBytes()), sha256.convert(bytes));
    });
  }

  for (final corrupt in [
    'wrong key',
    'modified ciphertext',
    'truncated ciphertext'
  ]) {
    test('file decryption rejects $corrupt', () async {
      final source = File('${directory.path}/source')
        ..writeAsBytesSync(List<int>.generate(8193, (i) => i & 255));
      final encrypted = File('${directory.path}/encrypted');
      final restored = File('${directory.path}/restored');
      final result = await crypto.encryptFile(source.path, encrypted.path);
      expect(result.isSuccess, isTrue);
      final key = base64Decode(result.getResult()![AppString.key.string]);
      if (corrupt == 'wrong key') {
        key[0] ^= 1;
      } else {
        final bytes = await encrypted.readAsBytes();
        if (corrupt == 'modified ciphertext') {
          bytes[bytes.length ~/ 2] ^= 1;
          await encrypted.writeAsBytes(bytes);
        } else {
          await encrypted.writeAsBytes(bytes.sublist(0, bytes.length - 1));
        }
      }
      final decrypted = await crypto.decryptFile(
          encrypted.path, restored.path, key,
          writeMode: FileMode.write);
      expect(decrypted.isSuccess, isFalse);
      expect(decrypted.failureReason, contains('SodiumException'));
      expect(await source.length(), 8193);
    });
  }

  test('missing encryption source returns a clean failure', () async {
    final result = await crypto.encryptFile(
        '${directory.path}/missing', '${directory.path}/encrypted');
    expect(result.isSuccess, isFalse);
    expect(result.failureReason, isNotEmpty);
  });
}
