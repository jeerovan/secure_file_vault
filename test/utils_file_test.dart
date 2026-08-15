import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadStreamResult', () {
    test('classifies transient failures as retryable', () {
      for (final status in [401, 403, 429, 500, 503]) {
        final result = DownloadStreamResult.httpFailure(status);

        expect(result.succeeded, isFalse);
        expect(result.isRetryable, isTrue, reason: 'status $status');
      }

      expect(
        const DownloadStreamResult.transportFailure().isRetryable,
        isTrue,
      );
    });

    test('does not classify confirmed absence as retryable', () {
      final result = DownloadStreamResult.httpFailure(404);

      expect(result.succeeded, isFalse);
      expect(result.failureKind, DownloadFailureKind.notFound);
      expect(result.isRetryable, isFalse);
    });
  });
}
