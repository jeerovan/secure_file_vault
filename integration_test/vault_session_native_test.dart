import 'package:integration_test/integration_test.dart';

import 'device_revocation_native_test.dart' as revocation;
import 'recovery_native_test.dart' as recovery;
import 'support/iphone_results.dart';

/// Repeat session and recovery acceptance independently of live transfers.
/// Use the same guarded disposable native installation as the full review suite.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  revocation.registerRevocationNativeTests(reportResults: false);
  recovery.registerRecoveryNativeTests(reportResults: false);
  recordIphoneResults(binding, 'vault-session');
}
