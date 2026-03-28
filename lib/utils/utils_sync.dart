import 'dart:async';
import 'dart:convert';

import 'package:file_vault_bb/models/model_profile.dart';
import 'package:file_vault_bb/utils/utils_tasks.dart';
import '../models/model_change.dart';
import 'package:flutter/foundation.dart';
import '../services/service_backend.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../models/model_file.dart';
import '../models/model_item.dart';
import '../models/model_part.dart';
import '../models/model_state.dart';
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
        if (!canSync) {
          logger.info("Can not sync");
          return;
        }
        bool hasInternet = await InternetConnection().hasInternetAccess;
        if (!hasInternet) {
          logger.info("No internet");
          return;
        }
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
    } catch (e, s) {
      logger.error("⚠ Sync failed", error: e.toString(), stackTrace: s);
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
    bool hasInternet = await InternetConnection().hasInternetAccess;
    if (!hasInternet) return false;
    String? userId = getSignedInUserId();
    if (userId != null) {
      String deviceId = await getDeviceId();
      SecureStorage storage = SecureStorage();
      try {
        if (deviceId.isNotEmpty) {
          final api = BackendApi();
          final response = await api
              .post(endpoint: '/signout', jsonBody: {"device_id": deviceId});
          if (response["success"] == 0) {
            return false;
          }
        } else {
          return false;
        }
        if (!simulateTesting()) {
          await Supabase.instance.client.auth.signOut();
        }
        await storage.delete(key: AppString.masterKey.string);
        await storage.delete(key: AppString.accessKey.string);
        await storage.delete(key: 'selected_plan');
        final dbHelper = StorageSqlite.instance;
        await dbHelper.clearDb();
        //TODO remove all local media (FiFe folder)
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
          {"id": changeId, "data": map, "table_name": table});
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
        if (responseData["success"] == 0) break;
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
              map[AppString.textCipher.string] = changeMap["6"];
              map[AppString.textNonce.string] = changeMap["7"];
              map[AppString.keyCipher.string] = changeMap["8"];
              map[AppString.keyNonce.string] = changeMap["9"];
              Uint8List? decryptedBytes =
                  cryptoUtils.getDecryptedBytesFromMap(map, masterKeyBytes);
              if (decryptedBytes == null) continue;
              String jsonString = utf8.decode(decryptedBytes);
              Map<String, dynamic> itemMap = jsonDecode(jsonString);
              int deleteTask = int.parse(itemMap["deleted"].toString());
              if (deleteTask > 0) {
                String itemId = itemMap["id"];
                await ModelItem.deletedFromServer(itemId);
              } else {
                ModelItem newModelItem = await ModelItem.fromMap(itemMap);
                await newModelItem.upcertFromServer();
              }
              if (itemTS > lastItemTS) {
                lastItemTS = itemTS;
              }
            } else if (table == Tables.files.string) {
              String fileHash = changeMap["1"].split("_")[1];
              int fileTS = int.parse(changeMap["3"].toString());
              map["id"] = fileHash;
              map["item_count"] = int.parse(changeMap["6"].toString());
              map["parts"] = int.parse(changeMap["7"].toString());
              map["parts_uploaded"] = int.parse(changeMap["8"].toString());
              map["uploaded_at"] = int.parse(changeMap["9"].toString());
              map["provider"] = int.parse(changeMap["10"].toString());
              map["storage_id"] = changeMap["11"];
              map["data"] = changeMap["12"];
              map["updated_at"] = int.parse(changeMap["13"].toString());
              int deleteTask = int.parse(changeMap["14"].toString());
              if (deleteTask > 0) {
                await ModelFile.deletedFromServer(fileHash);
              } else {
                ModelFile newModelFile = await ModelFile.fromMap(map);
                newModelFile.upcertFromServer();
              }
              if (fileTS > lastFileTS) {
                lastFileTS = fileTS;
              }
            } else if (table == Tables.parts.string) {
              int partTS = int.parse(changeMap["3"].toString());
              List<String> userIdPartId = changeMap["1"].split("_");
              String partId = userIdPartId.skip(1).join('_');
              map["id"] = partId;
              map["size"] = int.parse(changeMap["6"].toString());
              map["cipher"] = changeMap["7"];
              map["nonce"] = changeMap["8"];
              map["data"] = changeMap["9"];
              map["uploaded_at"] = int.parse(changeMap["10"].toString());
              int deleteTask = int.parse(changeMap["11"].toString());
              if (deleteTask > 0) {
                await ModelPart.deletedFromServer(partId);
              } else {
                ModelPart newModelPart = await ModelPart.fromMap(map);
                await newModelPart.upcertFromServer();
              }
              if (partTS > lastPartTS) {
                lastPartTS = partTS;
              }
            } else if (table == Tables.profiles.string) {
              int profileTS = int.parse(changeMap["3"].toString());
              String profileId = changeMap["1"];
              map["username"] = changeMap["4"];
              map["image"] = changeMap["7"];
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
