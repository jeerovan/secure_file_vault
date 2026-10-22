import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_recon.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_crypto.dart';
import 'package:file_vault_bb/utils/utils_sync.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';

/// Run this fixture in a private checkout of the baseline commit, preserving
/// every lib/ source byte. Add only the integration-test SDK dependency and an
/// isolated Android application ID. It intentionally rejects modern headers.
/// Credentials and the separate disposable backend arrive through private
/// --dart-define-from-file input; never copy the owner's .env into that checkout.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late SodiumSumo sodium;
  Directory? source;
  var isolatedInstallVerified = false;
  final inputs =
      jsonDecode(const String.fromEnvironment('FIFE_NATIVE_PROVIDER_INPUTS'))
          as List;
  const timeout = Duration(minutes: 5);

  setUpAll(() async {
    expect(const bool.fromEnvironment('FIFE_RUN_LEGACY_NATIVE_TESTS'), isTrue);
    expect(const String.fromEnvironment('FIFE_LEGACY_BASE_COMMIT'),
        '297c9a6f613395ad774d59444b0fc26de5a2289e');
    expect(Platform.isAndroid, isTrue);
    expect((await DeviceInfoPlugin().androidInfo).isPhysicalDevice, isFalse);
    expect((await PackageInfo.fromPlatform()).packageName,
        'com.jeerovan.fife.legacytest');
    expect(AppEnv.localTestingBuild, isTrue);
    expect(AppEnv.localTestUserId.startsWith('fife-legacy-client-'), isTrue);
    expect(AppEnv.effectiveApiBaseUrl, AppEnv.apiBaseUrl);
    expect(Uri.parse(AppEnv.effectiveApiBaseUrl).port, isNot(5173),
        reason: 'Do not use the owner’s normal local test server');
    expect(inputs.map((input) => input['id']), orderedEquals([2, 3, 4, 5, 6]));
    isolatedInstallVerified = true;
    await addTrustedCertificates();
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    await StorageSqlite.instance.clearDb();
    ModelSetting.clear();
    await SecureStorage().clear();
    await ModelSetting.set(AppString.localTesting.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    await ModelSetting.set(AppString.deviceUuid.string, 'legacy-client-device');
    await ModelSetting.set(AppString.deviceHash.string, 'legacy-client-root');
    await (await ModelProfile.fromMap(
            {'id': AppEnv.localTestUserId, 'email': localTestEmailId}))
        .insert();
    sodium = await SodiumSumoInit.init();
    final keys = CryptoUtils(sodium).generateKeys().getResult()!;
    for (final entry
        in (keys[AppString.privateKeys.string] as Map<String, dynamic>)
            .entries) {
      await SecureStorage().write(key: entry.key, value: entry.value as String);
    }
    expect(
        (await BackendApi().post(
            endpoint: '/keys',
            jsonBody: keys[AppString.serverKeys.string]))['success'],
        1);
    expect(
        (await BackendApi(deviceUuidProvider: () async => '')
            .post(endpoint: '/devices', jsonBody: {
          'device_uuid': 'legacy-client-device',
          'title': 'Isolated baseline client fixture',
          'type': 1,
          'active': 1,
        }))['success'],
        1);
    await (await StorageSqlite.instance.database).insert('items', {
      'id': 'legacy-client-root',
      'name': 'Legacy client fixture',
      'is_folder': 1
    });
    source = await Directory(
            '${(await getApplicationDocumentsDirectory()).path}/legacy-fixture')
        .create();
  });

  for (final raw in inputs) {
    final input = Map<String, dynamic>.from(raw as Map);
    final name = input['name'] as String;
    final providerId = input['id'] as int;
    testWidgets('baseline client: $name modified multipart sync and deletion',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: Text('Legacy client checks')))));
      AppHttpClients.closeAll();
      final observer = _LegacyRequests(http.Client());
      final directory = await Directory('${source!.path}/$name').create();
      try {
        await http.runWithClient(() async {
          final registration = await BackendApi().post(
              endpoint: '/$name/add-account',
              jsonBody: Map<String, dynamic>.from(input['fields'] as Map));
          expect(registration['success'] == 1, isTrue,
              reason: '$name must accept the baseline registration body');
          final db = await StorageSqlite.instance.database;
          final rootId = 'legacy-$name';
          await db.insert('items', {
            'id': rootId,
            'parent_id': 'legacy-client-root',
            'name': name,
            'path': directory.path,
            'is_folder': 1
          });
          final recon = ReconciliationService(sodium);
          final file = File('${directory.path}/edited.bin');
          Future<ModelItem> discover(List<int> bytes) async {
            await file.writeAsBytes(bytes, flush: true);
            expect(
                (await recon.reconcile((await ModelItem.get(rootId))!)).status,
                ReconciliationStatus.completed);
            final rows = await db.query('items',
                where: 'root_id = ? AND is_folder = 0', whereArgs: [rootId]);
            expect(rows.length, 1);
            expect(await SyncUtils.pushMapChanges(), isTrue);
            return ModelItem.fromMap(rows.single);
          }

          Future<void> upload(ModelItem item) async {
            for (var step = 0; step < 14; step++) {
              final task = await ModelItemTask.get(item.id);
              if (task == null) break;
              expect(task.state, TransferTaskState.pending);
              await TaskManager().checkInitUpload(task).timeout(timeout);
            }
            expect(await ModelItemTask.get(item.id), isNull);
            final uploaded = (await ModelFile.get(item.fileHash!))!;
            expect(uploaded.providerId, providerId);
            expect(uploaded.uploadedAt, greaterThan(0));
            expect(await SyncUtils.pushMapChanges(), isTrue);
          }

          final original = await discover(utf8.encode('legacy original $name'));
          await upload(original);
          final bytes = List<int>.generate(
              35 * 1024 * 1024 + 19, (index) => (index + providerId) % 251);
          final edited = await discover(bytes);
          expect(edited.id, original.id);
          expect(edited.fileHash, isNot(original.fileHash));
          expect((await ModelFile.get(edited.fileHash!))!.parts, 2);
          await upload(edited);
          await file.delete();
          await ModelItemTask.addTask(edited.id, ItemTask.download.value);
          for (var step = 0; step < 14; step++) {
            final task = await ModelItemTask.get(edited.id);
            if (task == null) break;
            await TaskManager().checkInitDownload(task).timeout(timeout);
          }
          expect(await ModelItemTask.get(edited.id), isNull);
          final restored = await file.readAsBytes();
          expect(restored.length, bytes.length);
          expect(sha256.convert(restored), sha256.convert(bytes));
          await file.delete();
          expect((await recon.reconcile((await ModelItem.get(rootId))!)).status,
              ReconciliationStatus.completed);
          expect(await SyncUtils.pushMapChanges(), isTrue);
          final retained = (await ModelItem.get(edited.id))!;
          expect(retained.scanState, 0);
          expect(retained.archivedAt, 0);
          retained.archivedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
          await retained.update(['archived_at']);
          expect(await SyncUtils.pushMapChanges(), isTrue);
          expect((await ModelItem.getArchived()).map((item) => item.id),
              contains(edited.id));
          final saved = (await ModelFile.get(edited.fileHash!))!;
          final download = await BackendApi().post(
              endpoint: '/$name/get-download-url',
              jsonBody: {
                'storage_id': saved.storageId,
                'file_id': '${edited.fileHash}_1'
              });
          expect(download['success'], 1);
          expect(download['data'] is String, isTrue,
              reason: 'Legacy clients consume a URL string');
          final cloudUrl = Uri.parse(download['data'] as String);
          expect(await _cloudStatus(cloudUrl), 206);
          await retained.remove();
          expect(await SyncUtils.pushMapChanges(), isTrue);
          expect(await ModelItem.get(edited.id), isNull);
          expect(await _cloudStatus(cloudUrl), 404);
          expect(observer.backendRequests, greaterThan(0));
          expect(observer.legacyUploadAuthorizations, greaterThanOrEqualTo(3));
          debugPrint('Baseline $name: modified multipart bytes, URL string, '
              'Trash and permanent deletion passed');
        }, () => observer);
      } finally {
        AppHttpClients.closeAll();
        observer.close();
      }
    }, timeout: const Timeout(Duration(minutes: 12)));
  }

  tearDownAll(() async {
    // A failed install/identity guard must never clear an ordinary app.
    if (!isolatedInstallVerified) return;
    await TaskManager.stopBackgroundWakes();
    AppHttpClients.closeAll();
    await SecureStorage().clear();
    await StorageSqlite.instance.clearDb();
    ModelSetting.clear();
    final directory = source;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });
}

class _LegacyRequests extends http.BaseClient {
  _LegacyRequests(this.delegate);
  final http.Client delegate;
  int backendRequests = 0;
  int legacyUploadAuthorizations = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final backend = Uri.parse(AppEnv.effectiveApiBaseUrl);
    final toBackend =
        request.url.host == backend.host && request.url.port == backend.port;
    if (toBackend) {
      backendRequests++;
      final headers = request.headers.keys.map((key) => key.toLowerCase());
      expect(headers, isNot(contains('x-fife-vault-protocol')));
      expect(headers, isNot(contains('x-fife-managed-uploads')));
      expect(request.url.path.startsWith('/api/uploads/'), isFalse);
    }
    final response = await delegate.send(request);
    if (!toBackend || !request.url.path.endsWith('/get-upload-url')) {
      return response;
    }
    // The baseline transfer implementation uses dart:io directly. Observe the
    // authorization contract it consumes rather than counting package:http I/O.
    final bytes = await response.stream.toBytes();
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    expect(envelope['success'] == 1, isTrue);
    final data = envelope['data'];
    if (request.url.path.endsWith('/b2/get-upload-url')) {
      expect(data is Map, isTrue);
      expect(data['authorizationToken'] is String, isTrue);
      expect(data['authorizationToken'].isNotEmpty == true, isTrue);
      expect(data['uploadUrl'] is String, isTrue);
    } else {
      expect(data is String, isTrue);
    }
    legacyUploadAuthorizations++;
    return http.StreamedResponse(Stream.value(bytes), response.statusCode,
        contentLength: bytes.length,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase);
  }

  @override
  void close() => delegate.close();
}

Future<int> _cloudStatus(Uri uri) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    // Bypass the observer's zone factory so this short probe cannot close the
    // baseline application's shared backend/transfer client.
    final client = IOClient(HttpClient());
    try {
      final request = http.Request('GET', uri)..headers['Range'] = 'bytes=0-0';
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      await response.stream.drain<void>();
      return response.statusCode;
    } on SocketException {
      if (attempt == 2) rethrow;
    } on http.ClientException {
      if (attempt == 2) rethrow;
    } finally {
      client.close();
    }
  }
  throw StateError('No provider response');
}
