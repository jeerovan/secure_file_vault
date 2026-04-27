import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:http/http.dart' as http;

import '../models/model_item.dart';
import '../models/model_profile.dart';
import '../models/model_setting.dart';

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

  Future<void> refreshSessionAndGetJWT() async {
    final sessionCookie =
        await _storage.read(key: AppString.sessionCookie.string);
    if (sessionCookie == null) return;

    final response = await _http.get(
      Uri.parse('$_neonAuthUrl/get-session'),
      headers: {
        'Cookie': '__Secure-neon-auth.session_token=$sessionCookie',
        'Content-Type': 'application/json'
      },
    );

    if (response.statusCode == 200) {
      // Extract the JWT from the headers
      final jwt = response.headers['set-auth-jwt'];
      if (jwt != null) {
        await _storage.write(key: AppString.jwtToken.string, value: jwt);
        logger.info("Refreshed jwtToken");
      }
    } else {
      // If it fails, the session is dead. Clear storage and force re-login.
      await SyncUtils.signout();
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
