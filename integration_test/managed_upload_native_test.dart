import 'package:integration_test/integration_test.dart';

import 's3_providers_native_test.dart' as providers;
import 'recovery_native_test.dart' as recovery;
import 'support/iphone_results.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // These are integrity/recovery checks over real WAN transfers. Keep a
  // bounded allowance for slow but progressing 25 MiB encrypted parts.
  providers.registerProviderNativeTests(
    reportResults: false,
    transferTimeout: const Duration(minutes: 5),
    suiteTimeout: const Duration(minutes: 45),
  );
  recovery.registerRecoveryNativeTests(reportResults: false);
  recordIphoneResults(binding, 'managed-uploads');
}
