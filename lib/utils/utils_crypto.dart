import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../utils/common.dart';
import '../services/service_logger.dart';
import 'package:sodium/sodium_sumo.dart';
import 'enums.dart';

class CryptoUtils {
  final logger = AppLogger(prefixes: ["CryptoUtils"]);
  final SodiumSumo _sodium;
  CryptoUtils(this._sodium);

  static init() {
    SodiumSumoInit.init();
  }

  SecureKey generateKey() {
    return _sodium.crypto.secretBox.keygen(); // Generate 256-bit (32-byte) key
  }

  Uint8List generateSalt() {
    return _sodium.randombytes.buf(_sodium.crypto.pwhash.saltBytes);
  }

  Uint8List generateNonce() {
    return _sodium.randombytes.buf(_sodium.crypto.secretBox.nonceBytes);
  }

  String getHashingKeyFromMasterKey(
      String masterKeyBase64, String hashingContext, int keyId) {
    // CRITICAL: libsodium strictly requires the context to be exactly 8 characters.
    // If it's not 8 characters, the FFI call will throw an exception.
    if (hashingContext.length != 8) {
      throw ArgumentError('hashingContext must be exactly 8 characters long.');
    }

    final masterKeyBytes = base64Decode(masterKeyBase64);
    final masterSecureKey = _sodium.secureCopy(masterKeyBytes);
    SecureKey? hashingSecureKey;

    try {
      // Derive a sub-key specifically and ONLY for hashing files
      hashingSecureKey = _sodium.crypto.kdf.deriveFromKey(
        masterKey: masterSecureKey,
        context: hashingContext,
        subkeyId: BigInt.from(keyId), // Convert standard int to BigInt
        subkeyLen: _sodium.crypto.genericHash.bytes,
      );

      // Extract the raw bytes from the SecureKey and convert to Base64
      final derivedBytes = hashingSecureKey.extractBytes();
      return base64Encode(derivedBytes);
    } finally {
      // Always dispose of SecureKeys immediately to wipe them from memory
      masterSecureKey.dispose();
      hashingSecureKey?.dispose();
    }
  }

  ExecutionResult encryptBytes(
      {required Uint8List plainBytes, Uint8List? key}) {
    SecureKey secureKey =
        key == null ? generateKey() : SecureKey.fromList(_sodium, key);
    Uint8List keyBytes = secureKey.extractBytes();
    Uint8List nonce = generateNonce();
    Uint8List cipherBytes = _sodium.crypto.secretBox
        .easy(message: plainBytes, nonce: nonce, key: secureKey);
    secureKey.dispose();
    return ExecutionResult.success({
      AppString.encrypted.string: cipherBytes,
      AppString.key.string: keyBytes,
      AppString.nonce.string: nonce
    });
  }

  ExecutionResult decryptBytes(
      {required Uint8List cipherBytes,
      required Uint8List nonce,
      required Uint8List key}) {
    SecureKey secureKey = SecureKey.fromList(_sodium, key);
    ExecutionResult executionResult;
    try {
      Uint8List plainBytes = _sodium.crypto.secretBox
          .openEasy(cipherText: cipherBytes, nonce: nonce, key: secureKey);
      executionResult =
          ExecutionResult.success({AppString.decrypted.string: plainBytes});
    } catch (e, s) {
      logger.error("decryptBytes", error: e, stackTrace: s);
      executionResult = ExecutionResult.failure(reason: e.toString());
    } finally {
      secureKey.dispose();
    }
    return executionResult;
  }

  Future<ExecutionResult> encryptFile(String fileIn, String fileOut,
      {Uint8List? key, int? start, int? end}) async {
    ExecutionResult executionResult;
    SecureKey secretKey = key == null
        ? _sodium.crypto.secretStream.keygen()
        : SecureKey.fromList(_sodium, key);
    String secretKeyBase64 = base64Encode(secretKey.extractBytes());
    try {
      await _sodium.crypto.secretStream
          .pushChunked(
            messageStream: File(fileIn).openRead(start, end),
            key: secretKey,
            chunkSize: 4096,
          )
          .pipe(
            File(fileOut).openWrite(),
          );
      executionResult =
          ExecutionResult.success({AppString.key.string: secretKeyBase64});
    } catch (e, s) {
      logger.error("encryptFile", error: e, stackTrace: s);
      executionResult = ExecutionResult.failure(reason: e.toString());
    } finally {
      secretKey.dispose();
    }

    return executionResult;
  }

  Future<ExecutionResult> decryptFile(
      String fileIn, String fileOut, Uint8List keyBytes,
      {FileMode writeMode = FileMode.append}) async {
    ExecutionResult executionResult;
    SecureKey secretKey = SecureKey.fromList(_sodium, keyBytes);
    try {
      await _sodium.crypto.secretStream
          .pullChunked(
            cipherStream: File(fileIn).openRead(),
            key: secretKey,
            chunkSize: 4096,
          )
          .pipe(
            File(fileOut).openWrite(mode: writeMode),
          );
      executionResult = ExecutionResult.success({});
    } catch (e, s) {
      logger.error("decryptFile", error: e, stackTrace: s);
      executionResult = ExecutionResult.failure(reason: e.toString());
    } finally {
      secretKey.dispose();
    }
    return executionResult;
  }

  Map<String, dynamic> getEncryptedBytesMap(
      Uint8List plainBytes, Uint8List masterKeyBytes) {
    Map<String, dynamic> changeMap = {};
    ExecutionResult encryptionResult = encryptBytes(
      plainBytes: plainBytes,
    );
    Uint8List cipherBytes =
        encryptionResult.getResult()![AppString.encrypted.string];
    Uint8List keyBytes = encryptionResult.getResult()![AppString.key.string];
    Uint8List nonceBytes =
        encryptionResult.getResult()![AppString.nonce.string];

    //encrypt key with master key
    ExecutionResult keyEncryptionResult =
        encryptBytes(plainBytes: keyBytes, key: masterKeyBytes);
    Uint8List keyCipherBytes =
        keyEncryptionResult.getResult()![AppString.encrypted.string];
    Uint8List keyNonceBytes =
        keyEncryptionResult.getResult()![AppString.nonce.string];

    String cipherBase64 = base64Encode(cipherBytes);
    String nonceBase64 = base64Encode(nonceBytes);

    String keyCipherBase64 = base64Encode(keyCipherBytes);
    String keyNonceBase64 = base64Encode(keyNonceBytes);

    changeMap[AppString.textCipher.string] = cipherBase64;
    changeMap[AppString.textNonce.string] = nonceBase64;
    changeMap[AppString.keyCipher.string] = keyCipherBase64;
    changeMap[AppString.keyNonce.string] = keyNonceBase64;
    return changeMap;
  }

  Uint8List? getDecryptedBytesFromMap(
      Map<String, dynamic> map, Uint8List masterKeyBytes) {
    String keyCipherBase64 = map[AppString.keyCipher.string];
    String keyNonceBase64 = map[AppString.keyNonce.string];
    Uint8List keyCipherBytes = base64Decode(keyCipherBase64);
    Uint8List keyNonceBytes = base64Decode(keyNonceBase64);

    ExecutionResult keyDecryptionResult = decryptBytes(
        cipherBytes: keyCipherBytes, nonce: keyNonceBytes, key: masterKeyBytes);
    if (keyDecryptionResult.isFailure) return null;
    Uint8List keyBytes =
        keyDecryptionResult.getResult()![AppString.decrypted.string];

    String cipherTextBase64 = map[AppString.textCipher.string];
    String cipherNonceBase64 = map[AppString.textNonce.string];
    Uint8List cipherBytes = base64Decode(cipherTextBase64);
    Uint8List nonceBytes = base64Decode(cipherNonceBase64);

    ExecutionResult decryptionResult = decryptBytes(
        cipherBytes: cipherBytes, nonce: nonceBytes, key: keyBytes);
    if (decryptionResult.isFailure) return null;

    Uint8List decryptedBytes =
        decryptionResult.getResult()![AppString.decrypted.string];
    return decryptedBytes;
  }

  Map<String, dynamic> getFileEncryptionKeyCipher(
      Uint8List encryptionKeyBytes, Uint8List masterKeyBytes) {
    ExecutionResult keyEncryptionResult =
        encryptBytes(plainBytes: encryptionKeyBytes, key: masterKeyBytes);
    Uint8List keyCipherBytes =
        keyEncryptionResult.getResult()![AppString.encrypted.string];
    Uint8List keyNonceBytes =
        keyEncryptionResult.getResult()![AppString.nonce.string];
    String keyCipherBase64 = base64Encode(keyCipherBytes);
    String keyNonceBase64 = base64Encode(keyNonceBytes);
    return {
      AppString.keyCipher.string: keyCipherBase64,
      AppString.keyNonce.string: keyNonceBase64
    };
  }

  Uint8List? getFileEncryptionKeyBytes(
      String keyCipherBase64, String keyNonceBase64, String masterKeyBase64) {
    Uint8List keyCipherBytes = base64Decode(keyCipherBase64);
    Uint8List keyNonceBytes = base64Decode(keyNonceBase64);
    Uint8List masterKeyBytes = base64Decode(masterKeyBase64);
    ExecutionResult keyDecryptionResult = decryptBytes(
        cipherBytes: keyCipherBytes, nonce: keyNonceBytes, key: masterKeyBytes);
    if (keyDecryptionResult.isFailure) return null;
    Uint8List keyBytes =
        keyDecryptionResult.getResult()![AppString.decrypted.string];
    return keyBytes;
  }

  ExecutionResult generateKeys({Uint8List? masterKeyBytes}) {
    if (masterKeyBytes == null) {
      SecureKey masterKey = generateKey();
      masterKeyBytes = masterKey.extractBytes();
      masterKey.dispose();
    }
    String masterKeyBase64 = base64Encode(masterKeyBytes);

    SecureKey accessKey = generateKey();
    Uint8List accessKeyBytes = accessKey.extractBytes();
    accessKey.dispose();
    String accessKeyBase64 = base64Encode(accessKeyBytes);

    String fileHashKeyBase64 = getHashingKeyFromMasterKey(
        masterKeyBase64, AppString.fileHashKeyContext.string, 1);

    ExecutionResult masterKeyEncryptedWithAccessKeyResult =
        encryptBytes(plainBytes: masterKeyBytes, key: accessKeyBytes);
    Uint8List masterKeyEncryptedWithAccessKeyBytes =
        masterKeyEncryptedWithAccessKeyResult
            .getResult()![AppString.encrypted.string];
    Uint8List masterKeyAccessKeyNonceBytes =
        masterKeyEncryptedWithAccessKeyResult
            .getResult()![AppString.nonce.string];
    String masterKeyEncryptedWithAccessKeyBase64 =
        base64Encode(masterKeyEncryptedWithAccessKeyBytes);
    String masterKeyAccessKeyNonceBase64 =
        base64Encode(masterKeyAccessKeyNonceBytes);

    Map<String, dynamic> serverKeysBase64 = {
      AppString.cipher.string: masterKeyEncryptedWithAccessKeyBase64,
      AppString.nonce.string: masterKeyAccessKeyNonceBase64,
    };

    Map<String, dynamic> privateKeysBase64 = {
      AppString.masterKey.string: masterKeyBase64,
      AppString.accessKey.string: accessKeyBase64,
      AppString.fileHashKey.string: fileHashKeyBase64
    };
    return ExecutionResult.success({
      AppString.serverKeys.string: serverKeysBase64,
      AppString.privateKeys.string: privateKeysBase64
    });
  }
}
