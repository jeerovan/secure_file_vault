import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/utils/utils_tasks.dart';
import '../models/model_change.dart';
import '../models/model_profile.dart';
import 'package:flutter/foundation.dart';
import '../services/service_backend.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../models/model_file.dart';
import '../models/model_item.dart';
import '../models/model_part.dart';
import '../models/model_state.dart';
import '../models/model_setting.dart';
import '../services/service_events.dart';
import '../services/service_logger.dart';
import '../storage/storage_secure.dart';
import '../utils/utils_crypto.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:synchronized/synchronized.dart';

class SyncUtils {
  // Singleton setup
  static final SyncUtils _instance = SyncUtils._internal();
  factory SyncUtils() => _instance;
  SyncUtils._internal();

  Timer? _debounceTimer;
  Timer? _processTimer;

  bool _isSyncing = false;
  bool _hasPendingChanges = false;

  // Use a Lock for concurrency safety
  final Lock _lock = Lock();

  static final logger = AppLogger(prefixes: [
    "Sync",
  ]);
  static final String processRunningAt = "sync_running_at";

  // Static method to trigger change detection
  static void waitAndSyncChanges(
      {bool inBackground = false,
      bool manualSync = false,
      bool firstFetch = false}) {
    logger.info("wait and sync");
    _instance._handleChange(inBackground,
        manualSync: manualSync, firstFetch: firstFetch);
  }

  void _handleChange(bool inBackground,
      {bool manualSync = false, bool firstFetch = false}) {
    _hasPendingChanges = true;
    _debounceTimer?.cancel(); // Cancel any ongoing debounce
    _debounceTimer = Timer(Duration(seconds: 2), () {
      if (_hasPendingChanges) {
        _hasPendingChanges = false;
        triggerSync(inBackground,
            manualSync: manualSync, firstFetch: firstFetch);
      }
    });
  }

  Future<void> triggerSync(bool inBackground,
      {bool manualSync = false, bool firstFetch = false}) async {
    await _lock.synchronized(() async {
      if (_isSyncing) {
        logger.warning("Sync already in progress, skipping.");
        return;
      }
      try {
        _isSyncing = true;

        String mode = inBackground ? "Background" : "Foreground";
        logger.info("sync request from:$mode");
        bool canSync = await SyncUtils.canSync();
        if (!canSync) return;
        bool hasInternet = await InternetConnection().hasInternetAccess;
        if (!hasInternet) return;
        await _performSyncOperations(inBackground, manualSync, firstFetch);
      } catch (e, stack) {
        logger.error("Sync failed", error: e, stackTrace: stack);
      } finally {
        // Always release the flag, even if code crashes
        _isSyncing = false;
      }
    });
  }

  Future<void> _performSyncOperations(
      bool inBackground, bool manualSync, bool firstFetch) async {
    String mode = inBackground ? "Background" : "Foreground";
    logger.info("$mode|Sync|------------------START----------------");
    try {
      bool removed = await SyncUtils.checkDeviceStatus();
      if (!removed) {
        await fetchMapChanges();
        await pushMapChanges();
        TaskManager.init(inBackground: inBackground);
      }
    } catch (e) {
      logger.error("⚠ Sync failed: $e");
    }
    _processTimer?.cancel();
    _processTimer = null;
    if (manualSync) {
      // Send Signal to update home
      await signalToUpdateHome();
    }
    if (firstFetch) {
      // Send Signal to update home
      await signalToUpdateHome();
      EventStream().publish(AppEvent(type: EventType.serverFirstFetchEnds));
    }
    logger.info("$mode|Sync|------------------ENDED----------------");
  }

  // to sync, one must have masterKey with an active plan
  static Future<bool> canSync() async {
    // TODO check for plan also
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
      final response = await api.get(endpoint: '/devices');
      final status = response["status"];
      if (status == -1) {
        logger.error("checkDeviceStatus", error: response["error"]);
      } else if (status == 1) {
        final data = response["data"];
        removed = data["active"] == 0;
      }

      if (removed) {
        // signout
        await signout();
        // Send Signal to update home
        await signalToUpdateHome();
      }
      logger.info("device Status Checked");
    } catch (e, s) {
      logger.error("checkDeviceStatus", error: e, stackTrace: s);
    }
    return removed;
  }

  static Future<bool> signout() async {
    bool success = false;
    String? userId = getSignedInUserId();
    if (userId != null) {
      String? deviceId = await ModelState.get(AppString.deviceId.string);
      SecureStorage storage = SecureStorage();
      SupabaseClient supabase = Supabase.instance.client;
      try {
        if (simulateTesting()) {
          null;
        } else {
          if (deviceId != null) {
            // remove device from server
          }
          await supabase.auth.signOut();
        }
        await ModelItem.removeAllSyncedFolders();
        //TODO remove all local media (FiFe folder)
        await storage.delete(key: AppString.masterKey.string);
        await storage.delete(key: AppString.accessKey.string);
        await ModelState.delete(AppString.planRcId.string);
        await ModelState.delete(AppString.hasValidPlan.string);
        await ModelState.delete(AppString.deviceId.string);
        await ModelState.delete(AppString.deviceRegistered.string);
        await ModelState.delete(AppString.hasEncryptionKeys.string);
        await ModelState.delete(AppString.debugCipherData.string);
        await ModelState.delete(AppString.encryptionKeyType.string);
        await ModelState.delete(AppString.pushedLocalContentForSync.string);
        await ModelState.delete(AppString.lastChangesFetchedAt.string);
        await ModelState.delete(AppString.lastProfilesChangesFetchedAt.string);
        await ModelState.delete(AppString.lastFilesChangesFetchedAt.string);
        await ModelState.delete(AppString.lastItemsChangesFetchedAt.string);
        await ModelState.delete(AppString.lastPartsChangesFetchedAt.string);
        await ModelState.delete(AppString.dataSeeded.string);
        await ModelSetting.set(AppString.signedIn.string, "no");
        await ModelSetting.set(AppString.simulateTesting.string, "no");
        // Send Signal to update home
        await signalToUpdateHome();
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
          {"id": changeId, "data": map, "table": table});
      await change.insert();
      logger.info("encryptAndPushChange:$table|$changeId");
      waitAndSyncChanges();
    }
  }

  static Future<void> pushMapChanges() async {
    logger.info("Push Map Changes");
    final api = BackendApi();
    bool changesAvailable = true;
    String? masterKeyBase64 = await getMasterKey();
    if (masterKeyBase64 == null) return;
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
        if (response["status"] == 1) {
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
    if (await canSync() == false || masterKeyBase64 == null) return;
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
      int lastProfilesFetchedAt = await ModelState.get(
          AppString.lastProfilesChangesFetchedAt.string,
          defaultValue: 0);
      int lastItemsFetchedAt = await ModelState.get(
          AppString.lastItemsChangesFetchedAt.string,
          defaultValue: 0);
      int lastFilesFetchedAt = await ModelState.get(
          AppString.lastFilesChangesFetchedAt.string,
          defaultValue: 0);
      int lastPartsFetchedAt = await ModelState.get(
          AppString.lastPartsChangesFetchedAt.string,
          defaultValue: 0);
      try {
        // fetch clubbed changes
        Map<String, dynamic> requestData = {
          AppString.lastProfilesChangesFetchedAt.string: lastProfilesFetchedAt,
          AppString.lastFilesChangesFetchedAt.string: lastFilesFetchedAt,
          AppString.lastItemsChangesFetchedAt.string: lastItemsFetchedAt,
          AppString.lastPartsChangesFetchedAt.string: lastPartsFetchedAt
        };
        final responseData =
            await api.get(endpoint: '/sync', queryParameters: requestData);
        if (responseData["status"] == 0) break;
        Map<String, dynamic> tableChanges = responseData["data"];
        for (String table in tables) {
          if (!tableChanges.containsKey(table)) continue;
          List<dynamic> changesMap = tableChanges[table];
          if (changesMap.isEmpty) {
            continue;
          }
          changesAvailable = true;
          for (Map<String, dynamic> changeMap in changesMap) {
            Map<String, dynamic> map = changeMap;
            if (table == Tables.items.string) {
              Uint8List? decryptedBytes = cryptoUtils.getDecryptedBytesFromMap(
                  changeMap, masterKeyBytes);
              if (decryptedBytes == null) continue;
              String jsonString = utf8.decode(decryptedBytes);
              map = jsonDecode(jsonString);
            }
            //TODO handle changeId/rowId
            //String changeId = changeMap["id"];
            String rowId = map["id"];
            int deleteTask = int.parse(map.remove("deleted").toString());
            if (deleteTask > 0) {
              if (table == Tables.files.string) {
                await ModelFile.deletedFromServer(rowId);
              } else if (table == Tables.items.string) {
                await ModelItem.deletedFromServer(rowId);
              }
            } else {
              if (table == Tables.profiles.string) {
                ModelProfile newProfile = await ModelProfile.fromMap(map);
                await newProfile.upcertFromServer();
              } else if (table == Tables.files.string) {
                ModelFile newFile = await ModelFile.fromMap(map);
                await newFile.upcertFromServer();
              } else if (table == Tables.parts.string) {
                ModelPart newPart = await ModelPart.fromMap(map);
                await newPart.upcertFromServer();
              } else if (table == Tables.items.string) {
                ModelItem item = await ModelItem.fromMap(map);
                await item.upcertFromServer();
              }
            }
          }
        }
        // update last fetched at iso time
        if (changesAvailable) {
          String fetchedAt =
              tableChanges[AppString.lastChangesFetchedAt.string];
          await ModelState.set(
              AppString.lastChangesFetchedAt.string, fetchedAt);
        }
        logger.info("Fetched Map Changes");
      } catch (e, s) {
        logger.error("fetchMapChanges", error: e, stackTrace: s);
      }
    }
  }

/* 
  static Future<void> fetchFiles(int startedAt, bool inBackground) async {
    List<ModelChange> changes = await ModelChange.requiresFileFetch();
    if (changes.isEmpty) return;
    SodiumSumo sodium = await SodiumSumoInit.init();
    CryptoUtils cryptoUtils = CryptoUtils(sodium);

    for (ModelChange change in changes) {
      String changeId = change.id;
      List<String> tableRowId = changeId.split("|");
      String itemRowId = tableRowId[1];
      ModelItem? modelItem = await ModelItem.get(itemRowId);
      if (modelItem == null) {
        logger.debug("Item deleted already, not fetching: $changeId");
        await ModelChange.upgradeChangeTask(change);
        continue;
      }
      ModelFile? modelFile = await ModelFile.get(modelItem.fileId!);
      Map<String, dynamic>? data = change.data;
      if (modelFile != null) {
        String fileName = modelItem.name;
        String filePath = await ModelItem.getPathForItem(modelItem.id);
        File fileOut = File(filePath);
        if (fileOut.existsSync()) {
          // duplicate item
          logger.debug(
              "to be fetched file already exist, may be another group:$changeId");
          await ModelChange.upgradeChangeTask(change);
        } else {
          Map<String, dynamic> serverData =
              await getDataToDownloadFile(fileName);
          // check when its available to download
          if (serverData.containsKey("url") && serverData["url"].isNotEmpty) {
            int fileSize = data["size"];
            if (fileSize > 20 * 1024 * 1024) {
              // mark set downloadable
              logger.debug("Marking downloadable:$changeId");
              await ModelChange.updateTypeState(
                  changeId, SyncState.downloadable);
              await ModelChange.upgradeChangeTask(change, updateState: false);
            } else {
              // download & decrypt
              bool downloadedDecrypted =
                  await cryptoUtils.downloadDecryptFile(data);
              if (downloadedDecrypted) {
                await ModelChange.upgradeChangeTask(change);
              }
            }
          } else {
            logger.debug("not available to be fetched yet:$changeId");
          }
        }
      }
    }
    logger.info("Files fetched");
  }
 */
  static Future<Map<String, dynamic>> getDataToDownloadFile(
      String fileName) async {
    SupabaseClient supabase = Supabase.instance.client;
    Map<String, dynamic> downloadData = {};
    try {
      final res = await supabase.functions
          .invoke('get_download_url', body: {'fileName': fileName});
      Map<String, dynamic> data = jsonDecode(res.data);
      downloadData.addAll(data);
    } on FunctionException catch (e) {
      downloadData["error"] = e.details.toString();
    } catch (e) {
      downloadData["error"] = e.toString();
    }
    return downloadData;
  }
}
