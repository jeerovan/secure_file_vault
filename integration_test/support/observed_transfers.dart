import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/utils/common.dart';
import 'package:http/http.dart' as http;

/// An idempotent verification probe must survive a pooled connection reset.
/// Retry transport failures with a fresh connection; never hide a wrong status.
Future<int> probeCloudStatus(Uri url,
    {http.Client Function()? clientFactory,
    Duration timeout = const Duration(seconds: 30)}) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    final http.Client client = clientFactory != null
        ? clientFactory()
        : Zone.root.run<http.Client>(http.Client.new);
    try {
      final response = await client
          .send(http.Request('GET', url)..headers['Range'] = 'bytes=0-0')
          .timeout(timeout);
      await response.stream.drain<void>().timeout(timeout);
      return response.statusCode;
    } catch (error) {
      if (attempt == 2 ||
          error is! http.ClientException &&
              error is! SocketException &&
              error is! TimeoutException) {
        rethrow;
      }
    } finally {
      client.close();
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Cloud probe did not complete');
}

/// Real ciphertext and network, with controlled rejection or lost-response faults.
class ObservedTransfers extends http.BaseClient {
  final http.Client delegate;
  final String? endpointHost;
  int uploads = 0;
  bool loseNextSuccess = false;
  bool rejectNextUpload = false;
  bool closed = false;
  String? lostVersion;
  String? rejectedInvariant;
  String? providerFailureType;

  ObservedTransfers(this.delegate, {this.endpointHost});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final upload = request.method == 'PUT' &&
        (endpointHost == null
            ? request.url.host.endsWith('.backblazeb2.com')
            : request.url.host == endpointHost ||
                request.url.host.endsWith('.$endpointHost'));
    if (upload) {
      final checks = {
        'fixture_scope': request.url.scheme == 'https' &&
            (endpointHost == null
                ? request.url.pathSegments.length >= 3 &&
                    request.url.pathSegments[1] == AppEnv.localTestUserId
                : request.url.pathSegments.contains(AppEnv.localTestUserId)),
        'no_native_token': !request.headers.containsKey('authorization'),
        if (endpointHost == null)
          'md5_header': request.headers['content-md5']?.isNotEmpty == true,
        if (endpointHost == null)
          'sha1_metadata':
              request.headers['x-amz-meta-sha1']?.isNotEmpty == true,
        'expiry': request.url.queryParameters['X-Amz-Expires'] == '900',
      };
      for (final check in checks.entries) {
        if (!check.value) {
          rejectedInvariant = check.key;
          // Consume a rejected StreamedRequest so the uploader's sink can close.
          await request.finalize().drain<void>();
          throw StateError('Fixture upload rejected: ${check.key}');
        }
      }
      uploads++;
      providerFailureType = null;
      if (rejectNextUpload) {
        rejectNextUpload = false;
        await request.finalize().drain<void>();
        return http.StreamedResponse(const Stream.empty(), 403,
            request: request);
      }
    }
    final http.StreamedResponse response;
    try {
      response = await delegate.send(request);
    } catch (error) {
      if (upload) {
        final certificate = RegExp(r'CERTIFICATE_VERIFY_FAILED[^)]{0,120}')
            .firstMatch(error.toString())
            ?.group(0);
        providerFailureType =
            '${error.runtimeType}${certificate == null ? '' : ': $certificate'}';
      }
      rethrow;
    }
    if (upload && loseNextSuccess && response.statusCode == 200) {
      loseNextSuccess = false;
      lostVersion = response.headers['x-amz-version-id'];
      await response.stream.drain<void>();
      throw http.ClientException(
          'Injected loss after generated S3 fixture commit');
    }
    return response;
  }

  @override
  void close() {
    if (!closed) delegate.close();
    closed = true;
  }
}
