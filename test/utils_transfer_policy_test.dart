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

  test('only confirmed no-storage response is classified as storage full', () {
    expect(
      UploadStorageSelectionPolicy.classify({'success': 0, 'message': '4'}),
      UploadStorageSelectionStatus.storageFull,
    );
    expect(
      UploadStorageSelectionPolicy.classify(
          {'success': -1, 'message': 'Network Error'}),
      UploadStorageSelectionStatus.retryableFailure,
    );
    expect(
      UploadStorageSelectionPolicy.classify({'success': 0, 'message': '14'}),
      UploadStorageSelectionStatus.retryableFailure,
    );
    expect(
      UploadStorageSelectionPolicy.classify({'success': 1}),
      UploadStorageSelectionStatus.selected,
    );
  });

  test('B2 recovery marker and response parsing are durable and strict', () {
    final original = <String, dynamic>{'sha1': 'hash'};
    final attempted = B2UploadRecoveryPolicy.markAttempted(original);

    expect(B2UploadRecoveryPolicy.wasAttempted(original), isFalse);
    expect(B2UploadRecoveryPolicy.wasAttempted(attempted), isTrue);
    expect(
      B2UploadRecoveryPolicy.recoveredFileId({
        'success': 1,
        'data': {'fileId': 'b2-id'},
      }),
      'b2-id',
    );
    expect(
      B2UploadRecoveryPolicy.recoveredFileId({
        'success': -1,
        'data': {'fileId': 'ambiguous'},
      }),
      isNull,
    );
    expect(
      B2UploadRecoveryPolicy.recoveredFileId({'success': 1, 'data': null}),
      isNull,
    );
  });
}
