import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import '../models/model_setting.dart';
import '../storage/storage_secure.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../utils/utils_crypto.dart';
import 'service_backend.dart';
import 'service_session_cleanup.dart';
import 'service_session_work.dart';

enum RecoveryResetPhase {
  confirmation,
  waiting,
  generation,
  phrase,
  registration,
  signIn,
  missingKeys,
  unavailable
}

class RecoveryResetView {
  const RecoveryResetView(this.phase,
      {this.error,
      this.email,
      this.notBefore,
      this.expiresAt,
      this.canReturn = false});
  final RecoveryResetPhase phase;
  final String? error;
  final String? email;
  final int? notBefore;
  final int? expiresAt;
  final bool canReturn;
}

class _RecoveryFailure implements Exception {
  const _RecoveryFailure(this.code);
  final String code;
}

/// Owns reset progress independently of widget and process lifetimes. Private
/// keys and the challenge stay together in one authenticated secure-store value.
class RecoveryResetService {
  RecoveryResetService._() : _apiFactory = BackendApi.new;
  static final instance = RecoveryResetService._();
  final BackendApi Function() _apiFactory;
  final SecureStorage _storage = SecureStorage();
  Future<RecoveryResetView>? _running;

  @visibleForTesting
  RecoveryResetService.test({required BackendApi Function() apiFactory})
      : _apiFactory = apiFactory;

  static final _uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false);

  Future<bool> hasPending() =>
      _storage.containsKey(key: AppString.recoveryResetStage.string);

  Future<String?> pendingEmail() async {
    try {
      return (await _load())?['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _load() async {
    final raw = await _storage.read(key: AppString.recoveryResetStage.string);
    if (raw == null) return null;
    try {
      final stage = jsonDecode(raw);
      if (stage is! Map<String, dynamic> ||
          stage['version'] != 1 ||
          stage['userId'] is! String ||
          stage['email'] is! String ||
          stage['operationId'] is! String ||
          !_uuidPattern.hasMatch(stage['operationId']) ||
          stage['deviceUuid'] is! String ||
          !_uuidPattern.hasMatch(stage['deviceUuid']) ||
          stage['challenge'] is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(stage['challenge']) ||
          stage['privateKeys'] is! Map ||
          stage['serverKeys'] is! Map ||
          stage['sessionHash'] is! String ||
          stage['expectedGeneration'] is! String) {
        throw const _RecoveryFailure('staging_lost');
      }
      return stage;
    } catch (_) {
      throw const _RecoveryFailure('staging_lost');
    }
  }

  Future<void> _check(String revision) async {
    await SessionWork.checkpoint();
    if (SessionWork.revision != revision) throw const SessionInvalidated();
  }

  Future<void> _save(Map<String, dynamic> stage, String revision,
      {bool create = false}) async {
    await SessionWork.run(() async {
      await _check(revision);
      final previous = await _load();
      if (create
          ? previous != null
          : previous?['operationId'] != stage['operationId']) {
        throw const SessionInvalidated();
      }
      final encoded = jsonEncode(stage);
      await _storage.write(
          key: AppString.recoveryResetStage.string, value: encoded);
      if (await _storage.read(key: AppString.recoveryResetStage.string) !=
          encoded) {
        throw const _RecoveryFailure('staging_unavailable');
      }
    });
  }

  Future<bool> _sameAccount(Map<String, dynamic> stage) async =>
      await ModelSetting.getRaw(AppString.signedIn.string) == 'yes' &&
      await getSignedInUserId() == stage['userId'] &&
      (await _storage.read(key: AppString.sessionCookie.string))?.isNotEmpty ==
          true;

  String _hash(String value) => sha256.convert(utf8.encode(value)).toString();

  Map<String, dynamic> _data(Map<String, dynamic> response) {
    if (response['success'] != 1 || response['data'] is! Map) {
      throw _RecoveryFailure(
          response['message']?.toString() ?? 'please_try_again');
    }
    return Map<String, dynamic>.from(response['data']);
  }

  Future<Map<String, dynamic>> _status(String? operationId) async =>
      _data(await _apiFactory().get(
          endpoint: '/recovery-reset/status',
          queryParameters: {
            if (operationId != null) 'operation_id': operationId
          }));

  Future<RecoveryResetView> _singleFlight(
      Future<RecoveryResetView> Function() action) async {
    if (_running case final running?) return running;
    final operation = Future<RecoveryResetView>.sync(action)
        .onError<Object>((error, stack) async {
      if (error is _RecoveryFailure && error.code == 'vault_changed') {
        await SessionCleanup.instance.request();
        return const RecoveryResetView(RecoveryResetPhase.signIn);
      }
      if (error is _RecoveryFailure &&
          ['sign_in_again', '14', '18'].contains(error.code)) {
        return const RecoveryResetView(RecoveryResetPhase.signIn);
      }
      if (error is _RecoveryFailure &&
          ['staging_lost', 'staging_mismatch'].contains(error.code)) {
        return _missingKeys(error.code);
      }
      return RecoveryResetView(RecoveryResetPhase.unavailable,
          error: error is _RecoveryFailure ? error.code : 'please_try_again');
    });
    _running = operation;
    try {
      return await operation;
    } finally {
      if (identical(_running, operation)) _running = null;
    }
  }

  /// Called only after explicit destructive confirmation. Retries use the same
  /// envelope/challenge until the server definitively expires an uncommitted job.
  Future<RecoveryResetView> confirm() => _singleFlight(() async {
        if (simulateTesting() || localTesting()) {
          throw const _RecoveryFailure('recovery_unavailable');
        }
        await SessionWork.checkpoint();
        var revision = SessionWork.revision;
        var stage = await _load();
        final userId = await getSignedInUserId();
        final email = await getSignedInEmailId();
        final cookie = await _storage.read(key: AppString.sessionCookie.string);
        if (userId == null ||
            email == null ||
            cookie == null ||
            cookie.isEmpty ||
            await ModelSetting.getRaw(AppString.signedIn.string) != 'yes') {
          return RecoveryResetView(RecoveryResetPhase.signIn,
              email: stage?['email']);
        }
        if (stage != null) {
          if (!await _sameAccount(stage)) {
            return RecoveryResetView(RecoveryResetPhase.signIn,
                email: stage['email']);
          }
          Map<String, dynamic>? operation;
          var unpreparedIntent = false;
          try {
            operation = (await _status(stage['operationId']))['operation']
                as Map<String, dynamic>?;
          } on _RecoveryFailure catch (error) {
            if (error.code != 'reset_not_found') rethrow;
            unpreparedIntent = stage['phase'] == 'intent';
          }
          await _check(revision);
          if (operation != null && operation['phase'] != 'prepared') {
            return _committed(stage, operation, revision);
          }
          if (operation?['expired'] == true) {
            // The server checks expiry again under its write lock, including after
            // provider preflight; an older confirmation can no longer commit.
            stage = await _newStage(userId, email, cookie,
                expectedGeneration: stage['expectedGeneration']);
            // Replace the expired staging atomically, preserving it on write error.
            final encoded = jsonEncode(stage);
            await SessionWork.run(() async {
              await _check(revision);
              await _storage.write(
                  key: AppString.recoveryResetStage.string, value: encoded);
              if (await _storage.read(
                      key: AppString.recoveryResetStage.string) !=
                  encoded) {
                throw const _RecoveryFailure('staging_unavailable');
              }
            });
          } else if (stage['sessionHash'] != _hash(cookie)) {
            if (unpreparedIntent) {
              // The authenticated server found no preparation for this intent.
              // Keep its keys/challenge so a delayed old request remains safe;
              // the server still binds preparation to the current session.
              stage = {...stage, 'sessionHash': _hash(cookie)};
              await _save(stage, revision);
            } else {
              return RecoveryResetView(RecoveryResetPhase.confirmation,
                  error: 'confirmation_expiring',
                  expiresAt: operation?['expiresAt'],
                  email: stage['email']);
            }
          }
        } else {
          if (await getMasterKey() != null ||
              (await getDeviceUuid()).isNotEmpty) {
            throw const _RecoveryFailure('recovery_unavailable');
          }
          stage = await _newStage(userId, email, cookie);
          await _save(stage, revision, create: true);
        }
        await _validateKeys(stage);
        await _check(revision);
        final draft = _data(await _apiFactory().post(
            endpoint: '/recovery-reset/prepare',
            retryUnauthorized: true,
            jsonBody: {
              'operationId': stage['operationId'],
              'expectedGeneration': stage['expectedGeneration'],
              'challengeHash': _hash(stage['challenge']),
            }));
        await _check(revision);
        if (draft['phase'] != 'prepared') {
          return _committed(stage, draft, revision);
        }
        if (draft['operationId'] != stage['operationId'] ||
            draft['generation'] is! String ||
            !_uuidPattern.hasMatch(draft['generation'])) {
          throw const _RecoveryFailure('staging_mismatch');
        }
        stage = {
          ...stage,
          'generation': draft['generation'],
          'phase': 'confirming'
        };
        await _save(stage, revision);
        final response = await _apiFactory().post(
            endpoint: '/recovery-reset/confirm',
            retryUnauthorized: true,
            jsonBody: {
              'operationId': stage['operationId'],
              'challenge': stage['challenge'],
              'cipher': stage['serverKeys']['cipher'],
              'nonce': stage['serverKeys']['nonce'],
            });
        await _check(revision);
        if (response['success'] != 1) return _inspect(stage, revision);
        return _committed(stage, _data(response), revision);
      });

  Future<Map<String, dynamic>> _newStage(
      String userId, String email, String cookie,
      {String? expectedGeneration}) async {
    final crypto = CryptoUtils(await SodiumSumoInit.init());
    final keys = crypto.generateKeys().getResult()!;
    final random = Random.secure();
    final challenge =
        base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)))
            .replaceAll('=', '');
    final generation = expectedGeneration ??
        ModelSetting.get(AppString.vaultGeneration.string,
            defaultValue: 'legacy');
    return {
      'version': 1,
      'userId': userId,
      'email': email,
      'operationId': const Uuid().v4(),
      'deviceUuid': const Uuid().v4(),
      'challenge': challenge,
      'sessionHash': _hash(cookie),
      'expectedGeneration': generation.isEmpty ? 'legacy' : generation,
      'privateKeys': keys[AppString.privateKeys.string],
      'serverKeys': keys[AppString.serverKeys.string],
      'phase': 'intent',
      'retiredCleared': false
    };
  }

  Future<RecoveryResetView> refresh() => _singleFlight(() async {
        await SessionWork.checkpoint();
        final revision = SessionWork.revision;
        final stage = await _load();
        if (stage == null) {
          if (await getSignedInUserId() == null ||
              await _storage.read(key: AppString.sessionCookie.string) ==
                  null) {
            return const RecoveryResetView(RecoveryResetPhase.signIn);
          }
          return _missingKeys('staging_lost');
        }
        if (!await _sameAccount(stage)) {
          return RecoveryResetView(RecoveryResetPhase.signIn,
              email: stage['email']);
        }
        return _inspect(stage, revision);
      });

  Future<RecoveryResetView> _inspect(
      Map<String, dynamic> stage, String revision,
      {bool activateKeys = false}) async {
    Map<String, dynamic>? operation;
    try {
      operation = (await _status(stage['operationId']))['operation']
          as Map<String, dynamic>?;
    } on _RecoveryFailure catch (error) {
      if (error.code == 'reset_not_found' && stage['phase'] == 'intent') {
        // A missing operation alone says nothing about another pending
        // confirmation. Verify the account-wide status before offering an exit;
        // the discard action verifies it again before clearing local staging.
        final status = await _status(null);
        await _check(revision);
        return RecoveryResetView(RecoveryResetPhase.confirmation,
            email: stage['email'], canReturn: _canDiscard(status));
      }
      rethrow;
    }
    await _check(revision);
    if (operation == null) throw const _RecoveryFailure('please_try_again');
    if (operation['phase'] == 'prepared') {
      final cookie = await _storage.read(key: AppString.sessionCookie.string);
      final changedSession =
          cookie == null || _hash(cookie) != stage['sessionHash'];
      if (!changedSession && operation['requiresFreshSignin'] == true) {
        return RecoveryResetView(RecoveryResetPhase.signIn,
            email: stage['email']);
      }
      return RecoveryResetView(RecoveryResetPhase.confirmation,
          email: stage['email'],
          expiresAt: operation['expiresAt'],
          canReturn: operation['expired'] == true,
          error: changedSession && operation['expired'] != true
              ? 'confirmation_expiring'
              : operation['error']);
    }
    return _committed(stage, operation, revision, activateKeys: activateKeys);
  }

  Future<RecoveryResetView> _committed(Map<String, dynamic> original,
      Map<String, dynamic> operation, String revision,
      {bool activateKeys = false}) async {
    var stage = original;
    if (operation['operationId'] != stage['operationId'] ||
        operation['generation'] != stage['generation'] ||
        operation['envelopeHash'] !=
            _hash(
                '${stage['serverKeys']['cipher']}.${stage['serverKeys']['nonce']}') ||
        !['cleanup_pending', 'ready'].contains(operation['phase'])) {
      throw const _RecoveryFailure('staging_mismatch');
    }
    await _check(revision);
    if (stage['retiredCleared'] != true) {
      if (!await SessionCleanup.instance
          .request(mode: SessionCleanupMode.recovery)) {
        throw const _RecoveryFailure('local_cleanup_pending');
      }
      final retained = await _load();
      if (retained?['operationId'] != stage['operationId'] ||
          !await _sameAccount(retained!)) {
        throw const SessionInvalidated();
      }
      stage = {...retained, 'retiredCleared': true, 'phase': 'waiting'};
      revision = SessionWork.revision;
      await _save(stage, revision);
    }
    return SessionWork.run(() async {
      await _check(revision);
      if (!await _sameAccount(stage)) {
        return RecoveryResetView(RecoveryResetPhase.signIn,
            email: stage['email']);
      }
      await ModelSetting.set(
          AppString.vaultGeneration.string, stage['generation']);
      if (operation['phase'] != 'ready') {
        return RecoveryResetView(RecoveryResetPhase.waiting,
            error: operation['error'],
            notBefore: operation['notBefore'],
            email: stage['email']);
      }
      await _validateKeys(stage);
      final activationStarted =
          ['activating', 'phrase', 'acknowledged'].contains(stage['phase']);
      if (!activationStarted && !activateKeys) {
        return RecoveryResetView(RecoveryResetPhase.generation,
            email: stage['email']);
      }
      if (!activationStarted) {
        // The explicit generation action is durable before activating keys.
        // A crash after a partial secure-store write resumes this same key set.
        stage = {...stage, 'phase': 'activating'};
        await _save(stage, revision);
      }
      for (final entry in (stage['privateKeys'] as Map).entries) {
        await _check(revision);
        await _storage.write(key: entry.key, value: entry.value);
      }
      await _check(revision);
      final acknowledged = stage['phase'] == 'acknowledged';
      stage = {...stage, 'phase': acknowledged ? 'acknowledged' : 'phrase'};
      await _save(stage, revision);
      if (acknowledged) {
        await ModelSetting.set(
            AppString.pendingDeviceUuid.string, stage['deviceUuid']);
      }
      return RecoveryResetView(
          acknowledged
              ? RecoveryResetPhase.registration
              : RecoveryResetPhase.phrase,
          email: stage['email']);
    });
  }

  /// The existing generation notice calls this only after the user continues.
  /// Recheck cloud readiness and use the exact keys bound to this reset.
  Future<RecoveryResetView> generateKeys() => _singleFlight(() async {
        await SessionWork.checkpoint();
        final revision = SessionWork.revision;
        final stage = await _load();
        if (stage == null) return _missingKeys('staging_lost');
        if (!await _sameAccount(stage)) {
          return RecoveryResetView(RecoveryResetPhase.signIn,
              email: stage['email']);
        }
        return _inspect(stage, revision, activateKeys: true);
      });

  Future<void> _validateKeys(Map<String, dynamic> stage) async {
    try {
      final keys = Map<String, dynamic>.from(stage['privateKeys']);
      final expected = {
        AppString.masterKey.string,
        AppString.accessKey.string,
        AppString.fileHashKey.string
      };
      if (keys.length != 3 ||
          !keys.keys.toSet().containsAll(expected) ||
          keys.values.any((value) =>
              value is! String || base64Decode(value).length != 32)) {
        throw const _RecoveryFailure('staging_mismatch');
      }
      final crypto = CryptoUtils(await SodiumSumoInit.init());
      final decrypted = crypto.decryptBytes(
          cipherBytes: base64Decode(stage['serverKeys']['cipher']),
          nonce: base64Decode(stage['serverKeys']['nonce']),
          key: base64Decode(keys[AppString.accessKey.string]));
      if (decrypted.isFailure ||
          base64Encode(decrypted.getResult()![AppString.decrypted.string]) !=
              keys[AppString.masterKey.string] ||
          crypto.getHashingKeyFromMasterKey(keys[AppString.masterKey.string],
                  AppString.fileHashKeyContext.string, 1) !=
              keys[AppString.fileHashKey.string]) {
        throw const _RecoveryFailure('staging_mismatch');
      }
    } catch (_) {
      throw const _RecoveryFailure('staging_mismatch');
    }
  }

  Future<RecoveryResetView> acknowledgePhrase() =>
      _singleFlight(() => SessionWork.run(() async {
            await SessionWork.checkpoint();
            final revision = SessionWork.revision;
            final stage = await _load();
            if (stage == null ||
                !await _sameAccount(stage) ||
                !['phrase', 'acknowledged'].contains(stage['phase'])) {
              throw const _RecoveryFailure('staging_mismatch');
            }
            await _validateKeys(stage);
            await _check(revision);
            await _save({...stage, 'phase': 'acknowledged'}, revision);
            await ModelSetting.set(
                AppString.pendingDeviceUuid.string, stage['deviceUuid']);
            return RecoveryResetView(RecoveryResetPhase.registration,
                email: stage['email']);
          }));

  Future<void> finishRegistration(String deviceUuid) async {
    return SessionWork.run(() async {
      final stage = await _load();
      if (stage == null) return;
      if (stage['phase'] != 'acknowledged' ||
          stage['deviceUuid'] != deviceUuid ||
          !await _sameAccount(stage) ||
          await getDeviceUuid() != deviceUuid ||
          await ModelSetting.getRaw(AppString.vaultGeneration.string) !=
              stage['generation']) {
        throw const SessionInvalidated();
      }
      await _storage.delete(key: AppString.recoveryResetStage.string);
      await ModelSetting.delete(AppString.pendingDeviceUuid.string);
    });
  }

  Future<void> prepareSignin() async {
    if (!await SessionCleanup.instance
        .request(mode: SessionCleanupMode.reauthenticate)) {
      throw const _RecoveryFailure('local_cleanup_pending');
    }
  }

  Future<RecoveryResetView> _missingKeys(String error) async {
    try {
      final status = await _status(null);
      return RecoveryResetView(RecoveryResetPhase.missingKeys,
          error: error,
          notBefore: status['operation']?['notBefore'],
          canReturn: _canDiscard(status));
    } catch (_) {
      return RecoveryResetView(RecoveryResetPhase.missingKeys, error: error);
    }
  }

  static bool _canDiscard(Map<String, dynamic> status) =>
      status['pendingConfirmation'] == false &&
      (status['operation'] == null || status['operation']?['phase'] == 'ready');

  /// Explicitly abandon unusable local staging only after the server proves
  /// no confirmation can still commit and no deletion is pending.
  Future<RecoveryResetView> discardUnavailableStaging() =>
      _singleFlight(() async {
        await SessionWork.checkpoint();
        final revision = SessionWork.revision;
        final status = await _status(null);
        await _check(revision);
        if (!_canDiscard(status)) {
          throw const _RecoveryFailure('reset_in_progress');
        }
        if (!await SessionCleanup.instance.request()) {
          throw const _RecoveryFailure('local_cleanup_pending');
        }
        return const RecoveryResetView(RecoveryResetPhase.signIn);
      });
}
