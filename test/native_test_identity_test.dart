import 'package:flutter_test/flutter_test.dart';

import '../integration_test/support/native_test_identity.dart';

void main() {
  test(
      'destructive native fixtures reject manual and historical app identities',
      () {
    for (final bundle in [
      'com.jeerovan.fife',
      'com.jeerovan.fife.localtest',
      'com.jeerovan.fife.localtest.recovery',
      'com.jeerovan.fife.localtest.review',
      'com.jeerovan.fife.localtest.fixture',
      'com.jeerovan.fife.localtest.fixture.runinvalid',
      'com.jeerovan.fife.localtest.fixture.run${'a' * 32}.other',
    ]) {
      expect(isIsolatedNativeTestBundle(bundle), isFalse, reason: bundle);
    }
  });

  test('fresh per-run fixture identities are recognized', () {
    expect(
        isIsolatedNativeTestBundle(
            'com.jeerovan.fife.localtest.fixture.run${'a' * 32}'),
        isTrue);
  });
}
