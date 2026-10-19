import 'dart:convert';
import 'dart:typed_data';

import 'package:bip39/bip39.dart' as bip39;
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';

void main() {
  late CryptoUtils crypto;
  final master = Uint8List.fromList(List.generate(32, (i) => i));
  setUpAll(() async => crypto = CryptoUtils(await SodiumSumoInit.init()));

  test('generated recovery words restore the exact master and file hashing key',
      () {
    final keys = crypto.generateKeys(masterKeyBytes: master).getResult()!;
    final private = keys[AppString.privateKeys.string] as Map<String, dynamic>;
    final server = keys[AppString.serverKeys.string] as Map<String, dynamic>;
    final words = bip39.entropyToMnemonic(
        bytesToHex(base64Decode(private[AppString.accessKey.string])));
    expect(words.split(' ').length, 24);
    expect(bip39.validateMnemonic(words), isTrue);
    final restoredAccess = hexToBytes(bip39.mnemonicToEntropy(words));
    final restored = crypto.decryptBytes(
      cipherBytes: base64Decode(server[AppString.cipher.string]),
      nonce: base64Decode(server[AppString.nonce.string]),
      key: restoredAccess,
    );
    expect(restored.isSuccess, isTrue);
    final restoredMaster =
        restored.getResult()![AppString.decrypted.string] as Uint8List;
    expect(restoredMaster, master);
    expect(
        crypto.getHashingKeyFromMasterKey(base64Encode(restoredMaster),
            AppString.fileHashKeyContext.string, 1),
        private[AppString.fileHashKey.string]);
  });

  test('a different valid recovery phrase cannot unlock the stored master key',
      () {
    final first = crypto.generateKeys(masterKeyBytes: master).getResult()!;
    final second = crypto.generateKeys().getResult()!;
    final server = first[AppString.serverKeys.string];
    final wrongAccess =
        second[AppString.privateKeys.string][AppString.accessKey.string];
    expect(
        crypto
            .decryptBytes(
              cipherBytes: base64Decode(server[AppString.cipher.string]),
              nonce: base64Decode(server[AppString.nonce.string]),
              key: base64Decode(wrongAccess),
            )
            .isFailure,
        isTrue);
  });

  for (final plain in [
    <int>[],
    [0, 255],
    utf8.encode('合同 🔐 private metadata')
  ]) {
    test(
        'metadata envelope round-trips ${plain.length} bytes with randomized encryption',
        () {
      final bytes = Uint8List.fromList(plain);
      final first = crypto.getEncryptedBytesMap(bytes, master);
      final second = crypto.getEncryptedBytesMap(bytes, master);
      expect(first, isNot(second));
      expect(crypto.getDecryptedBytesFromMap(first, master), bytes);
      expect(crypto.getDecryptedBytesFromMap(second, master), bytes);
    });
  }
  for (final field in [
    AppString.textCipher,
    AppString.textNonce,
    AppString.keyCipher,
    AppString.keyNonce
  ]) {
    test(
        'tampered ${field.string} cannot authenticate an encrypted metadata envelope',
        () {
      final encrypted =
          crypto.getEncryptedBytesMap(Uint8List.fromList([1, 2, 3]), master);
      final changed = base64Decode(encrypted[field.string]);
      changed[0] ^= 1;
      encrypted[field.string] = base64Encode(changed);
      expect(crypto.getDecryptedBytesFromMap(encrypted, master), isNull);
    });
  }
  test(
      'file encryption keys are wrapped and cannot be opened with another master',
      () {
    final fileKey = Uint8List.fromList(List.filled(32, 117));
    final wrapped = crypto.getFileEncryptionKeyCipher(fileKey, master);
    expect(base64Decode(wrapped[AppString.keyCipher.string]), isNot(fileKey));
    expect(
        crypto.getFileEncryptionKeyBytes(wrapped[AppString.keyCipher.string],
            wrapped[AppString.keyNonce.string], base64Encode(master)),
        fileKey);
    expect(
        crypto.getFileEncryptionKeyBytes(
            wrapped[AppString.keyCipher.string],
            wrapped[AppString.keyNonce.string],
            base64Encode(List.filled(32, 0))),
        isNull);
  });
  test('hash key derivation is deterministic and context/key-ID separated', () {
    final encoded = base64Encode(master);
    final first = crypto.getHashingKeyFromMasterKey(encoded, 'FileHash', 1);
    expect(crypto.getHashingKeyFromMasterKey(encoded, 'FileHash', 1), first);
    expect(crypto.getHashingKeyFromMasterKey(encoded, 'FileHash', 2),
        isNot(first));
    expect(crypto.getHashingKeyFromMasterKey(encoded, 'ElseHash', 1),
        isNot(first));
    expect(() => crypto.getHashingKeyFromMasterKey(encoded, 'short', 1),
        throwsArgumentError);
  });
}
