import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:path_provider/path_provider.dart';

Completer<void>? _refreshJwtCompleter;

class NeonAuth {
  late Dio _dio;
  late PersistCookieJar _cookieJar;
  final SecureStorage _storage;
  final String _neonAuthUrl;
  final logger = AppLogger(prefixes: ["NeonAuth"]);

  final Completer<void> _initCompleter = Completer<void>();
  bool _isInitialized = false;

  NeonAuth({SecureStorage? storage})
      : _storage = storage ?? SecureStorage(),
        _neonAuthUrl = AppEnv.neonAuthUrl {
    if (_neonAuthUrl.isEmpty) {
      throw StateError(
        'NEON_AUTH is empty.',
      );
    }
    _initDio();
  }

  Future<void> _ensureInitialized() async {
    if (_isInitialized) return;
    await _initCompleter.future;
  }

  Future<void> _initDio() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final cookiePath = '${appDocDir.path}/.cookies/';
      _cookieJar = PersistCookieJar(
        storage: FileStorage(cookiePath),
        ignoreExpires: false,
      );

      await _migrateOldCookiesIfNecessary();

      _dio = Dio(BaseOptions(
        baseUrl: _neonAuthUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        contentType: Headers.jsonContentType,
      ));

      _dio.interceptors.add(CookieManager(_cookieJar));

      /* _dio.interceptors.add(LogInterceptor(
        requestHeader: false,
        responseHeader: true,
        requestBody: true,
      )); */
      _isInitialized = true;
      _initCompleter.complete();
    } catch (e) {
      _initCompleter.completeError(e);
    }
  }

  Future<Response> sendOTP(String email) async {
    await _ensureInitialized();
    return await _dio.post(
      '/email-otp/send-verification-otp',
      data: {'email': email, 'type': 'sign-in'},
    );
  }

  Future<String?> verifyOTP(String email, String otp) async {
    await _ensureInitialized();
    final response = await _dio.post(
      '/sign-in/email-otp',
      data: {'email': email, 'otp': otp},
    );

    if (response.statusCode == 200) {
      final data = response.data;
      final String userId = data['user']['id'];

      // Fetch JWT using the session cookie now stored in _cookieJar
      await refreshSessionAndGetJWT();
      return userId;
    }
    return null;
  }

  bool _isTokenExpiringSoon(String token, Duration buffer) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true; // Malformed token, force refresh

      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final String decodedString = utf8.decode(base64Url.decode(normalized));
      final Map<String, dynamic> payloadMap = jsonDecode(decodedString);

      if (!payloadMap.containsKey('exp')) return true;

      // 'exp' is in seconds since epoch
      final expSeconds = payloadMap['exp'] as int;
      final expiryDate = DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000);

      // Check if the current time + 2 minutes is past the expiration date
      final timeWithBuffer = DateTime.now().add(buffer);
      return timeWithBuffer.isAfter(expiryDate);
    } catch (e) {
      logger.error("Failed to decode JWT to check expiry: $e");
      return true; // Fail safe: refresh the token if we can't parse it
    }
  }

  Future<void> refreshSessionAndGetJWT() async {
    if (simulateTesting()) return;
    await _ensureInitialized();
    if (_refreshJwtCompleter != null) return _refreshJwtCompleter!.future;

    _refreshJwtCompleter = Completer<void>();
    try {
      // Check if we even have a JWT cached
      final currentJwt = await _storage.read(key: AppString.jwtToken.string);

      // If we have a JWT and it's fresh, skip network call
      if (currentJwt != null &&
          !_isTokenExpiringSoon(currentJwt, const Duration(minutes: 2))) {
        return;
      }

      // Dio automatically attaches the session cookie from the CookieJar here!
      final response = await _dio.get('/get-session');

      if (response.statusCode == 200) {
        final jwt = response.headers.value('set-auth-jwt');
        if (jwt != null && jwt.isNotEmpty) {
          await _storage.write(key: AppString.jwtToken.string, value: jwt);
          logger.info("Successfully refreshed jwtToken.");
        } else {
          logger.error("Referesh Token success but missing jwt");
          // Resetting device
          await _cookieJar.deleteAll();
          await SyncUtils.resetDevice();
        }
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        await SyncUtils.signout();
      }
    } on DioException catch (e) {
      logger.error("Dio error during JWT refresh: ${e.message}");
    } catch (e, stack) {
      logger.error("Unexpected error during JWT refresh",
          error: e, stackTrace: stack);
    } finally {
      if (!_refreshJwtCompleter!.isCompleted) _refreshJwtCompleter!.complete();
      _refreshJwtCompleter = null;
    }
  }

  Future<bool> signOut() async {
    await _ensureInitialized();
    try {
      final response = await _dio.post('/sign-out');

      await _cookieJar.deleteAll();

      return response.statusCode == 200;
    } catch (e) {
      logger.error('Failed to sign-out: $e');
      return false;
    }
  }

  Future<void> _migrateOldCookiesIfNecessary() async {
    final oldCookieValue =
        await _storage.read(key: AppString.sessionCookie.string);

    if (oldCookieValue != null && oldCookieValue.isNotEmpty) {
      logger.info("Migrating old session cookie to CookieJar...");

      try {
        final cookie =
            Cookie('__Secure-neon-auth.session_token', oldCookieValue);

        final uri = Uri.parse(_neonAuthUrl);
        await _cookieJar.saveFromResponse(uri, [cookie]);

        await _storage.delete(key: AppString.sessionCookie.string);

        logger.info("Migration successful.");
      } catch (e) {
        logger.error("Failed to migrate cookies: $e");
      }
    }
  }
}
