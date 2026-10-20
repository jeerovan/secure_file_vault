import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import '../models/model_change.dart';
import 'package:flutter/foundation.dart';
import '../services/service_backend.dart';
import '../services/service_events.dart';
import '../services/service_recon.dart';
import '../services/service_reconciliation_coordinator.dart';
import '../services/service_sync_budget.dart';
import '../services/service_session_cleanup.dart';
import '../services/service_session_work.dart';
import '../storage/storage_secure.dart';
import '../storage/storage_channel.dart';
import '../storage/storage_sqlite.dart';
import '../storage/local_item_access.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../models/model_file.dart';
import '../models/model_item.dart';
import '../models/model_item_task.dart';
import '../models/model_part.dart';
import '../models/model_state.dart';
import '../services/service_logger.dart';
import '../utils/utils_crypto.dart';
import '../utils/utils_file.dart';
import '../utils/utils_sync_cursor.dart';
import '../utils/utils_transfer_staging.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// A deadline-limited callback drains eligible durable work first. Discovery
/// resumes once that queue is empty; foreground passes always discover edits.
Future<bool> runSyncPass({
  required Future<bool> Function() hasPendingTransfers,
  required Future<bool> Function() reconcile,
  required Future<bool> Function() sync,
}) async {
  SyncBudget.check();
  if (SyncBudget.current != null) {
    final pending = await hasPendingTransfers();
    SyncBudget.check();
    if (pending) return sync();
  }
  final reconciled = await reconcile();
  final synced = await sync();
  return reconciled && synced;
}

class SyncUtils {
  // Singleton setup
  static final SyncUtils _instance = SyncUtils._internal();
  factory SyncUtils() => _instance;
  SyncUtils._internal();

  Timer? _foregroundSyncTimer;

  static final logger = AppLogger(prefixes: ["Sync"]);

  void startAutoSync() {
    final minutes = isDebugEnabled ? 5 : 15;
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = Timer.periodic(Duration(minutes: minutes), (timer) {
      reconFolders(caller: "AutoSync");
    });
  }

  void stopAutoSync() {
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = null;
  }

  // Pass inBackground flag to determine if we should await everything
  Future<bool> reconFolders({String caller = ""}) async {
    return SessionWork.run(() => _reconFolders(caller: caller));
  }

  Future<bool> _reconFolders({String caller = ""}) async {
    String? userId = await getSignedInUserId();
    if (userId == null) {
      return true;
    }
    bool canAccessSecureStorage = await canSync();
    if (!canAccessSecureStorage) {
      logger.error("Can not access secure storage");
      return SyncBudget.current == null;
    }

    logger.info("Start recon from $caller");
    return runSyncPass(
      hasPendingTransfers: () async =>
          await ModelItemTask.fetchPendingTask({}) != null,
      reconcile: _reconcileLocalFolders,
      sync: () => triggerSync(caller: caller),
    );
  }

  Future<bool> _reconcileLocalFolders() async {
    bool reconciliationSucceeded = true;
    try {
      SodiumSumo sodium = await SodiumSumoInit.init();
      List<ModelItem> syncFolders = await ModelItem.getAllSyncedFolders();
      final budget = SyncBudget.current;
      if (budget != null) {
        // Retired roots without an active bookmark are not local scan sources.
        syncFolders = syncFolders
            .where((root) =>
                root.archivedAt == 0 &&
                ChannelStorage.hasUsableBookmark(root.bookmark))
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        final cursor = await ModelState.get('background_reconciliation_cursor');
        final cursorIndex = syncFolders.indexWhere((root) => root.id == cursor);
        if (cursorIndex >= 0) {
          syncFolders = [
            ...syncFolders.skip(cursorIndex + 1),
            ...syncFolders.take(cursorIndex + 1)
          ];
        }
        if (syncFolders.length > budget.maxRoots) {
          reconciliationSucceeded = false;
        }
        syncFolders = syncFolders.take(budget.maxRoots).toList();
      }
      for (ModelItem syncFolder in syncFolders) {
        SyncBudget.check(reserve: const Duration(seconds: 5));
        final result =
            await ReconciliationService(sodium).reconcile(syncFolder);
        if (result.status == ReconciliationStatus.failed ||
            result.status == ReconciliationStatus.partial ||
            (budget != null && !result.succeeded)) {
          reconciliationSucceeded = false;
        }
        if (budget != null && !budget.interrupted) {
          await ModelState.set(
              'background_reconciliation_cursor', syncFolder.id);
        }
      }
    } catch (e, stackTrace) {
      logger.error("Recon failed", error: e, stackTrace: stackTrace);
      reconciliationSucceeded = false;
    }
    return reconciliationSucceeded;
  }

  static Future<void> waitAndSyncChanges(String caller) async {
    logger.info("wait and sync (Foreground)");
    await _instance.triggerSync(caller: caller);
  }

  Future<bool> triggerSync({String caller = ""}) async {
    return SessionWork.run(() => _triggerSync(caller: caller));
  }

  Future<bool> _triggerSync({String caller = ""}) async {
    SyncBudget.check();
    final lease = await ExclusiveOperationCoordinator.tryAcquire('metadata');
    if (lease == null) {
      logger.warning("Sync already in progress. from $caller.");
      return SyncBudget.current == null;
    }

    EventStream().publish(AppEvent(
      type: EventType.system,
      id: 'metadata',
      key: EventKey.running,
    ));
    try {
      SyncBudget.check();
      logger.info("sync request from $caller");

      bool canSync = await SyncUtils.canSync();
      if (!canSync) {
        logger.warning("can not sync. from $caller");
        return SyncBudget.current == null;
      }

      // Check connectivity for both foreground and native background callbacks.
      bool hasInternet = await InternetConnection().hasInternetAccess;
      if (!hasInternet) {
        logger.info("No internet, from $caller");
        return false;
      }
      // refresh jwt first
      await refreshNeonAuth();

      return await _performSyncOperations(caller);
    } catch (e, stack) {
      logger.error("Sync failed", error: e, stackTrace: stack);
      return false;
    } finally {
      await lease.release();
      EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'metadata',
        key: EventKey.stopped,
      ));
    }
  }

  Future<bool> _performSyncOperations(String caller) async {
    logger.info("$caller|------------------START----------------");
    try {
      bool removed = await checkDeviceStatus();
      if (removed) return true;
      final allFetched = await fetchMapChanges();
      if (!allFetched) return false;
      final allPushed = await pushMapChanges();
      if (!allPushed) return false;
      await TaskManager.init(
        retryWakeHandler: () => triggerSync(caller: 'TransferRetry'),
      );
      SyncBudget.check();
      if (SyncBudget.current != null &&
          (await StorageSqlite.instance.getAll(Tables.itemTasks.string))
              .isNotEmpty) {
        return false;
      }
      return await pushMapChanges();
    } catch (e, s) {
      logger.error("Sync failed", error: e, stackTrace: s);
      return false;
    } finally {
      if (simulateTesting()) {
        await Future.delayed(const Duration(seconds: 10));
      }
      logger.info("$caller|------------------ENDED----------------");
    }
  }

  // to sync, one must have masterKey with
  static Future<bool> canSync() async {
    if (await SecureStorage()
        .containsKey(key: AppString.recoveryResetStage.string)) {
      return false;
    }
    String? masterKey = await getMasterKey();
    bool hasKeys = masterKey != null;
    return hasKeys;
  }

  static Future<bool> checkDeviceStatus() async {
    try {
      return await SessionWork.run(_checkDeviceStatus);
    } on SessionInvalidated {
      return true;
    }
  }

  static Future<bool> _checkDeviceStatus() async {
    bool removed = false;
    if (!simulateTesting()) {
      final api = BackendApi();
      try {
        String deviceId = await getDeviceUuid();
        final response = await api.get(
            endpoint: '/devices', queryParameters: {'device_uuid': deviceId});
        if (!SessionWork.active) return true;
        final status = response["success"];
        if (status == -1) {
          logger.error("checkDeviceStatus", error: response["message"]);
        } else if (status == 1) {
          final data = response["data"];
          removed = data == null ||
              (data is Map && (data.isEmpty || data["active"] == 0));
        } else if (status == 0 &&
            response['message'].toString() == '1' &&
            deviceId.isNotEmpty &&
            await getMasterKey() != null) {
          // NO_USER is revocation only for an already registered local vault.
          // A fresh OTP sign-in with no server keys still uses normal onboarding.
          removed = true;
        }

        if (removed) {
          // Revoked devices cannot rely on authenticated remote signout.
          await SessionCleanup.instance.request();
        }
      } on SessionInvalidated {
        rethrow;
      } catch (e, s) {
        logger.error("checkDeviceStatus", error: e, stackTrace: s);
      }
    }
    logger.info("device Status Checked");
    return removed;
  }

  static Future<bool> signout() async {
    bool success = false;
    bool hasInternet = await InternetConnection().hasInternetAccess;
    if (!hasInternet) return false;
    String? userId = await getSignedInUserId();
    if (userId != null) {
      String deviceUuid = await getDeviceUuid();
      try {
        if (localTesting()) {
          final api = BackendApi();
          final response =
              await api.post(endpoint: '/local-test/reset', jsonBody: {});
          if (response["success"] != 1) return false;
        } else if (!simulateTesting()) {
          if (deviceUuid.isNotEmpty) {
            final api = BackendApi();
            final response = await api.post(
                endpoint: '/signout', jsonBody: {"device_uuid": deviceUuid});
            if (response["success"] == 0) {
              return false;
            }
          }
          // Neon signout
          bool success = await NeonAuth().signOut();
          if (!success) {
            return false;
          }
        }
        success = await resetDevice();
      } catch (e, s) {
        logger.error("signout", error: e, stackTrace: s);
      }
    }
    return success;
  }

  static Future<bool> resetDevice() async {
    return SessionCleanup.instance.request();
  }

  static Future<Map<String, dynamic>?> prepareChangeToPush(
      Map<String, dynamic> map,
      {int deleteTask = 0}) async {
    String? masterKeyBase64 = await getMasterKey();
    String? userId = await getSignedInUserId();
    if (masterKeyBase64 != null && userId != null && !simulateTesting()) {
      final payload = Map<String, dynamic>.from(map);
      String table = payload["table"];
      String rowId = payload['id'];
      String changeId = '$table|$rowId';
      payload["deleted"] = deleteTask;

      ModelChange change = await ModelChange.fromMap(
          {"id": changeId, "data": payload, "table_name": table});
      return change.toMap();
    }
    return null;
  }

  static Future<bool> pushMapChanges() async {
    logger.info("Push Map Changes");
    String? masterKeyBase64 = await getMasterKey();
    if (simulateTesting()) {
      return true;
    }
    if (masterKeyBase64 == null) {
      return false;
    }
    final api = BackendApi();
    bool allpushed = true;
    bool changesAvailable = true;
    Uint8List masterKeyBytes = base64Decode(masterKeyBase64);
    var pages = 0;
    while (changesAvailable) {
      SyncBudget.check();
      if (SyncBudget.current case final budget?) {
        if (++pages > budget.maxMetadataPages) return false;
      }
      changesAvailable = false;
      List<Map<String, dynamic>> tableMaps = [];
      List<ModelChange> tableChanges = [];
      for (String table in [
        Tables.files.string,
        Tables.items.string,
        Tables.parts.string
      ]) {
        List<ModelChange> changes = await ModelChange.fetchForTable(table);
        List<Map<String, dynamic>> changeMaps = [];
        for (ModelChange change in changes) {
          SyncBudget.check();
          Map<String, dynamic> changeData = change.data;
          if (table == Tables.items.string) {
            Map<String, dynamic> changeMap = {};
            changeMap.addAll({
              "id": changeData["id"],
              "updated_at": changeData["updated_at"],
            });
            SodiumSumo sodium = await SodiumSumoInit.init();
            CryptoUtils cryptoUtils = CryptoUtils(sodium);

            String jsonString = jsonEncode(changeData);
            Uint8List plainBytes = Uint8List.fromList(utf8.encode(jsonString));

            Map<String, dynamic> encryptedDataMap =
                cryptoUtils.getEncryptedBytesMap(plainBytes, masterKeyBytes);
            changeMap.addAll(encryptedDataMap);
            changeMaps.add(changeMap);
          } else {
            changeMaps.add(changeData);
          }
          tableChanges.add(change);
        }
        if (changeMaps.isNotEmpty) {
          tableMaps.add({"table": table, "changes": changeMaps});
        }
      }
      if (tableMaps.isNotEmpty) {
        SyncBudget.check();
        changesAvailable = true;

        Map<String, dynamic> requestData = {
          AppString.tableMaps.string: tableMaps
        };
        final response =
            await api.post(endpoint: '/sync', jsonBody: requestData);
        if (response["success"] == 1) {
          for (ModelChange change in tableChanges) {
            ModelChange? dbChange = await ModelChange.get(change.id);
            if (dbChange != null) {
              if (dbChange.updatedAt == change.updatedAt) {
                await dbChange.delete();
              }
            }
          }
        } else {
          allpushed = false;
          break;
        }
      }
    }
    logger.info("Pushed Map Changes");
    return allpushed;
  }

  static Future<bool> fetchMapChanges() async {
    String? masterKeyBase64 = await getMasterKey();
    if (simulateTesting()) {
      return true;
    }
    if (masterKeyBase64 == null) {
      return false;
    }
    logger.info("Fetch Map Changes");
    final api = BackendApi();
    Uint8List masterKeyBytes = base64Decode(masterKeyBase64);
    SodiumSumo sodium = await SodiumSumoInit.init();
    CryptoUtils cryptoUtils = CryptoUtils(sodium);
    // process in the order
    List<String> tables = [
      Tables.profiles.string,
      Tables.files.string,
      Tables.items.string,
      Tables.parts.string
    ];
    bool allFetched = true;
    bool changesAvailable = true;
    var pages = 0;
    while (changesAvailable) {
      SyncBudget.check();
      if (SyncBudget.current case final budget?) {
        if (++pages > budget.maxMetadataPages) return false;
      }
      changesAvailable = false;
      final deletionLeases = <OperationLease>[];
      final profileCursor = SyncCursor(
        timestamp: int.parse(await ModelState.get(
            AppString.lastProfileTS.string,
            defaultValue: '0')),
        rowId: int.parse(await ModelState.get(AppString.lastProfileId.string,
            defaultValue: '0')),
      );
      final itemCursor = SyncCursor(
        timestamp: int.parse(await ModelState.get(AppString.lastItemTS.string,
            defaultValue: '0')),
        rowId: int.parse(await ModelState.get(AppString.lastItemId.string,
            defaultValue: '0')),
      );
      final fileCursor = SyncCursor(
        timestamp: int.parse(await ModelState.get(AppString.lastFileTS.string,
            defaultValue: '0')),
        rowId: int.parse(await ModelState.get(AppString.lastFileId.string,
            defaultValue: '0')),
      );
      final partCursor = SyncCursor(
        timestamp: int.parse(await ModelState.get(AppString.lastPartTS.string,
            defaultValue: '0')),
        rowId: int.parse(await ModelState.get(AppString.lastPartId.string,
            defaultValue: '0')),
      );
      try {
        // fetch clubbed changes
        Map<String, dynamic> requestData = {
          AppString.lastProfileTS.string: profileCursor.timestamp,
          AppString.lastProfileId.string: profileCursor.rowId,
          AppString.lastFileTS.string: fileCursor.timestamp,
          AppString.lastFileId.string: fileCursor.rowId,
          AppString.lastItemTS.string: itemCursor.timestamp,
          AppString.lastItemId.string: itemCursor.rowId,
          AppString.lastPartTS.string: partCursor.timestamp,
          AppString.lastPartId.string: partCursor.rowId,
        };
        final responseData =
            await api.get(endpoint: '/sync', queryParameters: requestData);
        if (responseData["success"] <= 0) {
          allFetched = false;
          break;
        }
        final mutations = <SyncPageMutation>[];
        Map<String, dynamic> tableChanges = responseData["data"];
        for (String table in tables) {
          if (!tableChanges.containsKey(table)) continue;
          List<dynamic> changesMap = tableChanges[table];
          if (changesMap.isEmpty) {
            continue;
          }
          changesAvailable = true;
          for (Map<String, dynamic> changeMap in changesMap) {
            SyncBudget.check();
            Map<String, dynamic> map = {};
            if (table == Tables.items.string) {
              int itemTS = int.parse(changeMap["3"].toString());
              map[AppString.textCipher.string] = changeMap["7"];
              map[AppString.textNonce.string] = changeMap["8"];
              map[AppString.keyCipher.string] = changeMap["9"];
              map[AppString.keyNonce.string] = changeMap["10"];
              int clientTS = int.parse(changeMap["11"].toString());
              Uint8List? decryptedBytes =
                  cryptoUtils.getDecryptedBytesFromMap(map, masterKeyBytes);
              if (decryptedBytes == null) {
                throw const FormatException("Unable to decrypt sync item");
              }
              String jsonString = utf8.decode(decryptedBytes);
              Map<String, dynamic> itemMap = jsonDecode(jsonString);
              int deleteTask = int.parse(itemMap["deleted"].toString());
              if (deleteTask > 0) {
                String itemId = itemMap["id"];
                final existingItem = await ModelItem.get(itemId);
                var shouldDelete = existingItem != null &&
                    existingItem.updatedAt <= clientTS &&
                    !existingItem.isFolder;
                if (existingItem != null &&
                    existingItem.updatedAt <= clientTS &&
                    existingItem.isFolder) {
                  shouldDelete = await LocalItemAccess.withAccess(itemId,
                      (itemPath) async => !await Directory(itemPath).exists());
                }
                if (shouldDelete) {
                  if (!existingItem!.isFolder) {
                    final lease =
                        await _prepareRemoteFileDeletion(existingItem);
                    deletionLeases.add(lease);
                  }
                  mutations.add(SyncPageMutation.deleteIfNotNewer(
                    table: Tables.items.string,
                    id: itemId,
                    remoteUpdatedAt: clientTS,
                  ));
                }
              } else {
                ModelItem newModelItem = await ModelItem.fromMap(itemMap);
                mutations.add(SyncPageMutation.upsertIfNewer(
                  table: Tables.items.string,
                  id: newModelItem.id,
                  row: newModelItem.toMap(),
                  remoteUpdatedAt: newModelItem.updatedAt,
                ));
              }
              itemCursor.advance(itemTS, int.parse(changeMap["1"].toString()));
            } else if (table == Tables.files.string) {
              ModelFile newModelFile = await ModelFile.fromServerMap(changeMap);
              String fileHash = newModelFile.id;
              int fileServerTS = int.parse(changeMap["3"].toString());
              int clientTS = newModelFile.updatedAt;
              int deleteTask = int.parse(changeMap["14"].toString());
              if (deleteTask > 0) {
                mutations.add(SyncPageMutation.deleteIfNotNewer(
                  table: Tables.files.string,
                  id: fileHash,
                  remoteUpdatedAt: clientTS,
                ));
              } else {
                mutations.add(SyncPageMutation.upsertIfNewer(
                  table: Tables.files.string,
                  id: fileHash,
                  row: newModelFile.toMap(),
                  remoteUpdatedAt: clientTS,
                ));
              }
              fileCursor.advance(
                  fileServerTS, int.parse(changeMap["1"].toString()));
            } else if (table == Tables.parts.string) {
              int partServerTS = int.parse(changeMap["3"].toString());
              ModelPart newModelPart = await ModelPart.fromServerMap(changeMap);
              final partId = newModelPart.id;
              int clientTS = newModelPart.updatedAt;
              int deleteTask = int.parse(changeMap["13"].toString());
              if (deleteTask > 0) {
                mutations.add(SyncPageMutation.deleteIfNotNewer(
                  table: Tables.parts.string,
                  id: partId,
                  remoteUpdatedAt: clientTS,
                ));
              } else {
                mutations.add(SyncPageMutation.upsertIfNewer(
                  table: Tables.parts.string,
                  id: partId,
                  row: newModelPart.toMap(),
                  remoteUpdatedAt: clientTS,
                ));
              }
              partCursor.advance(
                  partServerTS, int.parse(changeMap["1"].toString()));
            } else if (table == Tables.profiles.string) {
              int profileTS = int.parse(changeMap["3"].toString());
              String profileId = changeMap["4"];
              map["username"] = changeMap["5"];
              map["image"] = changeMap["8"];
              map["plan_expires_at"] = int.parse(
                  getValueFromMap(changeMap, "9", defaultValue: 0).toString());
              mutations.add(SyncPageMutation.updateExisting(
                table: Tables.profiles.string,
                id: profileId,
                row: map,
              ));
              profileCursor.advance(
                  profileTS, int.parse(changeMap["1"].toString()));
            }
          }
        }
        for (final lease in deletionLeases) {
          if (!await lease.prepareForCommit()) {
            throw StateError('Lost remote file deletion lease');
          }
        }
        SyncBudget.check();
        await StorageSqlite.instance.applySyncPage(mutations, {
          AppString.lastFileTS.string: fileCursor.timestamp,
          AppString.lastFileId.string: fileCursor.rowId,
          AppString.lastPartTS.string: partCursor.timestamp,
          AppString.lastPartId.string: partCursor.rowId,
          AppString.lastItemTS.string: itemCursor.timestamp,
          AppString.lastItemId.string: itemCursor.rowId,
          AppString.lastProfileTS.string: profileCursor.timestamp,
          AppString.lastProfileId.string: profileCursor.rowId,
        });
        logger.info("Fetched Map Changes");
      } catch (e, s) {
        logger.error("fetchMapChanges", error: e, stackTrace: s);
        allFetched = false;
        changesAvailable = false;
        break;
      } finally {
        for (final lease in deletionLeases.reversed) {
          try {
            await lease.release();
          } catch (e, s) {
            logger.error('Failed to release remote deletion lease',
                error: e, stackTrace: s);
          }
        }
      }
    }
    return allFetched;
  }

  static Future<OperationLease> _prepareRemoteFileDeletion(
      ModelItem item) async {
    final lease = await ExclusiveOperationCoordinator.tryAcquire(
      TaskManager.downloadOperationId(item.id),
    );
    if (lease == null) {
      throw StateError('Download is active for remotely deleted item');
    }

    try {
      final filePath = await ModelItem.getPathForItem(item.id);
      final managedRootPath = await ModelItem.getPathForItem('fife');
      await deleteManagedFileIfExists(
        filePath: filePath,
        managedRootPath: managedRootPath,
      );

      final fileHash = item.fileHash;
      if (fileHash != null) {
        final modelFile = await ModelFile.get(fileHash);
        final staging = DownloadStaging(
          baseDirectory: await getAppTempDirectory(),
          itemId: item.id,
          fileHash: fileHash,
          partCount: modelFile?.parts ?? 1,
          expectedPlaintextLength: item.size,
        );
        await staging.cleanup();
      }
      await ModelItemTask.completeTask(item.id);
      return lease;
    } catch (_) {
      await lease.release();
      rethrow;
    }
  }
}
