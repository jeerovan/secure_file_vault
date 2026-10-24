import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// iOS can reject the first connection while its Local Network prompt is open.
/// Keep the fixture alive for the permission decision; this proves TCP access,
/// while the subsequent API assertions still verify authentication and setup.
Future<void> waitForIphoneProviderNetworkAccess(Uri endpoint,
    {Duration timeout = const Duration(minutes: 3)}) async {
  if (!Platform.isIOS) return;
  debugPrint('Native provider fixture waiting for Local Network access.');
  final deadline = DateTime.now().add(timeout);
  while (true) {
    try {
      final socket = await Socket.connect(endpoint.host, endpoint.port,
          timeout: const Duration(seconds: 3));
      socket.destroy();
      return;
    } on SocketException {
      // A denied or still-pending permission must not become a vault failure.
    } on TimeoutException {
      // Wait within the same bounded permission window for a usable LAN route.
    }
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Native fixture Local Network access is unavailable');
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
}

/// The caller verifies its disposable app identity before reading credentials.
/// Runtime input avoids embedding provider secrets in a test application.
Future<List<dynamic>> readNativeProviderInputs() async {
  const embedded = String.fromEnvironment('FIFE_NATIVE_PROVIDER_INPUTS');
  if (embedded.isNotEmpty) return jsonDecode(embedded) as List;
  const endpoint = String.fromEnvironment('FIFE_NATIVE_PROVIDER_INPUT_URL');
  if (endpoint.isNotEmpty) {
    final uri = Uri.parse(endpoint);
    const token = String.fromEnvironment('FIFE_NATIVE_PROVIDER_INPUT_TOKEN');
    if (!Platform.isMacOS ||
        uri.scheme != 'https' ||
        uri.host != '127.0.0.1' ||
        uri.userInfo.isNotEmpty ||
        token.isEmpty) {
      throw StateError(
          'Private provider input requires authenticated loopback HTTPS');
    }
    debugPrint('Native provider fixture requesting private loopback input.');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw StateError('Private provider input was not available');
      }
      return jsonDecode(await utf8.decoder.bind(response).join()) as List;
    } finally {
      client.close(force: true);
    }
  }
  final directory = await getApplicationDocumentsDirectory();
  final file = File('${directory.path}/fife-provider-inputs.json');
  debugPrint('Native provider fixture waiting for private runtime input.');
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (!await file.exists()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
          'Private native provider fixture input was not supplied');
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  final encoded = await file.readAsString();
  await file.delete();
  return jsonDecode(encoded) as List;
}
