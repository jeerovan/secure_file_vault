import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import '../models/model_change.dart';
import 'package:flutter/foundation.dart';
import '../services/service_backend.dart';
import '../services/service_events.dart';
import '../services/service_recon.dart';
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
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class SyncUtils {
  // Singleton setup
  static final SyncUtils _instance = SyncUtils._internal();
  factory SyncUtils() => _instance;
  SyncUtils._internal();

  Timer? _debounceTimer;
  Timer? _syncTimer;

  bool _isSyncing = false;
  bool _hasPendingChanges = false;

  static final logger = AppLogger(prefixes: ["Sync"]);

  void startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      syncRootFolders(inBackground: false);
    });
  }

  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }

  // Pass inBackground flag to determine if we should await everything
  Future<void> syncRootFolders({bool inBackground = false}) async {
    List<ModelItem> syncFolders = await ModelItem.getAllSyncedFolders();
    for (ModelItem syncFolder in syncFolders) {
      await ReconciliationService().reconcile(syncFolder.id);
    }

    // If in background, await directly to prevent isolate termination
    if (inBackground) {
      await triggerSync(inBackground: true);
    } else {
      waitAndSyncChanges();
    }
  }

  static void waitAndSyncChanges() {
    logger.info("wait and sync (Foreground)");
    EventStream().publish(AppEvent(
        type: EventType.syncStatus,
        id: "",
        key: EventKey.running,
        value: null));
    _instance._handleChange();
  }

  void _handleChange() {
    _hasPendingChanges = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      if (_hasPendingChanges) {
        _hasPendingChanges = false;
        triggerSync(inBackground: false); // Fire and forget for foreground
      }
    });
  }

  Future<void> triggerSync({required bool inBackground}) async {
    // Drop the request if a sync is already actively running
    if (_isSyncing) {
      logger.warning("Sync already in progress, skipping.");
      return;
    }

    try {
      _isSyncing = true;
      String mode = inBackground ? "Background" : "Foreground";
      logger.info("sync request from: $mode");

      bool canSync = await SyncUtils.canSync();
      if (!canSync) return;

      // Note: Workmanager already ensures network connectivity via constraints on Android
      bool hasInternet = await InternetConnection().hasInternetAccess;
      if (!hasInternet) return;

      await _performSyncOperations(inBackground);
    } catch (e, stack) {
      logger.error("Sync failed", error: e, stackTrace: stack);
      // If this is a background task, you might want to rethrow so Workmanager can retry
      if (inBackground) rethrow;
    } finally {
      _isSyncing = false;
      EventStream().publish(AppEvent(
          type: EventType.syncStatus,
          id: "",
          key: EventKey.stopped,
          value: null));
    }
  }

  Future<void> _performSyncOperations(bool inBackground) async {
    String mode = inBackground ? "Background" : "Foreground";
    logger.info("$mode|Sync|------------------START----------------");
    try {
      bool removed = await SyncUtils.checkDeviceStatus();
      if (!removed) {
        await fetchMapChanges(); // fetch server changes first
        await pushMapChanges(); // send items/files changes before client uploads them
        await TaskManager.init(
            inBackground: inBackground); // upload actual files
        await pushMapChanges(); // send upload changes to server
      }
    } catch (e, s) {
      logger.error("⚠ Sync failed", error: e.toString(), stackTrace: s);
    }
    logger.info("$mode|Sync|------------------ENDED----------------");
  }

  // to sync, one must have masterKey with
  static Future<bool> canSync() async {
    String? masterKey = await getMasterKey();
    bool hasKeys = masterKey != null;
    return hasKeys;
  }

  static Future<bool> checkDeviceStatus() async {
    bool removed = false;
    if (simulateTesting()) {
      return removed;
    }
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
        removed = data["active"] == 0;
      }

      if (removed) {
        // signout
        await signout();
      }
      logger.info("device Status Checked");
    } catch (e, s) {
      logger.error("checkDeviceStatus", error: e, stackTrace: s);
    }
    return removed;
  }

  static Future<bool> signout() async {
    bool success = false;
    bool hasInternet = await InternetConnection().hasInternetAccess;
    if (!hasInternet) return false;
    String? userId = getSignedInUserId();
    if (userId != null) {
      String deviceUuid = await getDeviceUuid();
      SecureStorage storage = SecureStorage();
      try {
        if (!simulateTesting()) {
          if (deviceUuid.isNotEmpty) {
            final api = BackendApi();
            final response = await api.post(
                endpoint: '/signout', jsonBody: {"device_uuid": deviceUuid});
            if (response["success"] == 0) {
              return false;
            }
          } else {
            return false;
          }
          await Supabase.instance.client.auth.signOut();
        }
        await storage.delete(key: AppString.masterKey.string);
        await storage.delete(key: AppString.accessKey.string);
        final dbHelper = StorageSqlite.instance;
        await dbHelper.clearDb();
        //TODO remove all local media (FiFe folder)

        success = true;
      } on FunctionException catch (e) {
        Map<String, dynamic> errorMap =
            e.details is String ? jsonDecode(e.details) : e.details;
        dynamic error = errorMap.containsKey("error") ? errorMap["error"] : "";
        logger.error("signout", error: error);
      } catch (e, s) {
        logger.error("signout", error: e, stackTrace: s);
      }
    }
    return success;
  }

  static Future<void> logChangeToPush(Map<String, dynamic> map,
      {int deleteTask = 0}) async {
    String? masterKeyBase64 = await getMasterKey();
    String? userId = getSignedInUserId();
    if (masterKeyBase64 != null && userId != null) {
      String table = map["table"];
      String rowId = map['id'];
      String changeId = '$table|$rowId';
      map["deleted"] = deleteTask;

      ModelChange change = await ModelChange.fromMap(
          {"id": changeId, "data": map, "table_name": table});
      await change.insert();
      logger.info("encryptAndPushChange:$table|$changeId");
    }
  }

  static Future<void> pushMapChanges() async {
    logger.info("Push Map Changes");
    String? masterKeyBase64 = await getMasterKey();
    if (masterKeyBase64 == null || simulateTesting()) return;
    final api = BackendApi();
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
          logger.info("Pushed Map Changes");
        } else {
          changesAvailable = false;
        }
      }
    }
  }

  static Future<void> fetchMapChanges() async {
    String? masterKeyBase64 = await getMasterKey();
    if (await canSync() == false ||
        masterKeyBase64 == null ||
        simulateTesting()) {
      return;
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
        if (responseData["success"] <= 0) break;
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
              if (decryptedBytes == null) continue;
              String jsonString = utf8.decode(decryptedBytes);
              Map<String, dynamic> itemMap = jsonDecode(jsonString);
              int deleteTask = int.parse(itemMap["deleted"].toString());
              if (deleteTask > 0) {
                String itemId = itemMap["id"];
                await ModelItem.deletedFromServer(itemId, clientTS);
              } else {
                ModelItem newModelItem = await ModelItem.fromMap(itemMap);
                await newModelItem.upcertFromServer();
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
                await ModelFile.deletedFromServer(fileHash, clientTS);
              } else {
                newModelFile.upcertFromServer();
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
                await ModelPart.deletedFromServer(partId, clientTS);
              } else {
                await newModelPart.upcertFromServer();
              }
              if (partServerTS > lastPartTS) {
                lastPartTS = partServerTS;
              }
            } else if (table == Tables.profiles.string) {
              int profileTS = int.parse(changeMap["3"].toString());
              String profileId = changeMap["4"];
              map["username"] = changeMap["5"];
              map["image"] = changeMap["8"];
              await ModelProfile.upcertFromServer(profileId, map);
              if (profileTS > lastProfileTS) {
                lastProfileTS = profileTS;
              }
            }
          }
        }
        // update last TSs
        await ModelState.set(
            AppString.lastFileTS.string, lastFileTS.toString());
        await ModelState.set(
            AppString.lastPartTS.string, lastPartTS.toString());
        await ModelState.set(
            AppString.lastItemTS.string, lastItemTS.toString());
        await ModelState.set(
            AppString.lastProfileTS.string, lastProfileTS.toString());
        logger.info("Fetched Map Changes");
      } catch (e, s) {
        logger.error("fetchMapChanges", error: e, stackTrace: s);
      }
    }
  }
}
