import 'dart:convert';
import 'dart:io';

import 'package:bip39/bip39.dart' as bip39;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/model_setting.dart';
import '../storage/storage_secure.dart';
import '../utils/enums.dart';
import 'service_app_lock.dart';
import 'service_session_work.dart';

class RecoveryPhraseUnavailable implements Exception {
  const RecoveryPhraseUnavailable();
}

/// Desktop/Apple own exports natively; Android writes to a selected document.
/// Cleanup never touches a shared temporary directory or user-saved copies.
class RecoveryPhraseExportFiles {
  static const fileName = 'fife_recovery_phrase.txt';
  static const channel = MethodChannel('com.jeerovan.fife/recovery_export');

  static Future<void> clear() async {
    if (Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      await channel.invokeMethod<void>('clear');
    }
  }
}

abstract interface class RecoveryPhrasePlatform {
  Future<void> copy(String phrase);
  Future<String?> reserveSave();
  Future<bool> save(String phrase, String title, String? reservation);
}

class NativeRecoveryPhrasePlatform implements RecoveryPhrasePlatform {
  NativeRecoveryPhrasePlatform({
    Future<bool> Function(Uint8List bytes, String title, String? reservation)?
        saveFile,
    Future<void> Function()? clearTemporaryFiles,
    Future<void> Function(String? reservation)? releaseTemporaryFiles,
  })  : _saveFile = saveFile ?? _nativeSave,
        _clear = clearTemporaryFiles ?? RecoveryPhraseExportFiles.clear,
        _release = releaseTemporaryFiles ?? _nativeRelease;

  static const _privacy = MethodChannel('com.jeerovan.fife/app_lock_privacy');
  static bool _saving = false;
  static int _saveAttempts = 0;
  static bool? _lastSaveResult;
  @visibleForTesting
  static bool get saveInProgress => _saving;
  @visibleForTesting
  static int get saveAttempts => _saveAttempts;
  @visibleForTesting
  static bool? get lastSaveResult => _lastSaveResult;
  final Future<bool> Function(Uint8List, String, String?) _saveFile;
  final Future<void> Function() _clear;
  final Future<void> Function(String?) _release;

  static Future<void> _nativeRelease(String? reservation) async {
    if (Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      await RecoveryPhraseExportFiles.channel
          .invokeMethod<void>('release', reservation);
    }
  }

  static Future<bool> _nativeSave(
      Uint8List bytes, String title, String? reservation) async {
    if (Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      return await RecoveryPhraseExportFiles.channel
              .invokeMethod<bool>('save', {
            'text': utf8.decode(bytes),
            'title': title,
            'reservation': reservation,
          }) ??
          false;
    }
    return await FilePicker.saveFile(
            fileName: RecoveryPhraseExportFiles.fileName,
            bytes: bytes,
            mimeType: 'text/plain',
            dialogTitle: title,
            type: FileType.custom,
            allowedExtensions: ['txt']) !=
        null;
  }

  @override
  Future<void> copy(String phrase) =>
      _privacy.invokeMethod<void>('copyRecoveryPhrase', phrase);

  @override
  Future<String?> reserveSave() async {
    await _clear();
    return Platform.isIOS ||
            Platform.isMacOS ||
            Platform.isWindows ||
            Platform.isLinux
        ? RecoveryPhraseExportFiles.channel.invokeMethod<String>('reserve')
        : null;
  }

  @override
  Future<bool> save(String phrase, String title, String? reservation) async {
    if (_saving) throw StateError('A recovery export is already open');
    _saving = true;
    _saveAttempts++;
    _lastSaveResult = null;
    final bytes = Uint8List.fromList(utf8.encode(phrase));
    try {
      final saved = await _saveFile(bytes, title, reservation);
      _lastSaveResult = saved;
      return saved;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      try {
        await _release(reservation);
      } catch (_) {
        _lastSaveResult = null;
        rethrow;
      } finally {
        _saving = false;
      }
    }
  }
}

class RecoveryPhraseService {
  RecoveryPhraseService({
    Future<String?> Function()? readAccessKey,
    Future<bool> Function()? signedIn,
    RecoveryPhrasePlatform? platform,
  })  : _readAccessKey = readAccessKey ?? _readStoredAccessKey,
        _signedIn = signedIn ?? _isSignedIn,
        _platform = platform ?? NativeRecoveryPhrasePlatform();

  final Future<String?> Function() _readAccessKey;
  final Future<bool> Function() _signedIn;
  final RecoveryPhrasePlatform _platform;

  static Future<String?> _readStoredAccessKey() =>
      SecureStorage().read(key: AppString.accessKey.string);

  static Future<bool> _isSignedIn() async =>
      await ModelSetting.getRaw(AppString.signedIn.string) == 'yes';

  Future<void> _check(AppLockAuthorization proof) async {
    await SessionWork.checkpoint();
    proof.requireAvailable();
    if (!await _signedIn()) throw const AppLockAccessDenied();
    await SessionWork.checkpoint();
    proof.requireAvailable();
  }

  Future<String> read(AppLockAuthorization proof) => SessionWork.run(() async {
        await _check(proof);
        final encoded = await _readAccessKey();
        await _check(proof);
        Uint8List? bytes;
        try {
          if (encoded == null) throw const RecoveryPhraseUnavailable();
          bytes = base64Decode(encoded);
          if (bytes.length != 32) throw const RecoveryPhraseUnavailable();
          final hex = bytes
              .map((value) => value.toRadixString(16).padLeft(2, '0'))
              .join();
          return bip39.entropyToMnemonic(hex);
        } catch (_) {
          // Format exceptions can embed the secret input. Never log/rethrow it.
          throw const RecoveryPhraseUnavailable();
        } finally {
          bytes?.fillRange(0, bytes.length, 0);
        }
      });

  Future<void> copy(AppLockAuthorization proof, String phrase) =>
      SessionWork.run(() async {
        await _check(proof);
        await _platform.copy(phrase);
        await SessionWork.checkpoint();
      });

  Future<bool> save(AppLockAuthorization proof, String phrase, String title) =>
      SessionWork.run(() async {
        await _check(proof);
        final reservation = await _platform.reserveSave();
        await _check(proof);
        // The authorized OS save dialog may leave the app. Its result cannot
        // restore the phrase view, and private staging is cleared in finally.
        final saved = await _platform.save(phrase, title, reservation);
        await SessionWork.checkpoint();
        return saved;
      });
}
