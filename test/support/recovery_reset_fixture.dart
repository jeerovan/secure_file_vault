import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_recovery_reset.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An isolated protocol peer: real HTTP decoding/key generation remains in the
/// client. Actual server transaction/authorization behavior has PostgreSQL tests.
class RecoveryResetPeer {
  static const generation = '11111111-1111-4111-8111-111111111111';
  Map<String, dynamic>? draft;
  Map<String, dynamic>? envelope;
  String phase = 'prepared';
  String currentGeneration = 'legacy';
  bool expired = false;
  bool offline = false;
  bool loseConfirmResponse = false;
  bool corruptEnvelopeHash = false;
  String? confirmError;
  String? prepareError;
  bool available = true;
  String? statusError;
  String? operationError;
  bool requiresFreshSignin = false;
  int? expiresAtOverride;
  int prepareCalls = 0;
  int confirmCalls = 0;
  int statusCalls = 0;
  Future<void> Function()? beforePrepare;
  Future<void> Function()? beforeStatus;
  final requests = <String>[];
  final notBefore =
      DateTime.now().add(const Duration(hours: 24)).millisecondsSinceEpoch;

  RecoveryResetService service() => RecoveryResetService.test(
      apiFactory: () => BackendApi(
          baseUrlOverride: 'https://api.example.test/api',
          httpClient: MockClient(handle),
          refreshAuth: () async {}));

  Map<String, dynamic> get operation => {
        'operationId': draft!['operationId'],
        'phase': phase,
        'generation': generation,
        'expiresAt': expiresAtOverride ??
            DateTime.now()
                .add(const Duration(minutes: 5))
                .millisecondsSinceEpoch,
        'expired': expired,
        'requiresFreshSignin': requiresFreshSignin,
        'notBefore': notBefore,
        'envelopeHash': envelope == null
            ? null
            : corruptEnvelopeHash
                ? 'wrong'
                : sha256
                    .convert(utf8
                        .encode('${envelope!['cipher']}.${envelope!['nonce']}'))
                    .toString(),
        'error': operationError,
      };

  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    if (offline) return http.Response('', 503);
    Map<String, dynamic> reply;
    if (request.method == 'GET') {
      statusCalls++;
      await beforeStatus?.call();
      if (statusError != null) {
        return http.Response(
            jsonEncode({'success': 0, 'message': statusError}), 200);
      }
      final id = request.url.queryParameters['operation_id'];
      if (id != null && (draft == null || draft!['operationId'] != id)) {
        reply = {'success': 0, 'message': 'reset_not_found'};
      } else {
        reply = {
          'success': 1,
          'data': {
            'available': available,
            'generation': envelope == null ? currentGeneration : generation,
            'pendingConfirmation':
                draft != null && envelope == null && !expired,
            'operation':
                id != null || phase == 'cleanup_pending' ? operation : null
          }
        };
      }
    } else if (request.url.path.endsWith('/prepare')) {
      prepareCalls++;
      await beforePrepare?.call();
      if (prepareError != null) {
        return http.Response(
            jsonEncode({'success': 0, 'message': prepareError}), 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['expectedGeneration'] != currentGeneration) {
        return http.Response(
            jsonEncode({'success': 0, 'message': 'vault_changed'}), 200);
      }
      if (draft != null &&
          draft!['operationId'] != body['operationId'] &&
          !expired) {
        throw StateError('A second unexpired operation was attempted');
      }
      draft = body;
      expired = false;
      reply = {'success': 1, 'data': operation};
    } else {
      confirmCalls++;
      if (confirmError != null) {
        operationError =
            confirmError!.startsWith('storage_') ? confirmError : null;
        return http.Response(
            jsonEncode({'success': 0, 'message': confirmError}), 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body.keys.any((key) => [
            'private_keys',
            'master_key',
            'access_key',
            'file_hash_key'
          ].contains(key))) {
        throw StateError('Private reset keys reached the protocol peer');
      }
      if (body['operationId'] != draft?['operationId'] ||
          sha256.convert(utf8.encode(body['challenge'])).toString() !=
              draft?['challengeHash']) {
        throw StateError(
            'Confirmation was not bound to the prepared challenge');
      }
      envelope = body;
      phase = 'cleanup_pending';
      if (loseConfirmResponse) {
        offline = true;
        return http.Response('', 503);
      }
      reply = {'success': 1, 'data': operation};
    }
    return http.Response(jsonEncode(reply), 200);
  }
}
