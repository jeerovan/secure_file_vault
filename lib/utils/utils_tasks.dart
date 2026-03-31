import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path_lib;
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../services/service_logger.dart';
import 'utils_crypto.dart';

class TaskManager {
  // 1. Singleton implementation
  static final TaskManager _instance = TaskManager._internal();
  static final logger = AppLogger(prefixes: [
    "Tasker",
  ]);
  factory TaskManager() {
    return _instance;
  }

  TaskManager._internal();

  // State trackers
  bool _isDispatching = false;
  bool _inBackground = false;
  DateTime _startTime = DateTime.now();

  // Stores active uploads with an identifiable parameter (Task ID)
  final Set<String> _activeTaskIds = {};

  /// Static function "init" to start the process
  static void init({bool inBackground = false}) {
    if (_instance._activeTaskIds.isNotEmpty || _instance._isDispatching) {
      logger.info("Already running.");
      return;
    }
    _instance.setStartTime();
    _instance.start(inBackground);
  }

  void setStartTime() async {
    _startTime = DateTime.now();
  }

  /// Dispatcher function
  Future<void> start(bool isBackground) async {
    // Maintains running state in a flag to ignore start request if already running
    if (_isDispatching) return;

    _isDispatching = true;
    _inBackground = isBackground;

    try {
      bool hasInternet = await InternetConnection().hasInternetAccess;
      if (!hasInternet) return;

      // Concurrency limits
      final int maxConcurrentProcesses = _inBackground ? 1 : 1;

      while (_activeTaskIds.length < maxConcurrentProcesses) {
        // Fetches pending upload identifier from another function
        final String? pendingTaskId =
            await ModelItemTask.fetchPendingTask(_activeTaskIds);

        // Break if no pending task are available
        if (pendingTaskId == null) {
          break;
        }

        // Ensure we don't start the same task twice concurrently
        if (!_activeTaskIds.contains(pendingTaskId)) {
          _activeTaskIds.add(pendingTaskId);
          logger.info("Starting task: $pendingTaskId");
          // Initiate task process without awaiting to allow parallel execution up to the limit
          dispatchTask(pendingTaskId);
        }
      }
    } catch (e, s) {
      logger.error('Error in dispatcher', error: e.toString(), stackTrace: s);
    } finally {
      // Release dispatcher lock so finishing processes can re-trigger it
      _isDispatching = false;
    }
  }

  /// Internal processor handling individual tasks
  Future<void> dispatchTask(String taskId) async {
    bool queueNext = true;
    try {
      ModelItemTask? itemTask = await ModelItemTask.get(taskId);
      if (itemTask!.task == ItemTask.download.value) {
        await checkInitDownload(itemTask);
      } else if (itemTask.task == ItemTask.upload.value) {
        queueNext = await checkInitUpload(itemTask);
      }
    } catch (e, s) {
      logger.error("Task $taskId failed", error: e.toString(), stackTrace: s);
    } finally {
      // Remove from active processes using the identifiable parameter
      _activeTaskIds.remove(taskId);

      // Tracks task time when an task process finishes
      final Duration taskDuration = DateTime.now().difference(_startTime);
      logger.info(
          'Task $taskId finished. Time taken: ${taskDuration.inSeconds}s');

      // Check background constraint: if took > 1 minute, end without restarting
      if (_inBackground) {
        if (Platform.isIOS && taskDuration.inMinutes >= 1) {
          logger.info(
              'Background process exceeded 1 minute limit. Ending queue.');
          queueNext = false;
        } else if (Platform.isAndroid && taskDuration.inMinutes >= 2) {
          queueNext = false;
        }
      }
      // Call dispatcher function to enqueue new task process
      if (queueNext) start(_inBackground);
    }
  }

  Future<bool> checkInitUpload(ModelItemTask itemTask) async {
    ModelItem? modelItem = await ModelItem.get(itemTask.id);
    if (modelItem == null || modelItem.fileHash == null) {
      await itemTask.delete();
      return true;
    }
    final inFilePath = await ModelItem.getPathForLocalItem(modelItem.id);
    final inFile = File(inFilePath);
    if (!inFile.existsSync()) {
      await modelItem.remove(); //its remove not delete
      await itemTask.delete();
      return true;
    }
    ModelFile? modelFile = await ModelFile.get(modelItem.fileHash!);
    if (modelFile == null) {
      await modelItem.remove();
      await itemTask.delete();
      return true;
    }
    // check if already uploaded
    if (modelFile.uploadedAt > 0) {
      await itemTask.delete();
      return true;
    }
    int partToUpload = await ModelPart.getPartToUploadForFileHash(
        modelFile.id, modelFile.parts);
    if (partToUpload > modelFile.parts) {
      modelFile.uploadedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      await modelFile.update(["uploaded_at"]);
      await itemTask.delete();
      EventStream().publish(AppEvent(
          type: EventType.updateItem,
          id: modelItem.id,
          key: EventKey.uploaded));
      return true;
    }
    final api = BackendApi();
    // handle storage providers
    if (modelFile.storageId == null) {
      // call Api and set
      final providerResult = await api.post(
          endpoint: '/get-upload-storage-provider',
          jsonBody: {
            "file_hash": modelFile.id,
            "file_size": inFile.lengthSync()
          });
      final status = providerResult["success"];
      if (status <= 0) {
        logger.error('Get storage provider: ${jsonEncode(providerResult)}');
        return false;
      } else {
        final providerData = providerResult["data"];
        modelFile.storageId = providerData["storage_id"];
        modelFile.provider = providerData["provider"];
        List<String> attrs = ["storage_id", "provider"];
        await modelFile.update(attrs);
      }
    }
    if (modelFile.provider == 0) {
      return true;
    }

    Map<String, dynamic> uploadInfo = {};
    if (modelFile.provider == StorageProvider.fife.value ||
        modelFile.provider == StorageProvider.backblaze.value) {
      final urlResult = await api.post(
          endpoint: '/b2/get-upload-url',
          jsonBody: {"storage_id": modelFile.storageId});
      final status = urlResult["success"];
      if (status <= 0) {
        logger.error('Get B2 upload url: ${jsonEncode(urlResult)}');
        return true;
      } else {
        final urlData = urlResult["data"];
        uploadInfo["provider"] = "b2";
        uploadInfo["url"] = urlData["uploadUrl"];
        uploadInfo["token"] = urlData["authorizationToken"];
      }
    } else if (modelFile.provider == StorageProvider.cloudflare.value) {
      String fileId = '${modelFile.id}_$partToUpload';
      final urlResult = await api.post(
          endpoint: '/r2/get-upload-url',
          jsonBody: {"storage_id": modelFile.storageId, "file_id": fileId});
      final status = urlResult["success"];
      if (status <= 0) {
        logger.error('Get R2 upload url: ${jsonEncode(urlResult)}');
        return true;
      } else {
        uploadInfo["provider"] = "r2";
        uploadInfo["url"] = urlResult["data"];
      }
    }
    if (uploadInfo.containsKey("provider")) {
      return await uploadFilePart(
          itemTask, modelFile.id, uploadInfo, inFilePath, partToUpload);
    }
    return true;
  }

  Future<bool> uploadFilePart(ModelItemTask itemTask, String fileHash,
      Map<String, dynamic> uploadInfo, String inFilePath, int part) async {
    String fileHashPart = '${fileHash}_$part';
    Directory tempDir = await getTemporaryDirectory();
    String encryptedFilePath =
        path_lib.join(tempDir.path, "$fileHashPart.crypt");
    if (!File(encryptedFilePath).existsSync()) {
      FileSplitter fileSplitter = FileSplitter(file: File(inFilePath));
      final range = fileSplitter.getStartEndIndexForPart(part);
      SodiumSumo sodium = await SodiumSumoInit.init();
      CryptoUtils cryptoUtils = CryptoUtils(sodium);
      ExecutionResult fileEncryptionResult = await cryptoUtils.encryptFile(
          inFilePath, encryptedFilePath,
          start: range.start, end: range.end);
      if (fileEncryptionResult.isSuccess) {
        // may fail due to low storage
        String encryptionKeyBase64 = fileEncryptionResult.getResult()!["key"];
        Uint8List encryptionKeyBytes = base64Decode(encryptionKeyBase64);
        String? masterKeyBase64 = await getMasterKey();
        Uint8List masterKeyBytes = base64Decode(masterKeyBase64!);
        Map<String, dynamic> encryptionKeyCipher = cryptoUtils
            .getFileEncryptionKeyCipher(encryptionKeyBytes, masterKeyBytes);
        File encryptedFile = File(encryptedFilePath);
        int fileSize = encryptedFile.lengthSync();
        Uint8List fileBytes = File(encryptedFilePath).readAsBytesSync();
        String sha1Hash = sha1.convert(fileBytes).toString();
        Map<String, dynamic> partData = {
          "id": fileHashPart,
          "data": {"sha1": sha1Hash},
          "size": fileSize,
          AppString.cipher.string:
              encryptionKeyCipher[AppString.keyCipher.string],
          AppString.nonce.string: encryptionKeyCipher[AppString.keyNonce.string]
        };
        ModelPart modelPart = await ModelPart.fromMap(partData);
        await modelPart.insert();
      } else {
        logger.error("Encryption failed",
            error: fileEncryptionResult.failureReason);
        return false;
      }
    }
    Uint8List fileBytes = File(encryptedFilePath).readAsBytesSync();
    Map<String, String> headers = {};

    String sha1Hash = sha1.convert(fileBytes).toString();
    int contentLength = fileBytes.length;
    String method = 'POST';
    if (uploadInfo["provider"] == "b2") {
      String? userId = getSignedInUserId();
      headers = {
        "authorization": uploadInfo["token"],
        "X-Bz-Content-Sha1": sha1Hash,
        "X-Bz-File-Name": '$userId%2F$fileHashPart',
        "Content-Length": contentLength.toString(),
        "Content-Type": "application/octet-stream",
      };
    } else if (uploadInfo["provider"] == "r2") {
      method = 'PUT';
      headers = {
        "Content-Length": contentLength.toString(),
        "Content-Type": "application/octet-stream",
      };
    }
    String uploadUrl = uploadInfo["url"];
    logger.info(
        "pushFilePart|$fileHash|$part| uploading bytes to upload url with headers");
    Map<String, dynamic> uploadResult = await uploadFileBytes(
        method: method, bytes: fileBytes, url: uploadUrl, headers: headers);
    logger.info("UploadedBytes:${jsonEncode(uploadResult)}");
    // update parts_uploaded
    if (uploadResult["error"].isEmpty) {
      logger.info("pushFilePart|$fileHash|$part| bytes uploaded");

      //update
      ModelPart? modelPart = await ModelPart.get(fileHashPart);
      if (modelPart == null) {
        logger.error("PushFilePart", error: "file or part missing");
        return true;
      }
      modelPart.uploaded = 1;
      List<String> partAttrs = ["uploaded"];

      if (uploadResult.containsKey("fileId")) {
        String b2FileId = uploadResult["fileId"];
        Map<String, dynamic> partData = modelPart.data;
        partData["fileId"] = b2FileId;
        modelPart.data = partData;
        partAttrs.add("data");
      }
      await modelPart.update(partAttrs);
    } else {
      logger.error("Upload File Part", error: jsonEncode(uploadResult));
    }
    try {
      File(encryptedFilePath).delete();
    } catch (e) {
      // could not delete temp file
    }
    return true;
  }

  Future<void> checkInitDownload(ModelItemTask itemTask) async {
    ModelItem? modelItem = await ModelItem.get(itemTask.id);
    if (modelItem == null || modelItem.fileHash == null) {
      await itemTask.delete();
      return;
    }
    ModelFile? modelFile = await ModelFile.get(modelItem.fileHash!);
    if (modelFile == null) {
      await itemTask.delete();
      return;
    }
    int size = modelItem.size;
    int parts = modelFile.parts;
    String name = modelItem.name;
    Directory tempStorage = await getAppTempDirectory();
    String filePath = path_lib.join(tempStorage.path, name);
    int partsHave = 0;
    FileSplitter fileSplitter = FileSplitter(fileSize: size);
    if (File(filePath).existsSync()) {
      partsHave = fileSplitter.getPartsInSize(File(filePath).lengthSync());
    }
    if (partsHave == parts) {
      String finalFilePath = await ModelItem.getPathForItem(modelItem.id);
      await File(filePath).rename(finalFilePath);
      await itemTask.delete();
      return;
    }
    int partToDownload = partsHave + 1;
    int provider = modelFile.provider;
    String fileHashPart = '${modelFile.id}_$partToDownload';
    ModelPart? modelPart = await ModelPart.get(fileHashPart);
    if (modelPart == null) return;
    String downloadUrl = "";
    if (provider == StorageProvider.fife.value ||
        provider == StorageProvider.backblaze.value) {
      downloadUrl = await getDownloadUrl("b2", modelFile, partToDownload);
    } else if (provider == StorageProvider.cloudflare.value) {
      downloadUrl = await getDownloadUrl("r2", modelFile, partToDownload);
    }
    if (downloadUrl.isNotEmpty) {
      logger.info("$name:$partToDownload: fetched download url");
      Directory tempDir = await getTemporaryDirectory();
      String tempFilePath = "${tempDir.path}/$fileHashPart";
      File tempFile = File(tempFilePath);
      IOSink fileSink = tempFile.openWrite();
      int downloadedRequestState = await downloadFileStream(
          url: downloadUrl, headers: null, fileOut: fileSink, onProgress: null);
      if (downloadedRequestState == 1) {
        logger.info("$name:$partToDownload: Downloaded");
        // match length
        Uint8List fileBytes = File(tempFilePath).readAsBytesSync();
        int contentLength = fileBytes.length;
        if (modelPart.size == contentLength) {
          String keyCipherBase64 = modelPart.cipher;
          String keyNonceBase64 = modelPart.nonce;
          SodiumSumo sodium = await SodiumSumoInit.init();
          CryptoUtils cryptoUtils = CryptoUtils(sodium);
          String? masterKeyBase64 = await getMasterKey();
          Uint8List? fileEncryptionKeyBytes =
              cryptoUtils.getFileEncryptionKeyBytes(
                  keyCipherBase64, keyNonceBase64, masterKeyBase64!);
          if (fileEncryptionKeyBytes != null) {
            ExecutionResult decryptionResult = await cryptoUtils.decryptFile(
                tempFilePath, filePath, fileEncryptionKeyBytes);
            if (decryptionResult.isSuccess) {
              logger.info("$name:$partToDownload:Fetched & decrypted");
              if (partToDownload == parts) {
                String finalFilePath =
                    await ModelItem.getPathForItem(modelItem.id);
                await File(filePath).rename(finalFilePath);
                await itemTask.delete();
              }
            } else {
              String error = decryptionResult.failureReason ?? "";
              logger.error(
                  "$name:$partToDownload:Fetched but decryption failed",
                  error: error);
            }
          }
        } else {
          logger.error("$name:$partToDownload: length did not match");
        }
        try {
          tempFile.delete();
        } catch (e) {
          // could not delete temp file
        }
      } else if (downloadedRequestState == -1) {
        await modelItem.forceRemove();
      }
    }
  }

  static Future<String> getDownloadUrl(
      String provider, ModelFile modelFile, int part) async {
    final api = BackendApi();
    final downloadResult = await api.post(
        endpoint: '/$provider/get-download-url',
        jsonBody: {
          "storage_id": modelFile.storageId,
          "file_id": '${modelFile.id}_$part'
        });
    final status = downloadResult["success"];
    String downloadUrl = "";
    if (status > 0) {
      downloadUrl = downloadResult["data"];
    } else {
      logger.error("Get download url", error: jsonEncode(downloadResult));
    }
    return downloadUrl;
  }
}
