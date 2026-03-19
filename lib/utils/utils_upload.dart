import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_transfer.dart';
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

class UploadManager {
  // 1. Singleton implementation
  static final UploadManager _instance = UploadManager._internal();
  static final logger = AppLogger(prefixes: [
    "Uploader",
  ]);
  factory UploadManager() {
    return _instance;
  }

  UploadManager._internal();

  // State trackers
  bool _isDispatching = false;
  bool _isBackgroundMode = false;
  DateTime _startTime = DateTime.now();

  // Stores active uploads with an identifiable parameter (Upload ID)
  final Set<String> _activeUploadProcesses = {};

  /// Static function "init" to start the process
  static void init({bool isBackground = false}) {
    if (_instance._activeUploadProcesses.isNotEmpty ||
        _instance._isDispatching) {
      return;
    }
    _instance.setStartTime();
    _instance.start(isBackground);
  }

  void setStartTime() async {
    _startTime = DateTime.now();
  }

  /// Dispatcher function
  Future<void> start(bool isBackground) async {
    // Maintains running state in a flag to ignore start request if already running
    if (_isDispatching) return;

    _isDispatching = true;
    _isBackgroundMode = isBackground;

    try {
      bool hasInternet = await InternetConnection().hasInternetAccess;
      if (!hasInternet) return;

      // Concurrency limits: 1 for background, 3 for foreground
      final int maxConcurrentProcesses = _isBackgroundMode ? 1 : 3;

      while (_activeUploadProcesses.length < maxConcurrentProcesses) {
        // Fetches pending upload identifier from another function
        final String? pendingUploadId =
            await ModelTransfer.fetchPendingUpload(_activeUploadProcesses);

        // Break if no pending uploads are available
        if (pendingUploadId == null) {
          break;
        }

        // Ensure we don't start the same upload twice concurrently
        if (!_activeUploadProcesses.contains(pendingUploadId)) {
          _activeUploadProcesses.add(pendingUploadId);

          // Initiate upload process without awaiting to allow parallel execution up to the limit
          dispatchUpload(pendingUploadId);
        }
      }
    } catch (e) {
      debugPrint('Error in dispatcher: $e');
    } finally {
      // Release dispatcher lock so finishing processes can re-trigger it
      _isDispatching = false;
    }
  }

  /// Internal processor handling individual uploads
  Future<void> dispatchUpload(String uploadId) async {
    bool queueNext = true;
    try {
      bool success = await checkInitUpload(uploadId);
      queueNext = success;
    } catch (e) {
      debugPrint('Upload failed for $uploadId: $e');
    } finally {
      // Remove from active processes using the identifiable parameter
      _activeUploadProcesses.remove(uploadId);

      // Tracks upload time when an upload process finishes
      final Duration uploadDuration = DateTime.now().difference(_startTime);
      debugPrint(
          'Upload $uploadId finished. Time taken: ${uploadDuration.inSeconds}s');

      // Check background constraint: if took > 1 minute, end without restarting
      if (_isBackgroundMode) {
        if (Platform.isIOS && uploadDuration.inMinutes >= 1) {
          debugPrint(
              'Background process exceeded 1 minute limit. Ending queue.');
          queueNext = false;
        } else if (Platform.isAndroid && uploadDuration.inMinutes >= 2) {
          queueNext = false;
        }
      }
      // Call dispatcher function to enqueue new upload process
      if (queueNext) start(_isBackgroundMode);
    }
  }

  /// Replace with your actual chunked/encrypted cloud upload logic
  Future<bool> checkInitUpload(String uploadId) async {
    ModelItem? modelItem = await ModelItem.get(uploadId);
    if (modelItem == null || modelItem.fileId == null) {
      await ModelTransfer.deleteTransfer(uploadId);
      return true;
    }
    final inFilePath = await ModelItem.getPathForItem(modelItem.id);
    final inFile = File(inFilePath);
    if (!inFile.existsSync()) {
      await ModelTransfer.deleteTransfer(uploadId);
      return true;
    }
    ModelFile? modelFile = await ModelFile.get(modelItem.fileId!);
    if (modelFile == null) {
      await ModelTransfer.deleteTransfer(uploadId);
      return true;
    }
    // check if already uploaded
    if (modelFile.uploadedAt > 0) {
      await ModelTransfer.deleteTransfer(uploadId);
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
        return true;
      } else {
        final providerData = providerResult["data"];
        modelFile.storageId = providerData["storage"];
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
      if (modelFile.parts == modelFile.partsUploaded) {
        // May have failed to verify and update
        finishMultiPartB2Upload(uploadId, modelFile);
        return true;
      }
      if (modelFile.parts > 1) {
        // Check get fileId
        Map<String, dynamic> data = modelFile.data;
        if (!data.containsKey("fileId")) {
          final fileIdResult = await api.post(
              endpoint: '/b2/start-parts-upload',
              jsonBody: {
                "file_hash": modelFile.id,
                "storage_id": modelFile.storageId
              });
          final status = fileIdResult["status"];
          if (status <= 0) {
            return true;
          } else {
            final fileIdData = fileIdResult["data"];
            data["fileId"] = fileIdData["fileId"];
            modelFile.data = data;
            List<String> attrs = ["data"];
            await modelFile.update(attrs);
          }
        }
        String fileId = data["fileId"];
        final urlResult = await api.post(
            endpoint: '/b2/get-upload-part-url',
            jsonBody: {"file_id": fileId, "storage_id": modelFile.storageId});
        final status = urlResult["status"];
        if (status <= 0) {
          return true;
        } else {
          final urlData = urlResult["data"];
          final uploadUrl = urlData["uploadUrl"];
          final uploadToken = urlData["authorizationToken"];
          return await uploadFilePart(uploadId, modelFile.id, uploadUrl,
              uploadToken, inFilePath, modelFile.partsUploaded + 1, true);
        }
        // get upload part url
      } else {
        // get upload part url
        final urlResult = await api.post(
            endpoint: '/b2/get-upload-url',
            jsonBody: {"storage_id": modelFile.storageId});
        final status = urlResult["status"];
        if (status <= 0) {
          return true;
        } else {
          final urlData = urlResult["data"];
          final uploadUrl = urlData["uploadUrl"];
          final uploadToken = urlData["authorizationToken"];
          return await uploadFilePart(uploadId, modelFile.id, uploadUrl,
              uploadToken, inFilePath, modelFile.partsUploaded + 1, false);
        }
      }
    } else {
      // TODO handle other providers
    }
    return true;
  }

  Future<bool> uploadFilePart(
      String uploadId,
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
      FileSplitter fileSplitter = FileSplitter(File(inFilePath));
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
        Map<String, dynamic> partData = {
          "id": fileHashPart,
          "file_id": fileHash,
          "part_number": part,
          "size": fileSize,
          AppString.cipher.string:
              encryptionKeyCipher[AppString.keyCipher.string],
          AppString.nonce.string: encryptionKeyCipher[AppString.keyNonce.string]
        };
        ModelPart modelPart = await ModelPart.fromMap(partData);
        await modelPart.insert();
      } else if (fileEncryptionResult.failureReason!
          .contains("PathNotFoundException")) {
        await ModelTransfer.deleteTransfer(uploadId);
        return true;
      } else {
        return true; // Try again
      }
    }
    Uint8List fileBytes = File(fileOutPath).readAsBytesSync();
    String sha1Hash = sha1.convert(fileBytes).toString();
    Map<String, String> headers = {};
    int contentLength = fileBytes.length;
    if (multipart) {
      headers = {
        "authorization": uploadToken,
        "X-Bz-Part-Number": part.toString(),
        "X-Bz-Content-Sha1": sha1Hash,
        "Content-Length": contentLength.toString(),
      };
    } else {
      String? userId = getSignedInUserId();
      headers = {
        "authorization": uploadToken,
        "X-Bz-Content-Sha1": sha1Hash,
        "X-Bz-File-Name": '$userId%2F$fileHash',
        "Content-Length": contentLength.toString(),
        "Content-Type": "application/octet-stream",
      };
    }

    logger.info(
        "pushFilePart|$fileHash|$part| uploading bytes to upload url with headers");
    Map<String, dynamic> uploadResult = await uploadFileBytes(
        bytes: fileBytes, url: uploadUrl, headers: headers);
    logger.info("UploadedBytes:${jsonEncode(uploadResult)}");
    // update parts_uploaded
    if (uploadResult["error"].isEmpty) {
      logger.info("pushFilePart|$fileHash|$part| bytes uploaded");
      // verify uploaded content length and sha1hash
      int uploadedContentLength = uploadResult["contentLength"];
      String uploadedSha1 = uploadResult["contentSha1"];
      String b2FileId =
          uploadResult["fileId"]; // available for both parts and single uploads
      if (sha1Hash == uploadedSha1 && contentLength == uploadedContentLength) {
        //update local first
        ModelFile? modelFile = await ModelFile.get(fileHash);
        if (modelFile == null) return true;
        modelFile.partsUploaded = part;
        Map<String, dynamic> currentData = modelFile.data;
        currentData["fileId"] = b2FileId;
        List<String> attrs = ["parts_uploaded", "data"];
        await modelFile.update(attrs);
        if (modelFile.parts == modelFile.partsUploaded) {
          logger.info("pushFilePart|$fileHash|all parts uploaded");
          if (modelFile.parts > 1) {
            // multi parts
            // call finish parts upload
            await finishMultiPartB2Upload(uploadId, modelFile);
          } else {
            // single part
            modelFile.uploadedAt =
                DateTime.now().toUtc().millisecondsSinceEpoch;
            await modelFile.update(["uploaded_at"]);
            await ModelTransfer.deleteTransfer(uploadId);
          }
        }
      }
    } else {
      logger.error("pushFilePart|uploadBytes", error: jsonEncode(uploadResult));
    }

    return true;
  }

  Future<void> finishMultiPartB2Upload(
      String uploadId, ModelFile modelFile) async {
    final api = BackendApi();
    Map<String, dynamic> data = modelFile.data;
    String b2FileId = data["fileId"];
    List<String> partSha1Array = await ModelPart.shasForFileId(modelFile.id);
    logger.info("pushFilePart|${modelFile.id}|finish multi part");
    final finishResult =
        await api.post(endpoint: '/b2/finish-parts-upload', jsonBody: {
      "storage_id": modelFile.storageId,
      "file_id": b2FileId,
      "part_array": partSha1Array
    });
    final status = finishResult["status"];
    if (status > 0) {
      modelFile.uploadedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      await modelFile.update(["uploaded_at"]);
      await ModelTransfer.deleteTransfer(uploadId);
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
