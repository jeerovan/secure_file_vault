import 'dart:convert';

import 'package:file_vault_bb/services/service_managed_upload.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Map<String, String> settings;
  late List<String> paths;
  late List<Map<String, dynamic>> bodies;
  late int sends;
  late int capabilityStatus;
  late Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
      handle;
  ManagedUploadClient client() => ManagedUploadClient(
        read: (key) async => settings[key] ?? '',
        write: (key, value) async {
          settings[key] = value;
        },
        remove: (key) async {
          settings.remove(key);
        },
        post: (endpoint, body) async {
          paths.add(endpoint);
          bodies.add(Map.of(body));
          if (endpoint.endsWith('/protocol')) {
            return {
              'success': capabilityStatus == 200 ? 1 : 0,
              '_httpStatus': capabilityStatus,
              if (capabilityStatus == 200) 'data': {'protocol': 'managed-v1'},
            };
          }
          return handle(endpoint, body);
        },
      );
  Map<String, dynamic> reply(Map<String, dynamic> body, String state,
          {int status = 200}) =>
      {
        'success': 1,
        '_httpStatus': status,
        'data': {
          'protocol': 'managed-v1',
          'id': body['id'],
          'state': state,
          if (state == 'upload') ...{
            'method': 'PUT',
            'uploadUrl': 'https://bucket.example.test/part?uploadId=only-part',
            'headers': {'Content-MD5': 'AAAAAAAAAAAAAAAAAAAAAA=='}
          },
          if (state == 'complete') 'fileId': 'exact-version',
        },
      };
  Future<ManagedUploadAttempt> transfer({String digest = 'ciphertext-sha1'}) =>
      client().transfer(
        part: 'opaque_1',
        storageId: 7,
        sha1: digest,
        md5: 'AAAAAAAAAAAAAAAAAAAAAA==',
        size: 37,
        partMetadata: {'cipher': 'encrypted-key', 'nonce': 'key-nonce'},
        send: (url, headers) async {
          sends++;
          return UploadFileResult.success({});
        },
      );
  setUp(() {
    settings = {};
    paths = [];
    bodies = [];
    sends = 0;
    capabilityStatus = 200;
    SessionWork.complete('managed-test');
    handle = (endpoint, body) async =>
        reply(body, endpoint.endsWith('prepare') ? 'upload' : 'complete');
  });

  test(
      'receipt is persisted before authorization and success requires finalization',
      () async {
    handle = (endpoint, body) async {
      expect(settings['managed_upload:opaque_1'], isNotNull);
      expect(body['receipt'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      return reply(body, endpoint.endsWith('prepare') ? 'upload' : 'complete');
    };
    final result = await transfer();
    expect(result.supported, isTrue);
    expect(result.result?.succeeded, isTrue);
    expect(result.result?.data['fileId'], 'exact-version');
    expect(result.result?.data['managedUploadId'], bodies[1]['id']);
    expect(sends, 1);
    expect(
        paths, ['/uploads/protocol', '/uploads/prepare', '/uploads/complete']);
    expect(bodies[1]['part_metadata'],
        {'cipher': 'encrypted-key', 'nonce': 'key-nonce'});
    expect(
        settings['managed_upload:opaque_1'], isNot(contains('encrypted-key')));
    // The caller removes the receipt only after marking the local part uploaded.
    expect(settings, contains('managed_upload:opaque_1'));
    await client().forget('opaque_1');
    expect(settings, isEmpty);
  });

  test('lost finalization reply resumes with the same receipt and no upload',
      () async {
    var lost = true;
    handle = (endpoint, body) async {
      if (endpoint.endsWith('prepare')) return reply(body, 'upload');
      if (lost) {
        lost = false;
        return {'success': -1, 'message': 'Network Error'};
      }
      return reply(body, 'complete');
    };
    expect((await transfer()).result, isNull);
    final saved = jsonDecode(settings['managed_upload:opaque_1']!) as Map;
    final result = await transfer();
    expect(result.result?.succeeded, isTrue);
    expect(sends, 1);
    expect(bodies.where((b) => b.containsKey('id')).map((b) => b['id']).toSet(),
        {saved['id']});
    expect(
        bodies
            .where((b) => b.containsKey('receipt'))
            .map((b) => b['receipt'])
            .toSet(),
        {saved['receipt']});
  });

  test(
      'an older backend permits legacy fallback only before managed acceptance',
      () async {
    handle = (_, __) async =>
        {'success': 0, '_httpStatus': 404, 'message': 'Not found'};
    capabilityStatus = 404;
    expect((await transfer()).supported, isFalse);
    expect(sends, 0);
    expect(settings, isEmpty);
    capabilityStatus = 200;
    handle = (endpoint, body) async =>
        endpoint.endsWith('prepare') ? reply(body, 'upload') : {'success': -1};
    await transfer();
    handle = (_, __) async =>
        {'success': 0, '_httpStatus': 404, 'message': 'Not found'};
    expect((await transfer()).supported, isTrue);
    expect(settings, isNotEmpty);
    expect(sends, 1);
  });

  for (final status in [401, 403, 409, 429, 500, 503]) {
    test('HTTP $status cannot silently downgrade to a direct upload', () async {
      handle = (_, __) async =>
          {'success': 0, '_httpStatus': status, 'message': 'unavailable'};
      final attempt = await transfer();
      expect(attempt.supported, isTrue);
      expect(attempt.result, isNull);
      expect(sends, 0);
    });
  }

  test('an activation pause preserves the receipt and resumes after restart',
      () async {
    var enabled = false;
    handle = (endpoint, body) async {
      if (!enabled) {
        return {
          'success': 0,
          '_httpStatus': 503,
          'message': 'managed_uploads_disabled'
        };
      }
      return reply(body, endpoint.endsWith('prepare') ? 'upload' : 'complete');
    };
    expect((await transfer()).result, isNull);
    final retained = settings['managed_upload:opaque_1'];
    expect(retained, isNotNull);
    expect(sends, 0);

    // Each transfer constructs a fresh client from persisted settings. Once
    // negotiated, a disabled protocol route cannot permit legacy fallback.
    capabilityStatus = 404;
    expect((await transfer()).supported, isTrue);
    expect(settings['managed_upload:opaque_1'], retained);
    expect(paths.where((path) => path.endsWith('/protocol')), hasLength(1));
    expect(sends, 0);

    enabled = true;
    final result = await transfer();
    expect(result.result?.succeeded, isTrue);
    expect(sends, 1);
    final saved = jsonDecode(retained!) as Map;
    final attempts = bodies.where((body) => body.containsKey('receipt'));
    expect(attempts.map((body) => body['id']).toSet(), {saved['id']});
    expect(attempts.map((body) => body['receipt']).toSet(), {saved['receipt']});
    await client().forget('opaque_1');
    expect(settings, isEmpty);
  });

  test(
      'queued deletion survives restart and requires an explicit verified acknowledgement',
      () async {
    await transfer();
    handle =
        (endpoint, body) async => reply(body, 'cleanup_pending', status: 202);
    await client().abandon('opaque_1');
    expect(settings.containsKey('managed_upload:opaque_1'), isFalse);
    final cleanupKey = settings.keys.single;
    expect(cleanupKey, startsWith('managed_cleanup:'));
    expect(paths.last, '/uploads/report');
    final retained = settings[cleanupKey];
    // A misleading 200 queued response still does not acknowledge deletion.
    handle = (_, body) async => reply(body, 'cleanup_pending');
    // Re-report via the preserved record by exposing it as a part pointer.
    settings['managed_upload:opaque_1'] = retained!;
    await client().abandon('opaque_1');
    expect(settings[cleanupKey], retained);
    handle = (_, body) async => reply(body, 'committed');
    settings['managed_upload:opaque_1'] = retained;
    await client().abandon('opaque_1');
    expect(settings[cleanupKey], retained,
        reason: 'A committed file is not a deletion ACK');
    handle = (_, body) async => reply(body, 'deleted');
    settings['managed_upload:opaque_1'] = retained;
    await client().abandon('opaque_1');
    expect(settings, isEmpty);
  });

  test(
      'a different ciphertext retires its old attempt before authorizing a new ID',
      () async {
    await transfer();
    final old = jsonDecode(settings['managed_upload:opaque_1']!) as Map;
    handle = (endpoint, body) async => reply(
        body,
        endpoint.endsWith('report')
            ? 'cleanup_pending'
            : endpoint.endsWith('prepare')
                ? 'upload'
                : 'complete',
        status: endpoint.endsWith('report') ? 202 : 200);
    await transfer(digest: 'replacement-ciphertext');
    final current = jsonDecode(settings['managed_upload:opaque_1']!) as Map;
    expect(current['id'], isNot(old['id']));
    expect(settings, contains('managed_cleanup:${old['id']}'));
    expect(paths[3], '/uploads/report');
    expect(paths[4], '/uploads/protocol');
    expect(paths[5], '/uploads/prepare');
  });

  test('pending or malformed responses never mark a local part uploaded',
      () async {
    handle = (_, body) async => reply(body, 'complete', status: 202);
    expect((await transfer()).result, isNull);
    expect(sends, 0);
    handle = (_, body) async => {
          'success': 1,
          '_httpStatus': 200,
          'data': {
            ...reply(body, 'complete')['data'] as Map,
            'id': 'other-upload'
          }
        };
    expect((await transfer()).result, isNull);
    expect(sends, 0);
  });
  test(
      'lost preparation followed by an older backend cannot downgrade a possible upload',
      () async {
    handle = (_, __) async => {'success': -1, 'message': 'Network Error'};
    expect((await transfer()).result, isNull);
    expect(
        (jsonDecode(settings['managed_upload:opaque_1']!) as Map)['accepted'],
        isTrue);
    handle = (_, __) async =>
        {'success': 0, '_httpStatus': 404, 'message': 'Not found'};
    expect((await transfer()).supported, isTrue);
    expect(sends, 0);
  });
  test('failed read-only negotiation can safely retry against an older backend',
      () async {
    capabilityStatus = 503;
    expect((await transfer()).result, isNull);
    expect(paths, ['/uploads/protocol']);
    capabilityStatus = 404;
    expect((await transfer()).supported, isFalse);
    expect(sends, 0);
    expect(settings, isEmpty);
  });
}
