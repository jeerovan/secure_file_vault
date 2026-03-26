import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path_lib;
import 'package:http/http.dart' as http_lib;
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
      } else if (itemTask.task == ItemTask.delete.value) {
        await checkDeleteItemFile(itemTask);
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
    if (modelItem == null || modelItem.fileId == null) {
      await itemTask.delete();
      return true;
    }
    final inFilePath = await ModelItem.getPathForLocalItem(modelItem.id);
    final inFile = File(inFilePath);
    if (!inFile.existsSync()) {
      itemTask.task = ItemTask.delete.value;
      await itemTask.update(["task"]);
      return true;
    }
    ModelFile? modelFile = await ModelFile.get(modelItem.fileId!);
    if (modelFile == null) {
      itemTask.task = ItemTask.delete.value;
      await itemTask.update(["task"]);
      return true;
    }
    // check if already uploaded
    if (modelFile.uploadedAt > 0) {
      await itemTask.delete();
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
      final status = providerResult["status"];
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
    if (modelFile.provider == StorageProvider.fife.value ||
        modelFile.provider == StorageProvider.backblaze.value) {
      final urlResult = await api.post(
          endpoint: '/b2/get-upload-url',
          jsonBody: {"storage_id": modelFile.storageId});
      final status = urlResult["status"];
      if (status <= 0) {
        logger.error('Get upload url: ${jsonEncode(urlResult)}');
        return true;
      } else {
        final urlData = urlResult["data"];
        final uploadUrl = urlData["uploadUrl"];
        final uploadToken = urlData["authorizationToken"];
        return await uploadB2FilePart(itemTask, modelFile.id, uploadUrl,
            uploadToken, inFilePath, modelFile.partsUploaded + 1, false);
      }
    } else {
      // TODO handle other providers
    }
    return true;
  }

  Future<bool> uploadB2FilePart(
      ModelItemTask itemTask,
      String fileHash,
      String uploadUrl,
      String uploadToken,
      String inFilePath,
      int part,
      bool multipart) async {
    String fileHashPart = '${fileHash}_$part';
    Directory tempDir = await getTemporaryDirectory();
    String fileOutPath = path_lib.join(tempDir.path, "$fileHashPart.crypt");
    if (!File(fileOutPath).existsSync()) {
      FileSplitter fileSplitter = FileSplitter(file: File(inFilePath));
      final range = fileSplitter.getStartEndIndexForPart(part);
      SodiumSumo sodium = await SodiumSumoInit.init();
      CryptoUtils cryptoUtils = CryptoUtils(sodium);
      ExecutionResult fileEncryptionResult = await cryptoUtils.encryptFile(
          inFilePath, fileOutPath,
          start: range.start, end: range.end);
      if (fileEncryptionResult.isSuccess) {
        // may fail due to low storage
        String encryptionKeyBase64 = fileEncryptionResult.getResult()!["key"];
        Uint8List encryptionKeyBytes = base64Decode(encryptionKeyBase64);
        String? masterKeyBase64 = await getMasterKey();
        Uint8List masterKeyBytes = base64Decode(masterKeyBase64!);
        Map<String, dynamic> encryptionKeyCipher = cryptoUtils
            .getFileEncryptionKeyCipher(encryptionKeyBytes, masterKeyBytes);
        File encryptedFile = File(fileOutPath);
        int fileSize = encryptedFile.lengthSync();
        Uint8List fileBytes = File(fileOutPath).readAsBytesSync();
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
    Uint8List fileBytes = File(fileOutPath).readAsBytesSync();
    String sha1Hash = sha1.convert(fileBytes).toString();
    int contentLength = fileBytes.length;
    String? userId = getSignedInUserId();
    Map<String, String> headers = {
      "authorization": uploadToken,
      "X-Bz-Content-Sha1": sha1Hash,
      "X-Bz-File-Name": '$userId%2F$fileHashPart',
      "Content-Length": contentLength.toString(),
      "Content-Type": "application/octet-stream",
    };

    logger.info(
        "pushFilePart|$fileHash|$part| uploading bytes to upload url with headers");
    Map<String, dynamic> uploadResult = await uploadB2FileBytes(
        bytes: fileBytes, url: uploadUrl, headers: headers);
    logger.info("UploadedBytes:${jsonEncode(uploadResult)}");
    // update parts_uploaded
    if (uploadResult["error"].isEmpty) {
      logger.info("pushFilePart|$fileHash|$part| bytes uploaded");
      // verify uploaded content length and sha1hash
      int uploadedContentLength = uploadResult["contentLength"];
      String uploadedSha1 = uploadResult["contentSha1"];
      String b2FileId = uploadResult["fileId"];
      if (sha1Hash == uploadedSha1 && contentLength == uploadedContentLength) {
        //update
        ModelFile? modelFile = await ModelFile.get(fileHash);
        ModelPart? modelPart = await ModelPart.get(fileHashPart);
        if (modelFile == null || modelPart == null) {
          logger.error("PushFilePart", error: "file or part missing");
          return true;
        }
        modelFile.partsUploaded = part;
        List<String> fileAttrs = ["parts_uploaded"];

        Map<String, dynamic> partData = modelPart.data;
        partData["fileId"] = b2FileId;
        modelPart.data = partData;
        List<String> partAttrs = ["data"];
        await modelPart.update(partAttrs);

        if (modelFile.parts == modelFile.partsUploaded) {
          logger.info("pushFilePart|$fileHash|all parts uploaded");
          modelFile.uploadedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
          fileAttrs.add("uploaded_at");
          await itemTask.delete();
        }
        await modelFile.update(fileAttrs);
      }
    } else {
      logger.error("Upload B2 File Part", error: jsonEncode(uploadResult));
    }
    return true;
  }

  static Future<Map<String, dynamic>> uploadB2FileBytes({
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
      logger.error("Upload B2 File Bytes", error: e, stackTrace: s);
      data["error"] = e.toString();
    }
    return data;
  }

  Future<void> checkDeleteItemFile(ModelItemTask itemTask) async {
    ModelItem? modelItem = await ModelItem.get(itemTask.id);
    if (modelItem == null || modelItem.fileId == null) {
      await itemTask.delete();
      return;
    }
    ModelFile? modelFile = await ModelFile.get(modelItem.fileId!);
    if (modelFile == null) {
      await itemTask.delete();
      return;
    }
    if (modelFile.uploadedAt > 0) {
      await ModelFile.updateItemCount(modelItem.fileId!, false);
      await modelItem.delete();
      await itemTask.delete();
    } else {
      int parts = modelFile.parts;
      while (parts > 0) {
        ModelPart? modelPart = await ModelPart.get('${modelFile.id}_$parts');
        if (modelPart != null) {
          await modelPart.delete();
        }
        parts = parts - 1;
      }
      await modelFile.delete();
      await modelItem.delete();
      await itemTask.delete();
    }
  }

  Future<void> checkInitDownload(ModelItemTask itemTask) async {
    ModelItem? modelItem = await ModelItem.get(itemTask.id);
    if (modelItem == null || modelItem.fileId == null) {
      await itemTask.delete();
      return;
    }
    ModelFile? modelFile = await ModelFile.get(modelItem.fileId!);
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
    if (provider == StorageProvider.fife.value ||
        provider == StorageProvider.backblaze.value) {
      String downloadUrl = await getB2DownloadUrl(modelFile, partToDownload);
      if (downloadUrl.isNotEmpty) {
        logger.info("$name:$partToDownload: fetched download url");
        Directory tempDir = await getTemporaryDirectory();
        String tempFilePath = "${tempDir.path}/$fileHashPart";
        File tempFile = File(tempFilePath);
        IOSink fileSink = tempFile.openWrite();
        bool downloaded = await downloadFileStream(
            url: downloadUrl,
            headers: null,
            fileOut: fileSink,
            onProgress: null);
        if (downloaded) {
          logger.info("$name:$partToDownload: Downloaded");
          // match sha1 hash
          Map<String, dynamic> partData = modelPart.data;
          Uint8List fileBytes = File(tempFilePath).readAsBytesSync();
          String sha1Hash = sha1.convert(fileBytes).toString();
          int contentLength = fileBytes.length;
          if (modelPart.size == contentLength && sha1Hash == partData["sha1"]) {
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
            logger.error("$name:$partToDownload: length or sha1 did not match");
          }
        }
      }
    }
  }

  static Future<String> getB2DownloadUrl(ModelFile modelFile, int part) async {
    final api = BackendApi();
    final downloadResult = await api.post(
        endpoint: '/b2/get-download-url',
        jsonBody: {
          "storage_id": modelFile.storageId,
          "file_id": '${modelFile.id}_$part'
        });
    final status = downloadResult["status"];
    String downloadUrl = "";
    if (status > 0) {
      downloadUrl = downloadResult["data"];
    } else {
      logger.error("B2 get download url", error: jsonEncode(downloadResult));
    }
    return downloadUrl;
  }
}
