import 'dart:convert';
import 'package:http/http.dart' as http_lib;
import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';

bool _isNonPublicIpv4(String hostname) {
  final parts = hostname.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((part) => part == null || part < 0 || part > 255)) {
    return true;
  }
  final first = octets[0]!;
  final second = octets[1]!;
  return first == 0 ||
      first == 10 ||
      first == 127 ||
      (first == 100 && second >= 64 && second <= 127) ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168) ||
      (first == 198 && (second == 18 || second == 19)) ||
      first >= 224;
}

bool _isNonPublicIpv6(String hostname) {
  final normalized = hostname.toLowerCase();
  if (!normalized.contains(':')) return false;
  if (normalized.startsWith('::ffff:')) return true;
  final mappedIpv4 = RegExp(
    r'(?:^|:)ffff:(\d+\.\d+\.\d+\.\d+)$',
  ).firstMatch(normalized)?.group(1);
  if (mappedIpv4 != null && _isNonPublicIpv4(mappedIpv4)) return true;
  return normalized == '::' ||
      normalized == '::1' ||
      normalized.startsWith('fc') ||
      normalized.startsWith('fd') ||
      normalized.startsWith('fe8') ||
      normalized.startsWith('fe9') ||
      normalized.startsWith('fea') ||
      normalized.startsWith('feb');
}

String normalizePublicS3Endpoint(String value) {
  final endpoint = Uri.tryParse(value.trim());
  if (endpoint == null ||
      endpoint.scheme != 'https' ||
      !endpoint.hasAuthority ||
      endpoint.host.isEmpty) {
    throw const FormatException('S3 endpoint must be a public HTTPS URL.');
  }
  if (endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment) {
    throw const FormatException(
      'S3 endpoint cannot contain credentials, a query, or a fragment.',
    );
  }
  final hostname = endpoint.host.toLowerCase();
  if (hostname == 'localhost' ||
      hostname.endsWith('.localhost') ||
      hostname.endsWith('.local') ||
      _isNonPublicIpv4(hostname) ||
      _isNonPublicIpv6(hostname)) {
    throw const FormatException('S3 endpoint must use a public host.');
  }

  final normalizedPath = endpoint.path.replaceFirst(RegExp(r'/+$'), '');
  return endpoint
      .replace(path: normalizedPath)
      .toString()
      .replaceFirst(RegExp(r'/+$'), '');
}

Uri buildS3BucketUri({
  required String endpoint,
  required String bucket,
  required bool forcePathStyle,
}) {
  final endpointUri = Uri.parse(normalizePublicS3Endpoint(endpoint));
  if (!forcePathStyle) {
    return endpointUri.replace(host: '$bucket.${endpointUri.host}');
  }
  return endpointUri.replace(
    pathSegments: [
      ...endpointUri.pathSegments.where((segment) => segment.isNotEmpty),
      bucket,
    ],
  );
}

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
    bool forcePathStyle = true,
  }) async {
    try {
      final signer = AWSSigV4Signer(
        credentialsProvider: AWSCredentialsProvider(
          AWSCredentials(accessKey, secretKey),
        ),
      );

      // Construct HeadBucket request
      final uri = buildS3BucketUri(
        endpoint: endpoint,
        bucket: bucket,
        forcePathStyle: forcePathStyle,
      );
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
