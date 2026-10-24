import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'service_session_cleanup.dart';
import 'service_session_work.dart';
import 'service_session_authentication.dart';
import 'package:http/http.dart' as http;

class AuthRefreshSingleFlight {
  Future<void>? _inFlight;

  Future<void> run(Future<void> Function() refresh) async {
    final existing = _inFlight;
    if (existing != null) return existing;
    final operation = refresh();
    _inFlight = operation;
    try {
      await operation;
    } finally {
      if (identical(_inFlight, operation)) _inFlight = null;
    }
  }
}

class NeonAuth {
  static final AuthRefreshSingleFlight _refreshSingleFlight =
      AuthRefreshSingleFlight();
  final SecureStorage _storage;
  final http.Client _http;
  final String _neonAuthUrl;
  final Duration timeout;
  final logger = AppLogger(prefixes: ["NeonAuth"]);

  NeonAuth({
    SecureStorage? storage,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : _storage = storage ?? SecureStorage(),
        _http = httpClient ?? AppHttpClients.auth,
        _neonAuthUrl = AppEnv.neonAuthUrl {
    if (_neonAuthUrl.isEmpty) {
      throw StateError(
        'NEON_AUTH is empty.',
      );
    }
  }

  String? _getHeader(Map<String, String> headers, String key) {
    final lowerKey = key.toLowerCase();
    for (var entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerKey) {
        return entry.value;
      }
    }
    return null;
  }

  Future<http.Response> sendOTP(String email) =>
      SessionWork.authenticate(() => _sendOTP(email));

  Future<http.Response> _sendOTP(String email) async {
    Uri otpUrl = Uri.parse('$_neonAuthUrl/email-otp/send-verification-otp');
    final response = await _http
        .post(
          otpUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'type':
                'sign-in' // Specifying 'sign-in' triggers the passwordless flow
          }),
        )
        .timeout(timeout);
    await SessionWork.checkpoint();
    return response;
  }

  Future<String?> verifyOTP(String email, String otp) async {
    return SessionWork.authenticate(() => _verifyOTP(email, otp));
  }

  Future<String?> _verifyOTP(String email, String otp) async {
    final sessions = SessionAuthentication.instance;
    final nonce = await sessions.beginAttempt();
    final url = Uri.parse('$_neonAuthUrl/sign-in/email-otp');
    final response = await _http
        .post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'otp': otp,
            // Optional: Pass 'name' or 'image' here if you want to set them during auto-registration
          }),
        )
        .timeout(timeout);
    await SessionWork.checkpoint();
    if (response.statusCode != 200) {
      await sessions.discardAttempt(nonce);
      return null;
    }
    final rawCookie = _getHeader(response.headers, 'set-cookie');
    final match = rawCookie == null
        ? null
        : RegExp(r'__Secure-neon-auth\.session_token=([^;]+)')
            .firstMatch(rawCookie);
    final data = jsonDecode(response.body);
    final user = data is Map ? data['user'] : null;
    if (match == null ||
        user is! Map ||
        user['id'] is! String ||
        (user['id'] as String).isEmpty ||
        user['email'] is! String ||
        (user['email'] as String).trim().toLowerCase() !=
            email.trim().toLowerCase()) {
      await sessions.discardAttempt(nonce);
      return null;
    }
    await sessions.stageVerified(
        nonce,
        AuthenticatedAccount(
            id: user['id'],
            email: user['email'],
            service: 'neon',
            cookie: match.group(1)!));
    return user['id'];
  }

  static bool _noSession(http.Response response) {
    try {
      final value = jsonDecode(response.body);
      return value == null ||
          value is Map &&
              value.containsKey('session') &&
              value.containsKey('user') &&
              value['session'] == null &&
              value['user'] == null;
    } catch (_) {
      return false;
    }
  }

  /// A new sign-in must use its own cookie, never an older still-valid JWT.
  Future<String> refreshForSignin(AuthenticatedAccount account) =>
      SessionWork.authenticate(() async {
        final response =
            await _http.get(Uri.parse('$_neonAuthUrl/get-session'), headers: {
          'Cookie': '__Secure-neon-auth.session_token=${account.cookie};',
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        }).timeout(timeout);
        await SessionWork.checkpoint();
        if (response.statusCode == 401 ||
            response.statusCode == 403 ||
            response.statusCode == 200 && _noSession(response)) {
          throw const VerifiedSigninExpired();
        }
        final jwt = _getHeader(response.headers, 'set-auth-jwt');
        if (response.statusCode != 200 || jwt == null || jwt.isEmpty) {
          throw StateError('Fresh authentication token is unavailable');
        }
        final pieces = jwt.split('.');
        if (pieces.length != 3) {
          throw StateError('Authentication token is incomplete');
        }
        final claims = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(pieces[1]))));
        if (claims is! Map ||
            claims['sub'] != account.id ||
            claims['email'] is! String ||
            (claims['email'] as String).trim().toLowerCase() !=
                account.email.trim().toLowerCase()) {
          throw const VerifiedSigninExpired();
        }
        return jwt;
      });

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
      logger.debug("Token Expiry: $expiryDate");
      // Check if the current time + 2 minutes is past the expiration date
      final timeWithBuffer = DateTime.now().add(buffer);
      return timeWithBuffer.isAfter(expiryDate);
    } catch (e) {
      logger.error("Failed to decode JWT to check expiry: $e");
      return true; // Fail safe: refresh the token if we can't parse it
    }
  }

  Future<void> refreshSessionAndGetJWT() async {
    await SessionWork.run(
        () => _refreshSingleFlight.run(_refreshSessionAndGetJWT));
  }

  Future<void> _refreshSessionAndGetJWT() async {
    logger.info("refreshSessionAndGetJWT called");
    if (simulateTesting()) {
      logger.info("Skipping refresh due to simulateTesting()");
      return;
    }
    try {
      final currentJwtToken =
          await _storage.read(key: AppString.jwtToken.string);

      if (currentJwtToken != null) {
        final needsRefresh = _isTokenExpiringSoon(
          currentJwtToken,
          const Duration(minutes: 2),
        );

        if (!needsRefresh) {
          // Token is still valid and not within the 2-minute buffer. Abort refresh.
          return;
        }
        logger
            .info("JWT is expiring within 2 minutes. Proceeding with refresh.");
      } else {
        logger.error("Can't refresh, Current JWT Token is Null");
      }

      final sessionCookie =
          await _storage.read(key: AppString.sessionCookie.string);
      if (sessionCookie == null || sessionCookie.isEmpty) {
        logger.error("Session cookie not found while refreshing JWT.");
        await SessionCleanup.instance.expiredAuthentication();
        return;
      }

      final response = await _http.get(
        Uri.parse('$_neonAuthUrl/get-session'),
        headers: {
          'Cookie': '__Secure-neon-auth.session_token=$sessionCookie;',
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
      ).timeout(timeout);

      if (response.statusCode == 200) {
        if (_noSession(response)) {
          await SessionCleanup.instance.expiredAuthentication();
          return;
        }
        final jwt = _getHeader(response.headers, 'set-auth-jwt');
        if (jwt != null && jwt.isNotEmpty) {
          await _storage.write(key: AppString.jwtToken.string, value: jwt);
          logger.info("Successfully refreshed jwtToken.");
        } else {
          logger.error(
              "Server returned 200 but 'set-auth-jwt' header was missing.");
          // An incomplete response does not establish that the session is
          // invalid. Preserve local keys/data so the next refresh can retry.
        }
      }
      // Legit situations to sign out: Session is definitively invalid or expired
      else if (response.statusCode == 401 || response.statusCode == 403) {
        logger.warning(
            "Authentication expired (Status: ${response.statusCode}); requiring sign-in.");
        await SessionCleanup.instance.expiredAuthentication();
      }
      // 5xx (Server Errors), 429 (Rate Limit), etc. Do NOT sign out.
      else {
        logger.error(
            "Failed to refresh session. Server returned status: ${response.statusCode}. Retrying later.");
      }
    } on SessionInvalidated {
      rethrow;
    } on SocketException catch (e) {
      // Standard exception for no internet connection or DNS lookup failure
      logger.warning("No internet connection while refreshing JWT: $e");
    } on TimeoutException catch (e) {
      // Request took too long (poor network conditions)
      logger.warning("Timeout while refreshing JWT: $e");
    } catch (e, stackTrace) {
      // Catch-all for formatting errors, parse errors, etc.
      logger.error("Unexpected error during JWT refresh",
          error: e, stackTrace: stackTrace);
    }
  }

  Future<bool> signOut() async {
    bool success = false;
    String? sessionCookie =
        await _storage.read(key: AppString.sessionCookie.string);
    if (sessionCookie != null) {
      try {
        final url = Uri.parse('$_neonAuthUrl/sign-out');

        // 2. Call the sign-out endpoint to invalidate the session on the server
        final response = await _http
            .post(url,
                headers: {
                  // Provide the session cookie so the server knows what to destroy
                  'Cookie': '__Secure-neon-auth.session_token=$sessionCookie',
                  'Content-Type': 'application/json',
                  'Origin': _neonAuthUrl
                },
                body: '{}')
            .timeout(timeout);

        if (response.statusCode != 200) {
          // Log the error, but continue to clear local storage anyway
          logger.error(
              'Server sign-out error: ${response.statusCode} - ${response.body}');
        } else {
          success = true;
        }
      } catch (e) {
        // Handle network errors gracefully
        logger.error('Failed to reach auth server during sign-out: $e');
      }
    } else {
      logger.error("Error signing out", error: "Session cookie not found");
    }
    return success;
  }
}
