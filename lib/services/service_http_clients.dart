import 'package:http/http.dart' as http;

class AppHttpClients {
  AppHttpClients._();

  static http.Client? _backend;
  static http.Client? _auth;
  static http.Client? _transfer;

  static http.Client get backend => _backend ??= http.Client();
  static http.Client get auth => _auth ??= http.Client();
  static http.Client get transfer => _transfer ??= http.Client();

  static void closeAll() {
    _backend?.close();
    _auth?.close();
    _transfer?.close();
    _backend = null;
    _auth = null;
    _transfer = null;
  }
}
