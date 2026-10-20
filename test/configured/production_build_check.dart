import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_test/flutter_test.dart';

// Run explicitly with the same defines as the production-configured APK.
// This guards against .env retaining LOCAL_TESTING=true during device tests.
void main() {
  test('production build overrides local mode and uses HTTPS API and Neon auth', () {
    expect(AppEnv.localTestingBuild, isFalse);
    expect(Uri.parse(AppEnv.effectiveApiBaseUrl).scheme, 'https');
    expect(AppEnv.effectiveApiBaseUrl, AppEnv.apiBaseUrl);
    expect(Uri.parse(AppEnv.neonAuthUrl).scheme, 'https');
    expect(Uri.parse(AppEnv.neonAuthUrl).path.endsWith('/auth'), isTrue);
  });
}
