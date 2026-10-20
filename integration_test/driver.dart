import 'package:integration_test/integration_test_driver.dart';

// Keep test results in the caller's private log, without writing response data.
Future<void> main() => integrationDriver(responseDataCallback: (_) async {});
