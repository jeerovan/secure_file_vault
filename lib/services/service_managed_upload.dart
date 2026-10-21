import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/model_setting.dart';
import '../storage/storage_sqlite.dart';
import '../utils/enums.dart';
import '../utils/utils_file.dart';
import 'service_backend.dart';
import 'service_session_work.dart';

typedef UploadPost = Future<Map<String, dynamic>> Function(
    String endpoint, Map<String, dynamic> body);

class ManagedUploadAttempt {
  const ManagedUploadAttempt(
      {this.supported = true, this.result, this.sent = false, this.existing});
  final bool supported;
  final UploadFileResult? result;
  final bool sent;
  final Map<String, dynamic>? existing;
}

/// Private receipts live in local settings, never in synchronized part JSON.
/// The server owns the cleanup obligation even when these settings are erased.
class ManagedUploadClient {
  ManagedUploadClient({
    UploadPost? post,
    Future<String> Function(String)? read,
    Future<void> Function(String, String)? write,
    Future<void> Function(String)? remove,
  })  : _post = post ??
            ((endpoint, body) => BackendApi().post(
                endpoint: endpoint,
                jsonBody: body,
                retryUnauthorized: true,
                includeHttpStatus: true)),
        _read = read ?? ModelSetting.getRaw,
        _write = write ?? ModelSetting.set,
        _remove = remove ?? ModelSetting.delete;

  final UploadPost _post;
  final Future<String> Function(String) _read;
  final Future<void> Function(String, String) _write;
  final Future<void> Function(String) _remove;
  static String _key(String part) => 'managed_upload:$part';
  static String _cleanupKey(String id) => 'managed_cleanup:$id';

  Map<String, dynamic>? _decode(String raw) {
    try {
      final parsed = jsonDecode(raw);
      return parsed is Map ? Map<String, dynamic>.from(parsed) : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _data(Map<String, dynamic> reply, String id) {
    final data = reply['data'];
    return reply['success'] == 1 &&
            data is Map &&
            data['protocol'] == 'managed-v1' &&
            data['id'] == id
        ? Map<String, dynamic>.from(data)
        : null;
  }

  Future<void> abandon(String part) async {
    final record = _decode(await _read(_key(part)));
    if (record == null) return;
    // Persist before the HTTP request or removing the ordinary part pointer.
    await _write(_cleanupKey(record['id'] as String), jsonEncode(record));
    await _remove(_key(part));
    await _report(record);
  }

  Future<void> _report(Map<String, dynamic> record) async {
    final reply = await _post('/uploads/report', {
      'id': record['id'],
      'receipt': record['receipt'],
    });
    if (reply['_httpStatus'] == 200 &&
        _data(reply, record['id'] as String)?['state'] == 'deleted') {
      await _remove(_cleanupKey(record['id'] as String));
    }
  }

  Future<void> drainCleanup() async {
    final rows = await StorageSqlite.instance.getAll(Tables.settings.string);
    for (final row in rows
        .where((r) => (r['id'] as String).startsWith('managed_cleanup:'))
        .take(4)) {
      await SessionWork.checkpoint();
      final record = _decode(row['value'] as String);
      if (record != null) await _report(record);
    }
  }

  Future<void> forget(String part) => _remove(_key(part));

  Future<ManagedUploadAttempt> transfer({
    required String part,
    required int storageId,
    required String sha1,
    required String md5,
    required int size,
    required Map<String, dynamic> partMetadata,
    required Future<UploadFileResult> Function(
            String url, Map<String, String> headers)
        send,
  }) async {
    var record = _decode(await _read(_key(part)));
    if (record != null &&
        (record['sha1'] != sha1 ||
            record['size'] != size ||
            record['storage_id'] != storageId ||
            record['md5'] != md5)) {
      await abandon(part);
      record = null;
    }
    record ??= {
      'id': const Uuid().v4(),
      'receipt': base64UrlEncode(
              List<int>.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', ''),
      'sha1': sha1,
      'md5': md5,
      'size': size,
      'storage_id': storageId,
    };
    await _write(_key(part), jsonEncode(record));
    if (record['accepted'] != true) {
      final capability = await _post('/uploads/protocol', {});
      if ([404, 405, 501].contains(capability['_httpStatus'])) {
        await _remove(_key(part));
        return const ManagedUploadAttempt(supported: false);
      }
      final advertised = capability['data'];
      if (capability['_httpStatus'] != 200 ||
          capability['success'] != 1 ||
          advertised is! Map ||
          advertised['protocol'] != 'managed-v1') {
        return const ManagedUploadAttempt();
      }
      // Save before the first request that can allocate a cloud upload, so a
      // lost response followed by a backend rollback cannot downgrade it.
      record['accepted'] = true;
      await _write(_key(part), jsonEncode(record));
    }
    final id = record['id'] as String;
    final reply = await _post('/uploads/prepare', {
      'id': id,
      'receipt': record['receipt'],
      'storage_id': storageId,
      'file_id': part,
      'content_sha1': sha1,
      'content_md5': md5,
      'content_length': size,
      'part_metadata': partMetadata,
    });
    // A confirmed managed backend never silently falls back on a later error.
    final descriptor = _data(reply, id);
    if (descriptor == null) return const ManagedUploadAttempt();
    ManagedUploadAttempt? accepted(Map<String, dynamic>? data,
        {bool sent = false}) {
      if (data == null || !['existing', 'complete'].contains(data['state'])) {
        return null;
      }
      if (data['file'] is Map && data['part'] is Map) {
        return ManagedUploadAttempt(existing: data, sent: sent);
      }
      // Compatibility with earlier managed backends that return only a
      // completion version. Carry the operation ID into the metadata ACK.
      if (data['state'] == 'complete') {
        return ManagedUploadAttempt(
            sent: sent,
            result: UploadFileResult.success({
              'managedUploadId': id,
              if (data['fileId'] is String) 'fileId': data['fileId']
            }));
      }
      return const ManagedUploadAttempt();
    }

    final prepared = accepted(descriptor);
    if (reply['_httpStatus'] == 200 && prepared != null) return prepared;
    if (descriptor['state'] == 'deleted') {
      await _remove(_key(part));
      return const ManagedUploadAttempt();
    }
    record['accepted'] = true;
    await _write(_key(part), jsonEncode(record));
    Future<Map<String, dynamic>> complete() => _post('/uploads/complete', {
          'id': id,
          'receipt': record!['receipt'],
        });
    if (record['attempted'] == true || descriptor['state'] == 'pending') {
      final reconciled = await complete();
      final data = _data(reconciled, id);
      final recovered = accepted(data);
      if (reconciled['_httpStatus'] == 200 && recovered != null) {
        return recovered;
      }
      if (data?['state'] == 'deleted') {
        await _remove(_key(part));
        return const ManagedUploadAttempt();
      }
      if (reconciled['message'] != 'upload_not_ready') {
        return const ManagedUploadAttempt();
      }
    }
    if (descriptor['state'] != 'upload' ||
        descriptor['method'] != 'PUT' ||
        descriptor['uploadUrl'] is! String ||
        descriptor['headers'] is! Map) {
      return const ManagedUploadAttempt();
    }
    final uri = Uri.tryParse(descriptor['uploadUrl'] as String);
    final headers = descriptor['headers'] as Map;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        headers.entries.any((e) => e.key is! String || e.value is! String)) {
      return const ManagedUploadAttempt();
    }
    record['attempted'] = true;
    await _write(_key(part), jsonEncode(record));
    final uploaded =
        await send(uri.toString(), Map<String, String>.from(headers));
    if (!uploaded.succeeded) {
      return ManagedUploadAttempt(result: uploaded, sent: true);
    }
    await SessionWork.checkpoint();
    final finalReply = await complete();
    final finalData = _data(finalReply, id);
    return (finalReply['_httpStatus'] == 200
            ? accepted(finalData, sent: true)
            : null) ??
        const ManagedUploadAttempt(sent: true);
  }
}
