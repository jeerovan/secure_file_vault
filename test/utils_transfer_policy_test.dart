import 'package:file_vault_bb/utils/utils_transfer_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile concurrency is lower than desktop concurrency', () {
    expect(
      TransferConcurrencyPolicy.maxConcurrent(isMobile: true),
      TransferConcurrencyPolicy.mobileLimit,
    );
    expect(
      TransferConcurrencyPolicy.maxConcurrent(isMobile: false),
      TransferConcurrencyPolicy.desktopLimit,
    );
    expect(
      TransferConcurrencyPolicy.mobileLimit,
      lessThan(TransferConcurrencyPolicy.desktopLimit),
    );
  });
}
