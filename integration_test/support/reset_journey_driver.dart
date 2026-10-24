import 'package:integration_test/integration_test_driver.dart';

/// Use `flutter drive --keep-app-running` for each staged native reset run.
/// `flutter test` uninstalls the app and therefore cannot verify saved sessions
/// across these stages. Runtime credentials/results stay inside fixture apps.
Future<void> main() => integrationDriver(
      timeout: const Duration(minutes: 15),
      responseDataCallback: null,
    );
