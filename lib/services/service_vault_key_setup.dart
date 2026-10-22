import 'dart:convert';

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

enum VaultKeySetupPhase {
  generation,
  phrase,
  registration,
  recovery,
  unavailable
}

class VaultKeySetupResult {
  const VaultKeySetupResult(this.phase);
  final VaultKeySetupPhase phase;
}

/// A candidate is durable before publication and remains until acknowledgment
/// and registration. Its private keys become active only after server acceptance.
class VaultKeySetupService {
  VaultKeySetupService._() : _api = BackendApi.new;
  static final instance = VaultKeySetupService._();
  @visibleForTesting
  VaultKeySetupService.test({required BackendApi Function() apiFactory})
      : _api = apiFactory;
  final BackendApi Function() _api;
  final SecureStorage _storage = SecureStorage();
  Future<VaultKeySetupResult>? _running;
  String get _stageKey => AppString.vaultKeySetupStage.string;

  Future<bool> hasPending() => _storage.containsKey(key: _stageKey);

  Future<Map<String, dynamic>?> _load() async {
    final raw = await _storage.read(key: _stageKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['userId'] is! String ||
        decoded['email'] is! String ||
        decoded['generation'] is! String ||
        decoded['deviceUuid'] is! String ||
        !Uuid.isValidUUID(fromString: decoded['deviceUuid']) ||
        decoded['privateKeys'] is! Map ||
        decoded['serverKeys'] is! Map ||
        !['intent', 'claimed', 'phrase', 'acknowledged']
            .contains(decoded['phase'])) {
      throw StateError('Key creation staging is unavailable');
    }
    return decoded;
  }

  Future<String?> pendingEmail() async {
    try {
      return (await _load())?['email'] as String?;
    } catch (_) {
      return null;
    }
  }

  String get _generation => ModelSetting.get(AppString.vaultGeneration.string,
      defaultValue: 'legacy');

  Future<void> _check(String revision, Map<String, dynamic> stage) async {
    await SessionWork.checkpoint();
    if (revision != SessionWork.revision ||
        ModelSetting.get(AppString.signedIn.string) != 'yes' ||
        (_generation.isEmpty ? 'legacy' : _generation) != stage['generation']) {
      throw const SessionInvalidated();
    }
    if (await getSignedInUserId() != stage['userId']) {
      // Reauthentication may select a different account. Keep the original
      // candidate, but return to sign-in instead of stranding its setup UI.
      await SessionCleanup.instance
          .request(mode: SessionCleanupMode.reauthenticate);
      throw const SessionInvalidated();
    }
  }

  Future<void> _save(Map<String, dynamic> stage, String revision) async {
    await _check(revision, stage);
    final raw = jsonEncode(stage);
    await _storage.write(key: _stageKey, value: raw);
    await _check(revision, stage);
    if (await _storage.read(key: _stageKey) != raw) {
      throw StateError('Key creation staging is unavailable');
    }
  }

  Future<void> _validate(Map<String, dynamic> stage) async {
    final keys = Map<String, dynamic>.from(stage['privateKeys']);
    final expected = {
      AppString.masterKey.string,
      AppString.accessKey.string,
      AppString.fileHashKey.string
    };
    if (keys.length != expected.length ||
        !keys.keys.toSet().containsAll(expected) ||
        keys.values.any(
            (value) => value is! String || base64Decode(value).length != 32)) {
      throw StateError('Invalid key creation staging');
    }
    final crypto = CryptoUtils(await SodiumSumoInit.init());
    final envelope = stage['serverKeys'] as Map;
    final decrypted = crypto.decryptBytes(
        cipherBytes: base64Decode(envelope['cipher']),
        nonce: base64Decode(envelope['nonce']),
        key: base64Decode(keys[AppString.accessKey.string]));
    if (decrypted.isFailure ||
        base64Encode(decrypted.getResult()![AppString.decrypted.string]) !=
            keys[AppString.masterKey.string] ||
        crypto.getHashingKeyFromMasterKey(keys[AppString.masterKey.string],
                AppString.fileHashKeyContext.string, 1) !=
            keys[AppString.fileHashKey.string]) {
      throw StateError('Invalid key creation staging');
    }
  }

  Future<VaultKeySetupResult> _single(
      Future<VaultKeySetupResult> Function() action) async {
    if (_running case final running?) return running;
    final operation = SessionWork.run(action).onError<Object>((error, stack) {
      if (error is SessionInvalidated) throw error;
      return const VaultKeySetupResult(VaultKeySetupPhase.unavailable);
    });
    _running = operation;
    try {
      return await operation;
    } finally {
      if (identical(_running, operation)) _running = null;
    }
  }

  Future<VaultKeySetupResult> _activate(
      Map<String, dynamic> stage, String revision) async {
    await _validate(stage);
    final acknowledged = stage['phase'] == 'acknowledged';
    stage = {...stage, 'phase': acknowledged ? 'acknowledged' : 'claimed'};
    await _save(stage, revision);
    for (final entry in (stage['privateKeys'] as Map).entries) {
      await _check(revision, stage);
      await _storage.write(key: entry.key, value: entry.value);
    }
    await _check(revision, stage);
    await _storage.write(
        key: AppString.keyCipher.string, value: stage['serverKeys']['cipher']);
    await _check(revision, stage);
    await _storage.write(
        key: AppString.keyNonce.string, value: stage['serverKeys']['nonce']);
    stage = {...stage, 'phase': acknowledged ? 'acknowledged' : 'phrase'};
    await _save(stage, revision);
    if (acknowledged) {
      await ModelSetting.set(
          AppString.pendingDeviceUuid.string, stage['deviceUuid']);
    }
    return VaultKeySetupResult(acknowledged
        ? VaultKeySetupPhase.registration
        : VaultKeySetupPhase.phrase);
  }

  Future<VaultKeySetupResult> _reconcile(
      Map<String, dynamic> stage, String revision) async {
    await _check(revision, stage);
    if (simulateTesting()) return _activate(stage, revision);
    final reply = await _api().get(endpoint: '/keys');
    await _check(revision, stage);
    if (reply['success'] == 0 && reply['message'].toString() == '1') {
      return VaultKeySetupResult(stage['phase'] == 'intent'
          ? VaultKeySetupPhase.generation
          : VaultKeySetupPhase.unavailable);
    }
    if (reply['success'] != 1 || reply['data'] is! Map) {
      return const VaultKeySetupResult(VaultKeySetupPhase.unavailable);
    }
    final data = reply['data'] as Map;
    final currentGeneration = data['vault_generation'] ?? 'legacy';
    if (currentGeneration != stage['generation']) {
      // Only an explicit, valid generation from an authenticated response
      // proves this candidate belongs to a retired vault. A partial or
      // malformed response must never authorize erasing private staging.
      if (data['vault_generation'] is! String ||
          (currentGeneration != 'legacy' &&
              !Uuid.isValidUUID(fromString: currentGeneration))) {
        return const VaultKeySetupResult(VaultKeySetupPhase.unavailable);
      }
      await SessionCleanup.instance.request();
      throw const SessionInvalidated();
    }
    if (data['cipher'] == stage['serverKeys']['cipher'] &&
        data['nonce'] == stage['serverKeys']['nonce']) {
      return _activate(stage, revision);
    }
    if (data['cipher'] == null &&
        data['nonce'] == null &&
        data['key_state'] == 'missing' &&
        stage['phase'] == 'intent') {
      return const VaultKeySetupResult(VaultKeySetupPhase.generation);
    }
    if (data['cipher'] is String &&
        data['nonce'] is String &&
        stage['phase'] == 'intent') {
      // The other device's accepted envelope is authoritative. This candidate
      // was never activated; discard only its private staging and recover theirs.
      await _check(revision, stage);
      await _storage.delete(key: _stageKey);
      return const VaultKeySetupResult(VaultKeySetupPhase.recovery);
    }
    return const VaultKeySetupResult(VaultKeySetupPhase.unavailable);
  }

  Future<VaultKeySetupResult> resume() => _single(() async {
        final stage = await _load();
        if (stage == null) {
          return const VaultKeySetupResult(VaultKeySetupPhase.generation);
        }
        return _reconcile(stage, SessionWork.revision);
      });

  Future<VaultKeySetupResult> generate() => _single(() async {
        await SessionWork.checkpoint();
        final revision = SessionWork.revision;
        var stage = await _load();
        if (stage == null) {
          final userId = await getSignedInUserId();
          final email = await getSignedInEmailId();
          if (userId == null || email == null || await getMasterKey() != null) {
            throw const SessionInvalidated();
          }
          final crypto = CryptoUtils(await SodiumSumoInit.init());
          final keys = crypto.generateKeys().getResult()!;
          stage = {
            'version': 1,
            'userId': userId,
            'email': email,
            'generation': _generation.isEmpty ? 'legacy' : _generation,
            'deviceUuid': const Uuid().v4(),
            'privateKeys': keys[AppString.privateKeys.string],
            'serverKeys': keys[AppString.serverKeys.string],
            'phase': 'intent'
          };
          await _save(stage, revision);
        }
        await _check(revision, stage);
        await _validate(stage);
        if (stage['phase'] != 'intent') return _reconcile(stage, revision);
        if (simulateTesting()) return _activate(stage, revision);
        final response = await _api().post(endpoint: '/keys', jsonBody: {
          ...Map<String, dynamic>.from(stage['serverKeys']),
          'expectedGeneration': stage['generation']
        });
        await _check(revision, stage);
        if (response['success'] == 1) return _activate(stage, revision);
        // A lost response is recoverable by comparing the authoritative envelope;
        // a different winner is never replaced or activated with this candidate.
        return _reconcile(stage, revision);
      });

  Future<void> acknowledge() => SessionWork.run(() async {
        final stage = await _load();
        if (stage == null) return;
        final revision = SessionWork.revision;
        await _check(revision, stage);
        if (!['phrase', 'acknowledged'].contains(stage['phase'])) {
          throw StateError('Save the recovery phrase before registration');
        }
        await _validate(stage);
        await _save({...stage, 'phase': 'acknowledged'}, revision);
        await ModelSetting.set(
            AppString.pendingDeviceUuid.string, stage['deviceUuid']);
      });

  Future<String?> registrationUuid() async {
    final stage = await _load();
    if (stage == null) return null;
    await _check(SessionWork.revision, stage);
    if (stage['phase'] != 'acknowledged') {
      throw StateError('Save the recovery phrase before registration');
    }
    return stage['deviceUuid'] as String;
  }

  Future<void> finishRegistration(String deviceUuid) =>
      SessionWork.run(() async {
        final stage = await _load();
        if (stage == null) return;
        await _check(SessionWork.revision, stage);
        if (stage['phase'] != 'acknowledged' ||
            stage['deviceUuid'] != deviceUuid ||
            await getDeviceUuid() != deviceUuid) {
          throw const SessionInvalidated();
        }
        await _storage.delete(key: _stageKey);
        await ModelSetting.delete(AppString.pendingDeviceUuid.string);
      });
}
