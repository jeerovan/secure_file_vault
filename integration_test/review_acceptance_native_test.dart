import 'package:integration_test/integration_test.dart';

import 'device_revocation_native_test.dart' as revocation;
import 'recovery_native_test.dart' as recovery;
import 's3_providers_native_test.dart' as providers;
import 'support/iphone_results.dart';

/// Focused post-review acceptance. The existing provider filter scopes the
/// transfer checks alongside session cleanup, onboarding and native scheduling.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  revocation.registerRevocationNativeTests(reportResults: false);
  recovery.registerRecoveryNativeTests(reportResults: false);
  providers.registerProviderNativeTests(
    reportResults: false,
    transferTimeout: const Duration(minutes: 5),
    suiteTimeout: const Duration(minutes: 20),
  );
  recordIphoneResults(binding, 'review-acceptance');
}
