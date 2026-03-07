import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
import '../services/service_notification.dart';
import '../storage/storage_secure.dart';
import '../utils/utils_crypto.dart';
import '../utils/utils_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path/path.dart' as path_lib;
import 'package:http/http.dart' as http_lib;
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
    int startedAt = DateTime.now().millisecondsSinceEpoch;
    bool hasPendingUploads = false;
    bool hasMoreMapChangesToPush = false;
    try {
      bool removed = await SyncUtils.checkDeviceStatus();
      if (!removed) {
        await fetchMapChanges();
        await cleanupFiles();
        await pushMapChanges();
        // pushing files is a time consuming task
        hasPendingUploads = await pushFiles(startedAt, inBackground);
        // large files over 20 mb should not be fetched automatically
        await fetchFiles(startedAt, inBackground);
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
    if (!inBackground && (hasPendingUploads || hasMoreMapChangesToPush)) {
      logger.info("$mode|Sync| more tasks.. will continue..");
      _handleChange(inBackground, manualSync: manualSync);
    }
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
      int updatedAt = map['updated_at'];
      map["deleted"] = deleteTask;

      Map<String, dynamic> changeMap = {};
      if (table == Tables.items.string) {
        changeMap.addAll({
          "id": rowId,
          "updated_at": updatedAt,
        });
        SodiumSumo sodium = await SodiumSumoInit.init();
        CryptoUtils cryptoUtils = CryptoUtils(sodium);

        String jsonString = jsonEncode(map);
        Uint8List plainBytes = Uint8List.fromList(utf8.encode(jsonString));

        Uint8List masterKeyBytes = base64Decode(masterKeyBase64);
        Map<String, dynamic> encryptedDataMap =
            cryptoUtils.getEncryptedBytesMap(plainBytes, masterKeyBytes);
        changeMap.addAll(encryptedDataMap);
      } else {
        changeMap.addAll(map);
      }

      String changeData = jsonEncode(changeMap);

      SyncChangeTask changeTask = SyncChangeTask.pushMap;
      if (deleteTask == 0) {
        changeTask = ModelChange.getPushChangeTaskType(table, map);
      } else {
        changeTask = SyncChangeTask.pushMapDeleteFile;
        // delete file pending for upload if exist
        //TODO handle file being uploaded
      }
      // add/update change if any upload/download exist
      await ModelChange.addUpdate(
          changeId, table, changeData, changeTask.value);
      logger.info("encryptAndPushChange:$table|$changeId|${changeTask.value}");
      await ModelChange.updateTypeState(changeId, SyncState.uploading);
      waitAndSyncChanges();
    }
  }

  static Future<void> pushMapChanges() async {
    logger.info("Push Map Changes");
    final api = BackendApi();
    bool changesAvailable = true;
    while (changesAvailable) {
      changesAvailable = false;
      List<Map<String, dynamic>> tableMaps = [];
      List<ModelChange> tableChanges = [];
      for (String table in [
        Tables.files.string,
        Tables.items.string,
        Tables.parts.string
      ]) {
        List<ModelChange> changes =
            await ModelChange.fetch300MapPushForTable(table);
        List<Map<String, dynamic>> changeMaps = [];
        for (ModelChange change in changes) {
          changeMaps.add(change.changedData);
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
          await ModelChange.updateChangeState(tableChanges);
          logger.info("Pushed Map Changes");
        } else {
          changesAvailable = false;
        }
      }
    }
  }

  static Future<void> cleanupFiles() async {
    logger.info("Delete Files");
    List<ModelChange> changes = await ModelChange.requiresFileDelete();
    if (changes.isEmpty) return;
    SupabaseClient supabaseClient = Supabase.instance.client;
    for (ModelChange change in changes) {
      await deleteFile(change, supabaseClient);
    }
  }

  static Future<void> deleteFile(
      ModelChange change, SupabaseClient supabaseClient) async {
    Map<String, dynamic>? map = change.changedData;
    //TODO fix getting file to delete
    if (map != null && map.containsKey("name") && map["name"].isNotEmpty) {
      String fileName = map["name"];
      try {
        await supabaseClient.functions
            .invoke("delete_file", body: {"fileName": fileName});
        await ModelChange.upgradeChangeTask(change);
      } catch (e, s) {
        logger.error("deleteFile", error: e, stackTrace: s);
      }
    } else {
      await ModelChange.upgradeChangeTask(change);
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
            String changeId = changeMap["id"];
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
              SyncChangeTask changeType = SyncChangeTask.delete;
              if (table == Tables.files.string) {
                changeType = SyncChangeTask.fetchFile;
              }
              if (changeType.value > SyncChangeTask.delete.value) {
                await ModelChange.addUpdate(
                    changeId, table, "", changeType.value);
                logger.info(
                    "fetchChangesForTable|$table|Added change:$table|$changeId|${changeType.value}");
                await ModelChange.updateTypeState(
                    changeId, SyncState.downloading);
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
        await ModelState.set(AppString.hasValidPlan.string, "yes");
        logger.info("Fetched Map Changes");
      } catch (e, s) {
        logger.error("fetchMapChanges", error: e, stackTrace: s);
      }
    }
  }

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
      Map<String, dynamic>? data = change.changedData;
      if (modelFile != null) {
        String fileName = modelItem.name;
        String filePath = await ModelItem.getPathForItem(modelItem.id);
        File fileOut = File(filePath);
        if (fileOut.existsSync()) {
          // duplicate note item (may be different groups)
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

  static Future<bool> pushFiles(int startedAt, bool inBackground) async {
    logger.info("Push Files");
    bool hasPendingUploads = false;
    if (simulateTesting()) return hasPendingUploads;
    SupabaseClient supabaseClient = Supabase.instance.client;
    // push uploaded files state to supabase if left due to network failures
    // where uploadedAt > 0 but still exists,
    List<ModelFile> completedUploads = await ModelFile.pendingForPush();
    for (ModelFile completedUpload in completedUploads) {
      String fileId = completedUpload.id;
      try {
        // update if the the current uploadedAt on server is earlier than this uploadedAt
        logger.info("pushFiles|$fileId|syncing completed upload");
        await supabaseClient
            .from("files")
            .update({
              "uploaded_at": completedUpload.uploadedAt,
              "parts_uploaded": completedUpload.partsUploaded,
              "b2_id": completedUpload.remoteId,
            })
            .eq("id", fileId)
            .lt("uploaded_at", completedUpload.uploadedAt);

        String changeId = ""; // TODO get changeId
        ModelChange? change = await ModelChange.get(changeId);
        await completedUpload
            .delete(); // deletes the encrypted file in temp dir
        // upgrade changetask
        await ModelChange.upgradeChangeTask(change!);
      } catch (e, s) {
        logger.error("pushFiles", error: e, stackTrace: s);
      }
    }
    logger.info(
        "pushed Completed Uploads. Spent: ${DateTime.now().toUtc().millisecondsSinceEpoch - startedAt}");
    //uploading partial pending files
    // where uploadedAt = 0
    List<ModelFile> pendingUploads = []; // TODO get files pending for upload
    for (ModelFile pendingFile in pendingUploads) {
      await pushFile(pendingFile);
      hasPendingUploads = true;
    }
    logger.info(
        "pushed Pending Uploads. Spent: ${DateTime.now().toUtc().millisecondsSinceEpoch - startedAt}");
    // upload pending files
    List<ModelChange> changes = await ModelChange.requiresFilePush();
    for (ModelChange change in changes) {
      await checkPushFile(change);
      hasPendingUploads = true;
    }
    logger.info(
        "Created New Uploads. Spent: ${DateTime.now().toUtc().millisecondsSinceEpoch - startedAt}");
    return hasPendingUploads;
  }

  static Future<void> checkPushFile(ModelChange change) async {
    SupabaseClient supabaseClient = Supabase.instance.client;
    Map<String, dynamic>? dataMap = change.changedData;
    if (dataMap != null) {
      List<String> userIdRowId = change.id.split("|");
      String userId = userIdRowId[0];
      String? fileIn = getValueFromMap(dataMap, "path", defaultValue: null);
      if (fileIn != null) {
        String fileName = path_lib.basename(fileIn);
        String fileId = '$userId|$fileName';
        ModelFile? existingModelFile = await ModelFile.get(fileId);
        if (existingModelFile != null) {
          logger.info("checkPushFile|modelFile exists");
          return;
        }
        // check server if already uploaded (from another device)
        try {
          final serverFiles =
              await supabaseClient.from("files").select().eq("id", fileId);
          if (serverFiles.isNotEmpty) {
            // entry exist
            Map<String, dynamic> serverFile = serverFiles.first;
            int uploadedAt = serverFile["uploaded_at"];
            if (uploadedAt == 0) {
              // not uploaded
              // create new entry with server data
              serverFile["change_id"] = change.id;
              serverFile["path"] = fileIn;
              ModelFile modelFile = await ModelFile.fromMap(serverFile);
              await modelFile.insert();
              // push file
              await pushFile(modelFile);
            } else {
              // upgrade changetask
              await ModelChange.upgradeChangeTask(change);
            }
          } else {
            // encrypt file, get keys, update server before updating local
            Directory tempDir = await getTemporaryDirectory();
            String fileOut = path_lib.join(tempDir.path, "$fileName.crypt");
            SodiumSumo sodium = await SodiumSumoInit.init();
            CryptoUtils cryptoUtils = CryptoUtils(sodium);
            ExecutionResult fileEncryptionResult =
                await cryptoUtils.encryptFile(fileIn, fileOut);
            if (fileEncryptionResult.isSuccess) {
              // may fail due to low storage
              String encryptionKeyBase64 =
                  fileEncryptionResult.getResult()!["key"];
              Uint8List encryptionKeyBytes = base64Decode(encryptionKeyBase64);
              String? masterKeyBase64 = await getMasterKey();
              Uint8List masterKeyBytes = base64Decode(masterKeyBase64!);
              Map<String, dynamic> encryptionKeyCipher =
                  cryptoUtils.getFileEncryptionKeyCipher(
                      encryptionKeyBytes, masterKeyBytes);
              File encryptedFile = File(fileOut);
              int fileSize = encryptedFile.lengthSync();
              FileSplitter fileSplitter = FileSplitter(encryptedFile);
              int parts = fileSplitter.partSizes.length;
              String keyNonceBase64 =
                  encryptionKeyCipher[AppString.keyNonce.string];
              Map<String, dynamic> fileData = {
                "id": fileId,
                "file_name": fileName,
                AppString.keyCipher.string:
                    encryptionKeyCipher[AppString.keyCipher.string],
                AppString.keyNonce.string: keyNonceBase64,
                "parts": parts,
                "size": fileSize,
              };
              final res = await supabaseClient.functions
                  .invoke('start_parts_upload', body: fileData);
              Map<String, dynamic> resData = jsonDecode(res.data);
              if (resData["file"][AppString.keyNonce.string] !=
                  keyNonceBase64) {
                File tempFile = File(fileOut);
                if (tempFile.existsSync()) tempFile.delete();
              }
              fileData[AppString.keyCipher.string] =
                  resData["file"][AppString.keyCipher.string];
              fileData[AppString.keyNonce.string] =
                  resData["file"][AppString.keyNonce.string];
              fileData["parts"] = resData["file"]["parts"];
              fileData["size"] = resData["file"]["size"];
              fileData["b2_id"] = resData["file"]["b2_id"];
              // if above succeeds, create local entry
              fileData["change_id"] = change.id;
              fileData["path"] = fileIn;
              ModelFile modelFile = await ModelFile.fromMap(fileData);
              await modelFile.insert();
              // start actual upload
              await pushFile(modelFile);
            } else if (fileEncryptionResult.failureReason!
                .contains("PathNotFoundException")) {
              change.deleteWithItem();
            }
          }
        } catch (e, s) {
          logger.error("PushFile", error: e, stackTrace: s);
        }
      } else {
        logger.error("checkPushFile|fileIn is null");
      }
    } else {
      logger.error("checkPushFile|dataMap is null");
    }
  }

  static Future<void> pushFile(ModelFile modelFile) async {
    SupabaseClient supabaseClient = Supabase.instance.client;
    List<String> userIdFileName = modelFile.id.split("|");
    String fileName = userIdFileName[1];
    try {
      logger.info("pushFile|checking server entry for: $fileName");
      final serverFiles =
          await supabaseClient.from("files").select().eq("id", modelFile.id);
      if (serverFiles.isNotEmpty) {
        // entry exist
        logger.info("pushFile|$fileName exist on server");
        Map<String, dynamic> serverFile = serverFiles.first;
        int uploadedAt = serverFile["uploaded_at"];
        if (uploadedAt == 0) {
          logger.info("pushFile| $fileName not uploaded");
          // check and update in case of parts_uploaded mismatch
          int serverPartsUploaded = serverFile["parts_uploaded"];
          if (serverPartsUploaded != modelFile.partsUploaded) {
            logger.info("pushFile|$fileName| partsUploaded mismatch");
            if (modelFile.partsUploaded > serverPartsUploaded) {
              // update server only when partsUploaded are less
              logger.info("pushFile|$fileName|update partsUploaded on server");
              try {
                await supabaseClient
                    .from("files")
                    .update({"parts_uploaded": modelFile.partsUploaded})
                    .eq("id", modelFile.id)
                    .lt("parts_uploaded", modelFile.partsUploaded);
              } catch (e, s) {
                logger.error("pushFile", error: e, stackTrace: s);
              }
            } else if (modelFile.partsUploaded < serverPartsUploaded) {
              // being uploaded from another device
              // update local
              logger.info("pushFile|$fileName|update partsUploaded locally");
              modelFile.partsUploaded = serverPartsUploaded;
              await modelFile.update(["parts_uploaded"]);
            }
          }
          // check update b2_id (should never be inconsistent)
          if (serverFile["b2_id"] != null && modelFile.remoteId == null) {
            logger.info("pushFile|$fileName|updating b2id locally from server");
            modelFile.remoteId = serverFile["b2_id"];
            await modelFile.update(["b2_id"]);
          } else if (serverFile["b2_id"] == null &&
              modelFile.remoteId != null) {
            logger.info("pushFile|$fileName|update b2id on server");
            try {
              await supabaseClient
                  .from("files")
                  .update({"b2_id": modelFile.remoteId})
                  .eq("id", modelFile.id)
                  .isFilter("b2_id", null);
            } catch (e, s) {
              logger.error("pushFile", error: e, stackTrace: s);
            }
          }
          if (modelFile.parts > modelFile.partsUploaded) {
            logger.info("pushFile|$fileName|Not all parts uploaded");
            await pushFilePart(modelFile);
          } else {
            // all parts uploaded
            logger.info("pushFile|$fileName|all parts uploaded");
            if (modelFile.parts > 1) {
              // finish multi-part upload
              logger.info("pushFile|$fileName|finish parts upload");
              List<String> partSha1Array =
                  await ModelPart.shasForFileId(modelFile.id);
              final res = await supabaseClient.functions
                  .invoke('finish_parts_upload', body: {
                'fileId': modelFile.id,
                "partSha1Array": partSha1Array
              }); // will set uploaded_at on server
              logger.info("FinishPartsUpload:${res.data}");
              // uploaded_at should be synced locally from server
            } // single file upload will have uploaded_at > 0 when parts == partsUploaded
          }
        } else {
          String changeId = ""; // TODO get changeid
          ModelChange? change = await ModelChange.get(changeId);
          await ModelChange.upgradeChangeTask(change!);
        }
      }
    } catch (e, s) {
      logger.error("pushFile", error: e, stackTrace: s);
    }
  }

  static Future<void> pushFilePart(ModelFile modelFile) async {
    SodiumSumo sodium = await SodiumSumoInit.init();
    CryptoUtils cryptoUtils = CryptoUtils(sodium);
    List<String> userIdFileName = modelFile.id.split("|");
    String userId = userIdFileName[0];
    String fileName = userIdFileName[1];
    logger.info("pushFilePart|$fileName|get bytes to upload");
    // TODO get file part
    String filePath = "";
    String keyCipher = "";
    String keyNonce = "";
    File? fileOut = await getCreateEncryptedFileToUpload(
        filePath, keyCipher, keyNonce, cryptoUtils);
    if (fileOut == null) {
      logger.error("pushFilePart:error creating encrypted file");
    } else {
      int partNumber = modelFile.partsUploaded + 1;
      FileSplitter fileSplitter = FileSplitter(fileOut);
      Uint8List? fileBytes = await fileSplitter.getPart(partNumber);
      if (fileBytes != null) {
        SupabaseClient supabaseClient = Supabase.instance.client;
        int fileSize = fileBytes.length;
        String sha1Hash = sha1.convert(fileBytes).toString();
        String uploadUrl = "";
        Map<String, String> headers = {};
        try {
          logger.info("pushFilePart|$fileName|get upload part url");
          if (modelFile.parts > 1) {
            final res = await supabaseClient.functions.invoke(
                'get_upload_part_url',
                body: {'fileId': modelFile.remoteId});
            Map<String, dynamic> data = jsonDecode(res.data);
            uploadUrl = data["url"];
            String uploadToken = data["token"];
            headers = {
              "authorization": uploadToken,
              "X-Bz-Part-Number": partNumber.toString(),
              "X-Bz-Content-Sha1": sha1Hash,
              "Content-Length": fileSize.toString(),
            };
            // save sha
            // ModelPart filePart = ModelPart(
            //     id: sha1Hash, fileId: modelFile.id, partNumber: partNumber);
            // await filePart.insert();
          } else {
            logger.info("pushFilePart|$fileName|get upload url");
            final res = await supabaseClient.functions
                .invoke('get_upload_url', body: {'fileSize': fileSize});
            Map<String, dynamic> data = jsonDecode(res.data);
            uploadUrl = data["url"];
            String uploadToken = data["token"];
            headers = {
              "authorization": uploadToken,
              "X-Bz-Content-Sha1": sha1Hash,
              "X-Bz-File-Name": '$userId%2F$fileName',
              "Content-Length": fileSize.toString(),
              "Content-Type": "application/octet-stream",
            };
          }
          if (uploadUrl.isNotEmpty) {
            logger.info(
                "pushFilePart|$fileName|$partNumber| uploading bytes to upload url with headers");
            Map<String, dynamic> uploadResult = await SyncUtils.uploadFileBytes(
                bytes: fileBytes, url: uploadUrl, headers: headers);
            logger.info("UploadedBytes:${jsonEncode(uploadResult)}");
            // update parts_uploaded
            if (uploadResult["error"].isEmpty) {
              logger.info("pushFilePart|$fileName|$partNumber| bytes uploaded");
              String b2Id = uploadResult["fileId"];
              //update local first
              modelFile.partsUploaded = partNumber;
              List<String> attrs = ["parts_uploaded"];
              if (modelFile.remoteId == null && b2Id.isNotEmpty) {
                modelFile.remoteId = b2Id;
                attrs.add("b2_id");
              }
              await modelFile.update(attrs);
              if (modelFile.parts == modelFile.partsUploaded) {
                logger.info("pushFilePart|$fileName|all parts uploaded");
                if (modelFile.parts > 1) {
                  // multi parts
                  // call finish parts upload
                  logger.info("pushFilePart|$fileName|finish multi part");
                  List<String> partSha1Array =
                      await ModelPart.shasForFileId(modelFile.id);
                  await supabaseClient.functions.invoke('finish_parts_upload',
                      body: {
                        'fileId': modelFile.id,
                        "partSha1Array": partSha1Array
                      });
                } else {
                  // single part
                  modelFile.uploadedAt =
                      DateTime.now().toUtc().millisecondsSinceEpoch;
                  await modelFile.update(["uploaded_at"]);
                }
              }
            } else {
              logger.error("pushFilePart|uploadBytes",
                  error: jsonEncode(uploadResult));
            }
          }
        } catch (e, s) {
          logger.error("pushFilePart", error: e, stackTrace: s);
        }
      }
    }
  }

  static Future<File?> getCreateEncryptedFileToUpload(
      String fileInPath,
      String keyCipherBase64,
      String keyNonceBase64,
      CryptoUtils cryptoUtils) async {
    Directory tempDir = await getTemporaryDirectory();
    String fileName = path_lib.basename(fileInPath);
    String fileOutPath = path_lib.join(tempDir.path, '$fileName.crypt');
    File fileOut = File(fileOutPath);
    File fileIn = File(fileInPath);
    if (!fileOut.existsSync()) {
      if (fileIn.existsSync()) {
        String? masterKeyBase64 = await getMasterKey();
        Uint8List masterKeyBytes = base64Decode(masterKeyBase64!);
        Uint8List keyNonceBytes = base64Decode(keyNonceBase64);
        Uint8List keyCipherBytes = base64Decode(keyCipherBase64);
        ExecutionResult keyDecryptionResult = cryptoUtils.decryptBytes(
            cipherBytes: keyCipherBytes,
            nonce: keyNonceBytes,
            key: masterKeyBytes);
        Uint8List fileEncryptionKey =
            keyDecryptionResult.getResult()![AppString.decrypted.string];
        ExecutionResult fileEncryptionResult = await cryptoUtils
            .encryptFile(fileInPath, fileOutPath, key: fileEncryptionKey);
        if (fileEncryptionResult.isSuccess) {
          return fileOut;
        } else {
          return null;
        }
      } else {
        return null;
      }
    } else {
      return fileOut;
    }
  }

  static Future<Map<String, dynamic>> uploadFileBytes({
    required Uint8List bytes,
    required String url,
    required Map<String, String> headers,
  }) async {
    Map<String, dynamic> data = {"error": ""};
    try {
      // Create multipart request
      var request = http_lib.Request('POST', Uri.parse(url));

      // Add headers
      request.headers.addAll(headers);

      request.bodyBytes = bytes;

      // Send request and get response
      var streamedResponse = await request.send();
      var response = await http_lib.Response.fromStream(streamedResponse);

      // Check response
      if (response.statusCode == 200) {
        data.addAll(jsonDecode(response.body));
      } else if (response.statusCode == 400) {
        data["error"] = 'Upload:${response.statusCode.toString()}';
        data.addAll(jsonDecode(response.body));
      } else {
        data["error"] = 'Upload:${response.statusCode.toString()}';
      }
    } catch (e, s) {
      logger.error("Exception", error: e, stackTrace: s);
      data["error"] = e.toString();
    }
    return data;
  }
}
