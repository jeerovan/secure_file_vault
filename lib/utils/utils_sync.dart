import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_auth.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../models/model_change.dart';
import 'package:flutter/foundation.dart';
import '../services/service_backend.dart';
import '../services/service_events.dart';
import '../services/service_recon.dart';
import '../services/service_reconciliation_coordinator.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../models/model_file.dart';
import '../models/model_item.dart';
import '../models/model_part.dart';
import '../models/model_state.dart';
import '../services/service_logger.dart';
import '../storage/storage_secure.dart';
import '../utils/utils_crypto.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

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
    String? userId = await getSignedInUserId();
    if (userId == null) {
      return true;
    }
    bool canAccessSecureStorage = await canSync();
    if (!canAccessSecureStorage) {
      logger.error("Can not access secure storage");
      return true;
    }

    logger.info("Start recon from $caller");
    bool reconciliationSucceeded = true;
    try {
      SodiumSumo sodium = await SodiumSumoInit.init();
      List<ModelItem> syncFolders = await ModelItem.getAllSyncedFolders();
      for (ModelItem syncFolder in syncFolders) {
        final result =
            await ReconciliationService(sodium).reconcile(syncFolder);
        if (result.status == ReconciliationStatus.failed ||
            result.status == ReconciliationStatus.partial) {
          reconciliationSucceeded = false;
        }
      }
    } catch (e, stackTrace) {
      logger.error("Recon failed", error: e, stackTrace: stackTrace);
      reconciliationSucceeded = false;
    }
    final syncSucceeded = await triggerSync(caller: caller);
    return reconciliationSucceeded && syncSucceeded;
  }

  static Future<void> waitAndSyncChanges(String caller) async {
    logger.info("wait and sync (Foreground)");
    await _instance.triggerSync(caller: caller);
  }

  Future<bool> triggerSync({String caller = ""}) async {
    final lease = await ExclusiveOperationCoordinator.tryAcquire('metadata');
    if (lease == null) {
      logger.warning("Sync already in progress. from $caller.");
      return true;
    }

    EventStream().publish(AppEvent(
      type: EventType.system,
      id: 'metadata',
      key: EventKey.running,
    ));
    try {
      logger.info("sync request from $caller");

      bool canSync = await SyncUtils.canSync();
      if (!canSync) {
        logger.warning("can not sync. from $caller");
        return true;
      }

      // Note: Workmanager already ensures network connectivity via constraints on Android
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
      await TaskManager.init();
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
    String? masterKey = await getMasterKey();
    bool hasKeys = masterKey != null;
    return hasKeys;
  }

  static Future<bool> checkDeviceStatus() async {
    bool removed = false;
    if (!simulateTesting()) {
      final api = BackendApi();
      try {
        String deviceId = await getDeviceUuid();
        final response = await api.get(
            endpoint: '/devices', queryParameters: {'device_uuid': deviceId});
        final status = response["success"];
        if (status == -1) {
          logger.error("checkDeviceStatus", error: response["message"]);
        } else if (status == 1) {
          final data = response["data"];
          removed = data == null || data.isEmpty || data["active"] == 0;
        }

        if (removed) {
          // signout
          await signout();
        }
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
        if (!simulateTesting()) {
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
    SecureStorage storage = SecureStorage();
    try {
      if (!simulateTesting() && revenueCatSupported) {
        final isAnonymous = await Purchases.isAnonymous;
        if (!isAnonymous) {
          await Purchases.logOut();
        }
      }
      if (Platform.isAndroid) {
        await ServiceForeground.instance.stop();
      } else if (Platform.isIOS) {
        await BackgroundExecutionService.instance.cancelIosWork();
      }
      final locale = await ModelSetting.getRaw(AppString.locale.string);
      await storage.clear();
      final dbHelper = StorageSqlite.instance;
      await dbHelper.clearDb();
      ModelSetting.clear();
      await clearFiFeDirectory();
      // keep locale
      if (locale.isNotEmpty) {
        await ModelSetting.set(AppString.locale.string, locale);
      }
      await ModelSetting.set(AppString.onboarding.string, "yes");
      EventStream().publish(AppEvent(
          type: EventType.system, id: "signout", key: EventKey.signout));
      return true;
    } catch (e, s) {
      logger.error("Resetting device", error: e, stackTrace: s);
      return false;
    }
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
    while (changesAvailable) {
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
    while (changesAvailable) {
      changesAvailable = false;
      int lastProfileTS = int.parse(await ModelState.get(
          AppString.lastProfileTS.string,
          defaultValue: '0'));
      int lastItemTS = int.parse(
          await ModelState.get(AppString.lastItemTS.string, defaultValue: '0'));
      int lastFileTS = int.parse(
          await ModelState.get(AppString.lastFileTS.string, defaultValue: '0'));
      int lastPartTS = int.parse(
          await ModelState.get(AppString.lastPartTS.string, defaultValue: '0'));
      try {
        // fetch clubbed changes
        Map<String, dynamic> requestData = {
          AppString.lastProfileTS.string: lastProfileTS,
          AppString.lastFileTS.string: lastFileTS,
          AppString.lastItemTS.string: lastItemTS,
          AppString.lastPartTS.string: lastPartTS
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
                  final itemPath = await ModelItem.getPathForItem(itemId);
                  shouldDelete = !File(itemPath).existsSync();
                }
                if (shouldDelete) {
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
              if (itemTS > lastItemTS) {
                lastItemTS = itemTS;
              }
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
              if (fileServerTS > lastFileTS) {
                lastFileTS = fileServerTS;
              }
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
              if (partServerTS > lastPartTS) {
                lastPartTS = partServerTS;
              }
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
              if (profileTS > lastProfileTS) {
                lastProfileTS = profileTS;
              }
            }
          }
        }
        await StorageSqlite.instance.applySyncPage(mutations, {
          AppString.lastFileTS.string: lastFileTS,
          AppString.lastPartTS.string: lastPartTS,
          AppString.lastItemTS.string: lastItemTS,
          AppString.lastProfileTS.string: lastProfileTS,
        });
        logger.info("Fetched Map Changes");
      } catch (e, s) {
        logger.error("fetchMapChanges", error: e, stackTrace: s);
        allFetched = false;
        changesAvailable = false;
        break;
      }
    }
    return allFetched;
  }
}
