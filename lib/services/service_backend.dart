import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class AppEnv {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  ); // set via --dart-define=API_BASE_URL=... [web:44]
}

class BackendApi {
  final SupabaseClient _supabase;
  final http.Client _http;
  final Uri _base;
  final Duration timeout;
  final logger = AppLogger(prefixes: ["BackendAPI"]);

  BackendApi({
    SupabaseClient? supabase,
    http.Client? httpClient,
    String? baseUrlOverride,
    this.timeout = const Duration(seconds: 30),
  })  : _supabase = supabase ?? Supabase.instance.client,
        _http = httpClient ?? http.Client(),
        _base =
            Uri.parse(_normalizeBaseUrl(baseUrlOverride ?? AppEnv.apiBaseUrl)) {
    final raw = (baseUrlOverride ?? AppEnv.apiBaseUrl).trim();
    if (raw.isEmpty) {
      throw StateError(
        'API_BASE_URL is empty. Set --dart-define=API_BASE_URL=https://your.domain',
      );
    }
  }

  static String _normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  String _accessTokenOrThrow() {
    final session = _supabase.auth.currentSession;
    if (session == null) throw StateError('No active Supabase session.');
    return session.accessToken; // Session exposes accessToken [web:57]
  }

  Uri _buildUri(String endpoint, {Map<String, dynamic>? queryParameters}) {
    final ep = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    final uri = _base.resolve(ep);

    if (queryParameters == null || queryParameters.isEmpty) return uri;

    final qp = <String, String>{
      for (final e in queryParameters.entries)
        if (e.value != null) e.key: e.value.toString(),
    };
    return uri.replace(queryParameters: qp);
  }

  Future<Map<String, String>> _headers({
    required bool withAuth,
    Map<String, String>? extra,
  }) async {
    final h = <String, String>{
      'Content-Type': 'application/json',
      if (withAuth) 'Authorization': 'Bearer ${_accessTokenOrThrow()}',
      if (!withAuth) 'Authorization': 'Bearer ${getSignedInEmailId()}',
    };
    if (extra != null) h.addAll(extra);
    final deviceId = await getDeviceId();
    if (deviceId.isNotEmpty) {
      h.addAll({'device_id': deviceId});
    }
    return h;
  }

  dynamic _tryDecodeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return trimmed; // keep raw string; don't treat as exception
    }
  }

  Map<String, dynamic> _formatResponse(http.Response res) {
    final code = res.statusCode;
    Map<String, dynamic> response;
    if (code >= 500) {
      response = {'status': 0, 'error': 'Server Error'};
    } else {
      final decoded = _tryDecodeJson(res.body);

      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        response = map;
      } else {
        response = {
          'status': 0,
          if (decoded != null) 'error': decoded,
        };
      }
    }
    logger.info(response.toString());
    return response;
  }

  bool _isNetworkException(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is HttpException ||
      e is http.ClientException;

  Future<Map<String, dynamic>> get({
    required String endpoint,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      logger.info('GET $endpoint ${queryParameters.toString()}');
      final res = await _http
          .get(
            _buildUri(endpoint, queryParameters: queryParameters),
            headers: await _headers(
                withAuth: getSignedInEmailId() != testEmailId, extra: headers),
          )
          .timeout(timeout);
      return _formatResponse(res);
    } catch (e) {
      logger.debug(e.toString());
      if (_isNetworkException(e)) rethrow;
      return {'status': -1, 'error': 'Unexpected Error'};
    }
  }

  Future<Map<String, dynamic>> post({
    required String endpoint,
    required Map<String, dynamic> jsonBody,
    Map<String, String>? headers,
  }) async {
    try {
      logger.info('POST $endpoint ${jsonEncode(jsonBody)}');
      final res = await _http
          .post(
            _buildUri(endpoint),
            headers: await _headers(
                withAuth: getSignedInEmailId() != testEmailId, extra: headers),
            body: jsonEncode(jsonBody),
          )
          .timeout(timeout);
      return _formatResponse(res);
    } catch (e) {
      logger.debug(e.toString());
      if (_isNetworkException(e)) rethrow;
      return {'status': -1, 'error': 'Unexpected Error'};
    }
  }

  void close() => _http.close();
}
