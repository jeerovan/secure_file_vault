import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:http/http.dart' as http;

import '../models/model_item.dart';
import '../models/model_profile.dart';
import '../models/model_setting.dart';

Completer<void>? _refreshJwtCompleter;

class NeonAuth {
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
        _http = httpClient ?? http.Client(),
        _neonAuthUrl = AppEnv.neonAuthUrl {
    if (_neonAuthUrl.isEmpty) {
      throw StateError(
        'NEON_AUTH is empty.',
      );
    }
  }

  Future<http.Response> sendOTP(String email) async {
    Uri otpUrl = Uri.parse('$_neonAuthUrl/email-otp/send-verification-otp');
    final response = await _http.post(
      otpUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'type': 'sign-in' // Specifying 'sign-in' triggers the passwordless flow
      }),
    );
    return response;
  }

  Future<bool> verifyOTP(String email, String otp) async {
    final url = Uri.parse('$_neonAuthUrl/sign-in/email-otp');
    final response = await _http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'otp': otp,
        // Optional: Pass 'name' or 'image' here if you want to set them during auto-registration
      }),
    );
    bool success = false;
    if (response.statusCode == 200) {
      // Extract the full cookie string from the header
      final rawCookie = response.headers['set-cookie'];
      if (rawCookie != null) {
        // Parse out the __Secure-neon-auth.session_token
        final cookieMatch = RegExp(r'__Secure-neon-auth\.session_token=([^;]+)')
            .firstMatch(rawCookie);
        if (cookieMatch != null) {
          final sessionCookie = cookieMatch.group(1)!;
          await _storage.write(
              key: AppString.sessionCookie.string, value: sessionCookie);

          // create profile before fetch jwtToken
          final data = jsonDecode(response.body);
          final user = data['user'];

          ModelProfile profile = await ModelProfile.fromMap(
              {"id": user['id'], "email": user['email']});
          await profile.insert();

          ModelItem deviceItem = await ModelItem.fromMap({
            "id": "fife",
            "name": "FiFe",
            "is_folder": 1,
          });
          await deviceItem.insert();
          await ModelSetting.set(AppString.signedIn.string, "yes");
          success = true;
          // Immediately fetch the JWT
          await refreshSessionAndGetJWT();
        }
      }
    }
    return success;
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
    if (_refreshJwtCompleter != null) {
      logger.info("JWT refresh already in progress. Waiting...");
      return _refreshJwtCompleter!.future;
    }

    _refreshJwtCompleter = Completer<void>();
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
        logger.info(
            "JWT is missing or expiring within 2 minutes. Proceeding with refresh.");
      }

      final sessionCookie =
          await _storage.read(key: AppString.sessionCookie.string);

      if (sessionCookie == null) {
        logger.error("Session cookie not found while refreshing JWT.");
        await SyncUtils.signout();
        return;
      }

      final response = await _http.get(
        Uri.parse('$_neonAuthUrl/get-session'),
        headers: {
          'Cookie': '__Secure-neon-auth.session_token=$sessionCookie',
          'Content-Type': 'application/json'
        },
      ).timeout(const Duration(seconds: 20)); // Prevents hanging network calls

      if (response.statusCode == 200) {
        final jwt = response.headers['set-auth-jwt'];
        if (jwt != null && jwt.isNotEmpty) {
          await _storage.write(key: AppString.jwtToken.string, value: jwt);
          logger.info("Successfully refreshed jwtToken.");
        } else {
          logger.warning(
              "Server returned 200 but 'set-auth-jwt' header was missing.");
        }
      }
      // Legit situations to sign out: Session is definitively invalid or expired
      else if (response.statusCode == 401 || response.statusCode == 403) {
        logger.warning(
            "Session invalid or expired (Status: ${response.statusCode}). Forcing sign-out.");
        await SyncUtils.signout();
      }
      // 5xx (Server Errors), 429 (Rate Limit), etc. Do NOT sign out.
      else {
        logger.error(
            "Failed to refresh session. Server returned status: ${response.statusCode}. Retrying later.");
      }
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
    } finally {
      // Always complete and reset the lock, regardless of success or failure
      if (!_refreshJwtCompleter!.isCompleted) {
        _refreshJwtCompleter!.complete();
      }
      _refreshJwtCompleter = null;
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
        final response = await _http.post(url,
            headers: {
              // Provide the session cookie so the server knows what to destroy
              'Cookie': '__Secure-neon-auth.session_token=$sessionCookie',
              'Content-Type': 'application/json',
              'Origin': _neonAuthUrl
            },
            body: '{}');

        if (response.statusCode != 200) {
          // Log the error, but continue to clear local storage anyway
          logger.error(
              'Server sign-out warning: ${response.statusCode} - ${response.body}');
        } else {
          success = true;
        }
      } catch (e) {
        // Handle network errors gracefully
        logger.error('Failed to reach auth server during sign-out: $e');
      }
    }
    return success;
  }
}
