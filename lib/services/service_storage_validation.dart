import 'dart:convert';
import 'package:http/http.dart' as http_lib;
import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

class StorageValidationService {
  /// Validates Backblaze credentials replicating your backend logic
  static Future<String> validateBackblaze(String appId, String appKey) async {
    final String basicAuth =
        'Basic ${base64Encode(utf8.encode('$appId:$appKey'))}';

    try {
      final response = await http_lib.get(
        Uri.parse('https://api.backblazeb2.com/b2api/v4/b2_authorize_account'),
        headers: {'Authorization': basicAuth},
      );

      if (response.statusCode == 401) {
        return 'Invalid Application Key ID or Application Key.';
      } else if (response.statusCode != 200) {
        // Attempt to parse Backblaze's standard error response format
        try {
          final errorData = jsonDecode(response.body);
          return errorData['message'] ??
              'Authorization failed (HTTP ${response.statusCode}).';
        } catch (_) {
          return 'Authorization failed (HTTP ${response.statusCode}).';
        }
      }

      final data = jsonDecode(response.body);

      // Safe navigation for nested maps
      final apiInfo = data['apiInfo'];
      if (apiInfo == null ||
          apiInfo['storageApi'] == null ||
          apiInfo['storageApi']['allowed'] == null) {
        return 'Invalid response structure from Backblaze.';
      }

      final allowed = apiInfo['storageApi']['allowed'];

      final List? buckets = allowed['buckets'];
      final List capabilities = allowed['capabilities'] ?? [];
      final String? namePrefix = allowed['namePrefix'];

      // Replication of Svelte backend logic
      if (buckets == null || buckets.isEmpty) {
        return 'No buckets found. Ensure the key has bucket access.';
      } else if (buckets.length > 1) {
        return 'Multiple buckets allowed. Please restrict the key to a single bucket.';
      } else {
        final bucket = buckets[0];
        final id = bucket['id'];
        final name = bucket['name'];

        if (id == null || name == null) {
          return 'Invalid bucket information returned by the provider.';
        }
      }

      if (namePrefix != null) {
        return 'Keys with a name prefix are not supported.';
      }

      final requiredCaps = [
        'deleteFiles',
        'writeBuckets',
        'readBuckets',
        'readFiles',
        'shareFiles',
        'writeFiles',
        'listFiles'
      ];

      // Find exactly which capabilities are missing to give a better error message
      final missingCaps =
          requiredCaps.where((c) => !capabilities.contains(c)).toList();

      if (missingCaps.isNotEmpty) {
        return 'Key is missing required capabilities: ${missingCaps.join(', ')}';
      }

      return 'ok';
    } catch (e) {
      return 'Network error or unable to reach Backblaze API. Please check your connection.';
    }
  }

  /// Validates S3-compatible providers (Oracle, Cloudflare, IDrive)
  static Future<String> validateS3({
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
      if (response.statusCode == 200) {
        return 'ok';
      } else if (response.statusCode == 403) {
        return 'Access denied. Please check your Access Key and Secret Key, and ensure they have read/write permissions for the bucket.';
      } else if (response.statusCode == 404) {
        return 'Bucket "$bucket" not found. Please verify the bucket name and endpoint.';
      } else if (response.statusCode == 400) {
        return 'Bad request. Ensure the region ($region) matches the endpoint requirements.';
      } else {
        return 'Validation failed with HTTP status ${response.statusCode}.';
      }
    } catch (e) {
      return 'Network error or invalid endpoint URL. Please check your connection and endpoint configuration.';
    }
  }
}
