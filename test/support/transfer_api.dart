import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Deterministic API/bucket boundary with actual encrypted request bytes.
class TransferApi {
  final int providerId;
  final Map<String, List<int>> objects = {};
  final List<http.Request> requests = [];
  final List<int> uploadStatuses = [];
  final List<int> downloadStatuses = [];
  final List<List<int>> uploadBodies = [];
  final List<String> downloadedIds = [];
  Map<String, dynamic>? selectionFailure;
  List<int> Function(List<int>)? alterDownload;
  bool loseNextUploadResponse = false;
  HttpServer? _downloads;

  TransferApi({this.providerId = 6});

  Future<T> run<T>(Future<T> Function() action) async {
    AppHttpClients.closeAll();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _downloads = server;
    server.listen((request) async {
      downloadedIds.add(request.uri.pathSegments.last);
      final status =
          downloadStatuses.isEmpty ? 200 : downloadStatuses.removeAt(0);
      final bytes = objects[request.uri.pathSegments.last];
      request.response.statusCode = bytes == null ? 404 : status;
      if (bytes != null && status == 200) {
        request.response.add(alterDownload?.call(List.of(bytes)) ?? bytes);
      } else {
        request.response.write('bucket unavailable');
      }
      await request.response.close();
    });
    try {
      return await HttpOverrides.runWithHttpOverrides(
        () => http.runWithClient(action, () => MockClient(handle)),
        _LoopbackHttpOverrides(),
      );
    } finally {
      AppHttpClients.closeAll();
      await server.close(force: true);
      _downloads = null;
    }
  }

  http.Response json(Map<String, dynamic> body) =>
      http.Response(jsonEncode(body), 200,
          headers: {'content-type': 'application/json'});

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    if (request.url.host == 'bucket.example.test') {
      final id = request.headers['x-bz-file-name'] != null
          ? Uri.decodeComponent(request.headers['x-bz-file-name']!)
              .split('/')
              .last
          : request.url.pathSegments.last;
      if (request.method == 'GET') {
        final status =
            downloadStatuses.isEmpty ? 200 : downloadStatuses.removeAt(0);
        if (status != 200) return http.Response('bucket unavailable', status);
        final bytes = objects[id];
        if (bytes == null) return http.Response('missing object', 404);
        return http.Response.bytes(
            alterDownload?.call(List.of(bytes)) ?? bytes, 200);
      }
      uploadBodies.add(List.of(request.bodyBytes));
      final status = uploadStatuses.isEmpty ? 200 : uploadStatuses.removeAt(0);
      if (status != 200) return http.Response('upload unavailable', status);
      objects[id] = List.of(request.bodyBytes);
      if (loseNextUploadResponse) {
        loseNextUploadResponse = false;
        throw http.ClientException('response lost after bucket commit');
      }
      return json({'fileId': 'bucket-object-$id'});
    }
    if (path.endsWith('/get-file-parts')) {
      return json({'success': 0, 'message': '13'});
    }
    if (path.endsWith('/get-upload-storage-provider')) {
      return json(selectionFailure ??
          {
            'success': 1,
            'data': {'storage_id': 7, 'provider_id': providerId},
          });
    }
    if (path.endsWith('/get-upload-url')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (path.contains('/b2/')) {
        return json({
          'success': 1,
          'data': {
            'uploadUrl': 'https://bucket.example.test/b2',
            'authorizationToken': 'unit-bucket-token',
          },
        });
      }
      return json({
        'success': 1,
        'data': 'https://bucket.example.test/${body['file_id']}',
      });
    }
    if (path.endsWith('/find-uploaded-file')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final bytes = objects[body['file_id']];
      final matches = bytes != null &&
          bytes.length == body['content_length'] &&
          sha1.convert(bytes).toString() == body['content_sha1'];
      return json({
        'success': 1,
        'data': matches ? {'fileId': 'bucket-object-${body['file_id']}'} : null,
      });
    }
    if (path.endsWith('/get-download-url')) {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return json({
        'success': 1,
        'data': 'http://127.0.0.1:${_downloads!.port}/${body['file_id']}',
      });
    }
    throw StateError('Unexpected test request ${request.method} $path');
  }
}

class _LoopbackHttpOverrides extends HttpOverrides {}
