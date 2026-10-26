import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Controls native framework callbacks as well as test-zone requests. Only
/// fixture hosts are accepted; no socket or external account is accessed.
class NativeFixtureHttpOverrides extends HttpOverrides {
  NativeFixtureHttpOverrides(this.respond);
  final Future<http.Response> Function(http.Request) respond;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(respond);
}

class _Client implements HttpClient {
  _Client(this.respond);
  final Future<http.Response> Function(http.Request) respond;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    if (!{'auth.example.test', 'backend.example.test'}.contains(url.host)) {
      throw StateError('Native fixture refuses an unexpected HTTP host');
    }
    return _Request(method, url, respond);
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Headers implements HttpHeaders {
  final values = <String, List<String>>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value is Iterable
        ? value.map((v) => v.toString()).toList()
        : [value.toString()];
  }

  @override
  void forEach(void Function(String, List<String>) action) =>
      values.forEach(action);
  @override
  List<String>? operator [](String name) => values[name.toLowerCase()];
  @override
  String? value(String name) => values[name.toLowerCase()]?.join(',');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.respond);
  @override
  final String method;
  @override
  final Uri uri;
  final Future<http.Response> Function(http.Request) respond;
  final bytes = BytesBuilder();
  final completed = Completer<HttpClientResponse>();
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;
  @override
  Encoding encoding = utf8;
  @override
  void add(List<int> data) => bytes.add(data);
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.add(chunk);
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    if (!completed.isCompleted) {
      try {
        final request = http.Request(method, uri)
          ..headers.addAll(headers.values
              .map((key, value) => MapEntry(key, value.join(','))))
          ..bodyBytes = bytes.takeBytes();
        completed.complete(_Response(await respond(request)));
      } catch (error, stack) {
        completed.completeError(error, stack);
      }
    }
    return completed.future;
  }

  @override
  Future<HttpClientResponse> get done => completed.future;
  @override
  Future<void> flush() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this.response) {
    response.headers.forEach((key, value) => headers.set(key, value));
  }
  final http.Response response;
  @override
  final _Headers headers = _Headers();
  @override
  int get statusCode => response.statusCode;
  @override
  String get reasonPhrase => response.reasonPhrase ?? 'Fixture response';
  @override
  int get contentLength => response.bodyBytes.length;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(response.bodyBytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
