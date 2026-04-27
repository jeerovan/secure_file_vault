import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:http/http.dart' as http;

class BackendApi {
  final SecureStorage _storage;
  final http.Client _http;
  final Uri _base;
  final Duration timeout;
  final logger = AppLogger(prefixes: ["BackendAPI"]);

  BackendApi({
    SecureStorage? storage,
    http.Client? httpClient,
    String? baseUrlOverride,
    this.timeout = const Duration(seconds: 20),
  })  : _storage = storage ?? SecureStorage(),
        _http = httpClient ?? http.Client(),
        _base = Uri.parse(
            _normalizeBaseUrl(baseUrlOverride ?? '${AppEnv.apiBaseUrl}/api')) {
    final raw = (baseUrlOverride ?? '${AppEnv.apiBaseUrl}/api').trim();
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

  Future<String?> _getAccessToken() async {
    return await _storage.read(key: AppString.jwtToken.string);
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
    String? accessToken = await _getAccessToken();
    final h = <String, String>{
      'Content-Type': 'application/json',
      if (withAuth && accessToken != null)
        'Authorization': 'Bearer $accessToken',
      'Service': 'neon'
    };
    if (extra != null) h.addAll(extra);
    final deviceUuid = await getDeviceUuid();
    if (deviceUuid.isNotEmpty) {
      h.addAll({'device_uuid': deviceUuid});
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
      response = {'success': 0, 'message': 'Server Error'};
    } else {
      final decoded = _tryDecodeJson(res.body);

      if (decoded is Map) {
        final map = Map<String, dynamic>.from(decoded);
        response = map;
        if (response["success"] == 0) {
          String message = response["message"].toString();
          String mappedMessage = "Unknown";
          switch (message) {
            case "1":
              mappedMessage = "No User";
              break;
            case "2":
              mappedMessage = "Invalid JSON";
              break;
            case "3":
              mappedMessage = "Missing Fields";
              break;
            case "4":
              mappedMessage = "No Storage";
              break;
            case "5":
              mappedMessage = "Invalid Credentials";
              break;
            case "6":
              mappedMessage = "Credentials Incapable";
              break;
            case "7":
              mappedMessage = "Device Limit Reached";
              break;
            case "8":
              mappedMessage = "No Device";
              break;
            case "9":
              mappedMessage = "No Buckets";
              break;
            case "10":
              mappedMessage = "Multiple Buckets";
              break;
            case "11":
              mappedMessage = "Nameprefix Exist";
              break;
            case "12":
              mappedMessage = "Bucket Info";
              break;
            case "13":
              mappedMessage = "No Data";
              break;
            case "14":
              mappedMessage = "Unauthorized";
              // refresh jwt
              unawaited(NeonAuth().refreshSessionAndGetJWT());
              break;
            default:
              mappedMessage = "Unknown Error";
              break;
          }
          logger.error(mappedMessage);
        }
      } else {
        response = {
          'success': 0,
          if (decoded != null) 'message': decoded,
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
      String? signedEmailId = await getSignedInEmailId();
      bool withAuth = signedEmailId != null && signedEmailId != testEmailId;
      logger.info('GET $endpoint ${queryParameters.toString()}');
      final res = await _http
          .get(
            _buildUri(endpoint, queryParameters: queryParameters),
            headers: await _headers(withAuth: withAuth, extra: headers),
          )
          .timeout(timeout);
      return _formatResponse(res);
    } catch (e) {
      logger.error(e.toString());
      if (_isNetworkException(e)) {
        return {'success': -1, 'message': 'Network Error'};
      }
      return {'success': -1, 'message': 'Unexpected Error'};
    }
  }

  Future<Map<String, dynamic>> post({
    required String endpoint,
    required Map<String, dynamic> jsonBody,
    Map<String, String>? headers,
  }) async {
    try {
      String? signedEmailId = await getSignedInEmailId();
      bool withAuth = signedEmailId != null && signedEmailId != testEmailId;
      logger.info('POST $endpoint ${jsonEncode(jsonBody)}');
      final res = await _http
          .post(
            _buildUri(endpoint),
            headers: await _headers(withAuth: withAuth, extra: headers),
            body: jsonEncode(jsonBody),
          )
          .timeout(timeout);
      return _formatResponse(res);
    } catch (e) {
      logger.error(endpoint, error: e.toString());
      if (_isNetworkException(e)) {
        return {'success': -1, 'message': 'Network Error'};
      }
      return {'success': -1, 'message': 'Unexpected Error'};
    }
  }

  Future<Map<String, dynamic>> delete({
    required String endpoint,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      String? signedEmailId = await getSignedInEmailId();
      bool withAuth = signedEmailId != null && signedEmailId != testEmailId;
      logger.info('DELETE $endpoint ${queryParameters.toString()}');
      final res = await _http
          .delete(
            _buildUri(endpoint, queryParameters: queryParameters),
            headers: await _headers(withAuth: withAuth, extra: headers),
          )
          .timeout(timeout);
      return _formatResponse(res);
    } catch (e) {
      logger.error(e.toString());
      if (_isNetworkException(e)) {
        return {'success': -1, 'message': 'Network Error'};
      }
      return {'success': -1, 'message': 'Unexpected Error'};
    }
  }

  void close() => _http.close();
}
