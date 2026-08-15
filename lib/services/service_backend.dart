import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_logger.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:http/http.dart' as http;

class BackendApi {
  final SecureStorage _storage;
  final http.Client _http;
  final bool _ownsHttpClient;
  final Uri _base;
  final Duration timeout;
  final Future<String?> Function()? _accessTokenProvider;
  final Future<String?> Function()? _signedEmailIdProvider;
  final Future<String> Function()? _deviceUuidProvider;
  final Future<void> Function() _refreshAuth;
  final logger = AppLogger(prefixes: ["BackendAPI"]);

  BackendApi({
    SecureStorage? storage,
    http.Client? httpClient,
    String? baseUrlOverride,
    Future<String?> Function()? accessTokenProvider,
    Future<String?> Function()? signedEmailIdProvider,
    Future<String> Function()? deviceUuidProvider,
    Future<void> Function()? refreshAuth,
    this.timeout = const Duration(seconds: 30),
  })  : _storage = storage ?? SecureStorage(),
        _http = httpClient ?? AppHttpClients.backend,
        _ownsHttpClient = httpClient != null,
        _accessTokenProvider = accessTokenProvider,
        _signedEmailIdProvider = signedEmailIdProvider,
        _deviceUuidProvider = deviceUuidProvider,
        _refreshAuth = refreshAuth ?? refreshNeonAuth,
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
    if (_accessTokenProvider != null) return _accessTokenProvider();
    String? jwtToken = await _storage.read(key: AppString.jwtToken.string);
    /* if (jwtToken != null) {
      logger.info(jwtToken);
    } */
    return jwtToken;
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
    final deviceUuid = await (_deviceUuidProvider?.call() ?? getDeviceUuid());
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
          String mappedMessage = "Unknown Error";
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
              break;
            case "15":
              mappedMessage = "Invalid Data";
              break;
            case "16":
              mappedMessage = "Requires FiFe Pro";
              break;
            default:
              mappedMessage = message;
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
    logger.info('HTTP response status=$code');
    return response;
  }

  bool _isNetworkException(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e is HandshakeException ||
      e is HttpException ||
      e is http.ClientException;

  bool _isUnauthorized(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) return true;
    final decoded = _tryDecodeJson(response.body);
    return decoded is Map &&
        decoded['success'] == 0 &&
        decoded['message'].toString() == '14';
  }

  Future<bool> _shouldAuthenticate() async {
    final signedEmailId =
        await (_signedEmailIdProvider?.call() ?? getSignedInEmailId());
    return signedEmailId != null && signedEmailId != testEmailId;
  }

  Future<http.Response> _sendWithAuthRetry({
    required bool withAuth,
    required bool retryUnauthorized,
    required Map<String, String>? extraHeaders,
    required Future<http.Response> Function(Map<String, String>) send,
  }) async {
    final initialHeaders =
        await _headers(withAuth: withAuth, extra: extraHeaders);
    var response = await send(initialHeaders).timeout(timeout);
    if (withAuth && retryUnauthorized && _isUnauthorized(response)) {
      final previousAuthorization = initialHeaders['Authorization'];
      await _refreshAuth();
      final refreshedHeaders =
          await _headers(withAuth: true, extra: extraHeaders);
      if (refreshedHeaders['Authorization'] != previousAuthorization) {
        response = await send(refreshedHeaders).timeout(timeout);
      }
    }
    return response;
  }

  Future<Map<String, dynamic>> get({
    required String endpoint,
    Map<String, dynamic>? queryParameters,
    Map<String, String>? headers,
  }) async {
    try {
      final withAuth = await _shouldAuthenticate();
      logger.info('GET $endpoint');
      final res = await _sendWithAuthRetry(
        withAuth: withAuth,
        retryUnauthorized: true,
        extraHeaders: headers,
        send: (requestHeaders) => _http.get(
          _buildUri(endpoint, queryParameters: queryParameters),
          headers: requestHeaders,
        ),
      );
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
    bool retryUnauthorized = false,
  }) async {
    try {
      final withAuth = await _shouldAuthenticate();
      logger.info('POST $endpoint');
      final encodedBody = jsonEncode(jsonBody);
      final res = await _sendWithAuthRetry(
        withAuth: withAuth,
        retryUnauthorized: retryUnauthorized,
        extraHeaders: headers,
        send: (requestHeaders) => _http.post(
          _buildUri(endpoint),
          headers: requestHeaders,
          body: encodedBody,
        ),
      );
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
      final withAuth = await _shouldAuthenticate();
      logger.info('DELETE $endpoint');
      final res = await _sendWithAuthRetry(
        withAuth: withAuth,
        retryUnauthorized: true,
        extraHeaders: headers,
        send: (requestHeaders) => _http.delete(
          _buildUri(endpoint, queryParameters: queryParameters),
          headers: requestHeaders,
        ),
      );
      return _formatResponse(res);
    } catch (e) {
      logger.error(e.toString());
      if (_isNetworkException(e)) {
        return {'success': -1, 'message': 'Network Error'};
      }
      return {'success': -1, 'message': 'Unexpected Error'};
    }
  }

  /// Shared default clients are closed by [AppHttpClients.closeAll].
  void close() {
    if (_ownsHttpClient) _http.close();
  }
}
