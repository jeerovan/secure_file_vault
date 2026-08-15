import 'package:file_vault_bb/services/service_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLogger.sanitize', () {
    test('preserves ordinary diagnostics', () {
      expect(
        AppLogger.sanitize('Upload failed with status 503'),
        'Upload failed with status 503',
      );
    });

    test('redacts credentials and personal data', () {
      const message = 'authorization=Bearer abc.def token: "secret" otp=123456 '
          'email=user@example.com __Secure-session=cookie-value';

      final sanitized = AppLogger.sanitize(message);

      expect(sanitized, isNot(contains('abc.def')));
      expect(sanitized, isNot(contains('secret')));
      expect(sanitized, isNot(contains('123456')));
      expect(sanitized, isNot(contains('user@example.com')));
      expect(sanitized, isNot(contains('cookie-value')));
    });

    test('redacts signed URLs', () {
      const signedUrl =
          'https://storage.example.com/file?X-Amz-Signature=sensitive';

      expect(AppLogger.sanitize('download $signedUrl'),
          isNot(contains(signedUrl)));
      expect(AppLogger.sanitize('download $signedUrl'),
          contains('[REDACTED_URL]'));
    });

    test('redacts filesystem paths and hashes', () {
      const hash =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      const unixPath = '/home/user/private/report.txt';
      const windowsPath = r'C:\Users\user\private\report.txt';

      final sanitized = AppLogger.sanitize(
        'read $unixPath or $windowsPath with hash $hash',
      );

      expect(sanitized, isNot(contains(unixPath)));
      expect(sanitized, isNot(contains(windowsPath)));
      expect(sanitized, isNot(contains(hash)));
    });
  });
}
