import 'dart:convert';
import 'package:http/http.dart' as http_lib;
import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

class StorageValidationService {
  /// Validates Backblaze credentials replicating your backend logic
  static Future<bool> validateBackblaze(String appId, String appKey) async {
    final String basicAuth =
        'Basic ${base64Encode(utf8.encode('$appId:$appKey'))}';

    try {
      final response = await http_lib.get(
        Uri.parse('https://api.backblazeb2.com/b2api/v4/b2_authorize_account'),
        headers: {'Authorization': basicAuth},
      );

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final allowed = data['apiInfo']['storageApi']['allowed'];

      final List buckets =
          allowed['bucketId'] != null ? [allowed['bucketId']] : [];
      final List capabilities = allowed['capabilities'] ?? [];
      final String? namePrefix = allowed['namePrefix'];

      // Replication of Svelte backend logic
      if (buckets.length != 1 && allowed['bucketId'] != null) return false;
      if (namePrefix != null) return false; // Name prefix exist check

      final requiredCaps = [
        'deleteFiles',
        'writeBuckets',
        'readBuckets',
        'readFiles',
        'shareFiles',
        'writeFiles',
        'listFiles'
      ];

      final hasAllCapabilities =
          requiredCaps.every((c) => capabilities.contains(c));
      return hasAllCapabilities;
    } catch (e) {
      return false;
    }
  }

  /// Validates S3-compatible providers (Oracle, Cloudflare, IDrive)
  static Future<bool> validateS3({
    required String accessKey,
    required String secretKey,
    required String region,
    required String endpoint,
    required String bucket,
  }) async {
    try {
      final signer = AWSSigV4Signer(
        credentialsProvider: AWSCredentialsProvider(
          AWSCredentials(accessKey, secretKey),
        ),
      );

      // Construct HeadBucket request
      final uri = Uri.parse('$endpoint/$bucket');
      final request = AWSHttpRequest(
        method: AWSHttpMethod.head,
        uri: uri,
        headers: {'Host': uri.host},
      );

      // Sign the request with AWS Signature V4
      final signedRequest = await signer.sign(
        request,
        credentialScope:
            AWSCredentialScope(region: region, service: AWSService.s3),
      );

      // Execute via standard HTTP
      final response = await http_lib.head(
        signedRequest.uri,
        headers: Map.from(signedRequest.headers),
      );

      // 200 OK means bucket exists and we have permission
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
