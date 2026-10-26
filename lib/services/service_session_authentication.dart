import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/model_item.dart';
import '../models/model_profile.dart';
import '../models/model_setting.dart';
import '../storage/storage_secure.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import 'service_backend.dart';
import 'service_events.dart';
import 'service_session_cleanup.dart';
import 'service_session_work.dart';

/// Identity comes from the authenticated provider response, never a form field.
class AuthenticatedAccount {
  const AuthenticatedAccount(
      {required this.id,
      required this.email,
      required this.service,
      this.cookie,
      this.jwt});
  final String id, email, service;
  final String? cookie, jwt;
  String get ownerHash => SessionCleanup.authenticationOwnerHash(id, email);
  Map<String, dynamic> toJson() => {
        'userId': id,
        'email': email,
        'service': service,
        'cookie': cookie,
        'jwt': jwt
      };
  AuthenticatedAccount withJwt(String value) => AuthenticatedAccount(
      id: id, email: email, service: service, cookie: cookie, jwt: value);
  static AuthenticatedAccount? fromJson(Map value) {
    if (value['userId'] is! String ||
        (value['userId'] as String).isEmpty ||
        value['email'] is! String ||
        !(value['email'] as String).contains('@') ||
        !['neon', 'local-test', 'simulation'].contains(value['service']) ||
        (value['cookie'] != null && value['cookie'] is! String) ||
        (value['jwt'] != null && value['jwt'] is! String)) {
      return null;
    }
    if (value['service'] != 'simulation' &&
        (value['cookie'] is! String || (value['cookie'] as String).isEmpty)) {
      return null;
    }
    return AuthenticatedAccount(
        id: value['userId'],
        email: value['email'],
        service: value['service'],
        cookie: value['cookie'],
        jwt: value['jwt']);
  }
}

typedef AuthenticationApiFactory = BackendApi Function(
    AuthenticatedAccount account, String device, String generation);

class VerifiedSigninExpired implements Exception {
  const VerifiedSigninExpired();
}

class SessionAuthentication {
  SessionAuthentication._() : _apiFactory = _api;
  static final instance = SessionAuthentication._();
  @visibleForTesting
  SessionAuthentication.test({required AuthenticationApiFactory apiFactory})
      : _apiFactory = apiFactory;
  final AuthenticationApiFactory _apiFactory;
  final _storage = SecureStorage();
  Future<void>? _running;
  String? _runningNonce;
  static String get _key => AppString.authenticationCandidate.string;

  static BackendApi _api(
          AuthenticatedAccount account, String device, String generation) =>
      BackendApi(
        accessTokenProvider: () async => account.service == 'local-test'
            ? AppEnv.localTestAuthToken
            : account.jwt,
        signedEmailIdProvider: () async => account.email,
        deviceUuidProvider: () async => device,
        sessionCookieProvider: () async => account.cookie,
        vaultGenerationOverride: generation,
        localTestingProvider: () => account.service == 'local-test',
        enforceDeviceRevocation: false,
        requireFreshAuthentication: true,
        refreshAuth: () async {},
      );

  Future<T> _candidate<T>(Future<T> Function() action) =>
      SessionWork.authenticate(() => SessionCleanup.instance
          .withAuthenticationState(SessionWork.revision,
              () => StorageSqlite.instance.runInTransaction(action)));

  Future<Map<String, dynamic>?> _read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      if (value is Map<String, dynamic> &&
          value['version'] == 1 &&
          value['nonce'] is String &&
          value['revision'] is String) {
        return value;
      }
    } catch (_) {/* A damaged candidate cannot authorize vault access. */}
    return null;
  }

  Future<String> beginAttempt() => _candidate(() async {
        final nonce = const Uuid().v4();
        await _storage.write(
            key: _key,
            value: jsonEncode({
              'version': 1,
              'nonce': nonce,
              'revision': SessionWork.revision,
              'verified': false
            }));
        return nonce;
      });

  Future<void> discardCandidate() =>
      _candidate(() => _storage.delete(key: _key));

  Future<void> discardAttempt(String nonce) => _candidate(() async {
        if ((await _read())?['nonce'] == nonce) {
          await _storage.delete(key: _key);
        }
      });

  Future<void> stageVerified(String nonce, AuthenticatedAccount account) =>
      _candidate(() async {
        if (AuthenticatedAccount.fromJson(account.toJson()) == null) {
          throw StateError('Incomplete authenticated account');
        }
        final value = await _read();
        if (value?['nonce'] != nonce ||
            value?['revision'] != SessionWork.revision) {
          throw const SessionInvalidated();
        }
        await _storage.write(
            key: _key,
            value:
                jsonEncode({...value!, ...account.toJson(), 'verified': true}));
      });

  Future<Map<String, dynamic>?> _pending() =>
      SessionWork.authenticate(() async {
        final value = await _read();
        await SessionWork.checkpoint();
        if (value == null || value['verified'] != true) return null;
        final account = AuthenticatedAccount.fromJson(value);
        if (account == null) return null;
        final state = await SessionCleanup.instance.authenticationState();
        await SessionWork.checkpoint();
        if (value['revision'] != SessionWork.revision &&
            !(state['authenticationRequired'] == true &&
                state['authenticationTarget'] == account.ownerHash)) {
          return null;
        }
        return value;
      });

  Future<AuthenticatedAccount?> pendingAccount() async {
    final value = await _pending();
    return value == null ? null : AuthenticatedAccount.fromJson(value);
  }

  Future<void> completeSignin({
    required Future<String> Function(AuthenticatedAccount account) refreshNeon,
  }) async {
    final value = await _pending();
    if (value == null) throw StateError('Verified sign-in is unavailable');
    if (_running case final running?) {
      if (_runningNonce == value['nonce']) return running;
      try {
        await running;
      } catch (_) {/* A newer attempt supersedes it. */}
      return completeSignin(refreshNeon: refreshNeon);
    }
    _runningNonce = value['nonce'];
    final operation = _complete(value, refreshNeon);
    _running = operation;
    try {
      await operation;
    } finally {
      if (identical(_running, operation)) {
        _running = null;
        _runningNonce = null;
      }
    }
  }

  Future<void> _complete(Map<String, dynamic> value,
      Future<String> Function(AuthenticatedAccount) refreshNeon) async {
    var account = AuthenticatedAccount.fromJson(value)!;
    final nonce = value['nonce'] as String;
    // A completed cleanup can advance the revision before a crash; its guarded
    // target authorizes only this verified candidate to continue afterward.
    await _candidate(() async {
      await _assertNonce(nonce);
      value = {...value, 'revision': SessionWork.revision};
      await _storage.write(key: _key, value: jsonEncode(value));
    });
    if (account.service == 'neon') {
      String jwt;
      try {
        jwt = await SessionWork.authenticate(() => refreshNeon(account));
      } on VerifiedSigninExpired {
        await discardAttempt(nonce);
        rethrow;
      }
      account = account.withJwt(jwt);
      await stageVerified(nonce, account);
    }
    bool retain;
    try {
      retain = await SessionWork.authenticate(() => _canRetain(account));
    } on VerifiedSigninExpired {
      await discardAttempt(nonce);
      rethrow;
    }
    // An application API rejection does not establish that the provider session
    // ended. Keep its verified candidate and the private-data hold for Continue;
    // the next attempt rechecks Neon before retrying backend authorization.
    final state = await SessionCleanup.instance.authenticationState();
    final switched = state['mode'] == SessionCleanupMode.accountSwitch.name &&
        state['authenticationTarget'] == account.ownerHash;
    if (!retain && !switched || !SessionWork.authenticationRequired) {
      final completed = await SessionWork.authenticate(() =>
          SessionCleanup.instance.request(
              mode: retain
                  ? SessionCleanupMode.authenticationExpired
                  : SessionCleanupMode.accountSwitch,
              authenticationTarget: account.ownerHash,
              authenticationNonce: nonce));
      if (!completed) {
        throw StateError('Local account transition remains pending');
      }
    }
    final revision = SessionWork.revision;
    await SessionCleanup.instance.activateAuthentication(
        expectedRevision: revision,
        writeCredentials: () async {
          final current = await _assertNonce(nonce);
          if (AuthenticatedAccount.fromJson(current)?.ownerHash !=
              account.ownerHash) {
            throw const SessionInvalidated();
          }
          if (account.cookie != null) {
            await _storage.write(
                key: AppString.sessionCookie.string, value: account.cookie!);
          }
          if (account.jwt != null) {
            await _storage.write(
                key: AppString.jwtToken.string, value: account.jwt!);
          }
          final existing = await ModelProfile.get();
          if (existing?.id != account.id ||
              existing?.email?.trim().toLowerCase() !=
                  account.email.trim().toLowerCase()) {
            await (await ModelProfile.fromMap(
                    {'id': account.id, 'email': account.email}))
                .insert();
          }
          await ModelItem.ensureVaultRoot();
          await ModelSetting.set(AppString.signedIn.string, 'yes');
          await ModelSetting.delete(AppString.recoveryReauthentication.string);
          await ModelSetting.delete(AppString.otpSentAt.string);
          await ModelSetting.delete(AppString.otpSentTo.string);
          if (account.service == 'simulation') {
            await ModelSetting.set(AppString.simulateTesting.string, 'yes');
          } else {
            await ModelSetting.delete(AppString.simulateTesting.string);
          }
          if (account.service == 'local-test') {
            await ModelSetting.set(AppString.localTesting.string, 'yes');
          } else {
            await ModelSetting.delete(AppString.localTesting.string);
          }
          final settings =
              await StorageSqlite.instance.getAll(Tables.settings.string);
          ModelSetting.settingJson = {
            for (final entry in settings) entry['id']: entry['value']
          };
          if (await ModelSetting.getRaw(AppString.signedIn.string) != 'yes' ||
              (await ModelProfile.get())?.id != account.id ||
              (account.cookie != null &&
                  await _storage.read(key: AppString.sessionCookie.string) !=
                      account.cookie) ||
              (account.jwt != null &&
                  await _storage.read(key: AppString.jwtToken.string) !=
                      account.jwt)) {
            throw StateError('Authentication activation is incomplete');
          }
        });
    try {
      await _candidate(() async {
        if ((await _read())?['nonce'] == nonce) {
          await _storage.delete(key: _key);
        }
      });
    } catch (_) {
      /* Its retired revision cannot authorize another activation. */
    }
    EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'authentication',
        key: EventKey.authenticated));
  }

  Future<Map<String, dynamic>> _assertNonce(String nonce) async {
    final value = await _read();
    if (value?['nonce'] != nonce || value?['verified'] != true) {
      throw const SessionInvalidated();
    }
    return value!;
  }

  Future<bool> _canRetain(AuthenticatedAccount account) async {
    final state = await SessionCleanup.instance.authenticationState();
    final profile = await ModelProfile.get();
    final owner = state['authenticationRequired'] == true
        ? state['ownerHash']
        : profile?.email?.isNotEmpty == true
            ? SessionCleanup.authenticationOwnerHash(
                profile!.id, profile.email!)
            : null;
    final sameOwner = owner == account.ownerHash;
    var legacyStaging = false;
    var foreignStaging = false;
    for (final key in [
      AppString.recoveryResetStage,
      AppString.vaultKeySetupStage
    ]) {
      final raw = await _storage.read(key: key.string);
      if (raw == null) continue;
      Object? stage;
      try {
        stage = jsonDecode(raw);
      } catch (_) {/* Unprovable owner. */}
      if (stage is Map &&
          stage['userId'] == account.id &&
          stage['email'] is String &&
          (stage['email'] as String).trim().toLowerCase() ==
              account.email.trim().toLowerCase()) {
        legacyStaging = true;
      } else {
        foreignStaging = true;
      }
    }
    legacyStaging = legacyStaging && !foreignStaging;
    if (account.service == 'simulation') {
      return !foreignStaging && (sameOwner || legacyStaging);
    }
    final api = _apiFactory(account, '', '');
    Map<String, dynamic> reply;
    try {
      reply = await api.get(endpoint: '/keys');
    } finally {
      api.close();
    }
    if (reply['success'] != 1) {
      if (reply['message'] == 'sign_in_again') {
        throw const VerifiedSigninExpired();
      }
      if (reply['success'] == 0 &&
          (reply['message'].toString() == '1' ||
              ['vault_reset_pending', 'vault_replaced', 'account_removed']
                  .contains(reply['reason']))) {
        return legacyStaging;
      }
      throw StateError('Authenticated vault validation is unavailable');
    }
    final data = reply['data'];
    if (data is! Map ||
        !data.containsKey('cipher') ||
        !data.containsKey('nonce') ||
        !((data['cipher'] is String && data['nonce'] is String) ||
            (data['key_state'] == 'missing' &&
                data['cipher'] == null &&
                data['nonce'] == null))) {
      throw StateError('Authenticated vault response is incomplete');
    }
    if (legacyStaging) return true; // Its owning protocol validates activation.
    if (!sameOwner || foreignStaging || data['key_state'] == 'missing') {
      return false;
    }
    final generation =
        await ModelSetting.getRaw(AppString.vaultGeneration.string);
    final remoteGeneration = data['vault_generation'] ?? 'legacy';
    if (remoteGeneration is! String) {
      throw StateError('Vault generation is unavailable');
    }
    if (generation.isNotEmpty && generation != remoteGeneration) return false;
    final cipher = await _storage.read(key: AppString.keyCipher.string);
    final nonce = await _storage.read(key: AppString.keyNonce.string);
    if (cipher != null &&
        nonce != null &&
        (cipher != data['cipher'] || nonce != data['nonce'])) {
      return false;
    }
    final device = await getDeviceUuid();
    if (device.isEmpty) {
      return await getMasterKey() == null ||
          cipher == data['cipher'] && nonce == data['nonce'];
    }
    final membership = _apiFactory(account, device, remoteGeneration);
    Map<String, dynamic> status;
    try {
      status = await membership
          .get(endpoint: '/devices', queryParameters: {'device_uuid': device});
    } finally {
      membership.close();
    }
    if (status['success'] == 1 &&
        status['data'] is Map &&
        status['data']['id'] == device &&
        [0, 1].contains(status['data']['active'])) {
      return status['data']['active'] == 1;
    }
    // Released backends also represent an absent own-device registration as
    // an explicit null/empty successful result or NO_USER.
    if (status['success'] == 1 &&
            status.containsKey('data') &&
            (status['data'] == null ||
                status['data'] is Map && status['data'].isEmpty) ||
        status['success'] == 0 && status['message'].toString() == '1') {
      return false;
    }
    if (status['success'] == 0 &&
        [
          'device_revoked',
          'vault_replaced',
          'account_removed',
          'vault_reset_pending'
        ].contains(status['reason'])) {
      return false;
    }
    throw StateError('Device validation is unavailable');
  }
}
