import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_state.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:file_vault_bb/utils/utils_file.dart';
import 'package:file_vault_bb/utils/utils_transfer_staging.dart';
import 'package:file_vault_bb/utils/utils_transfer_policy.dart';
import 'package:path/path.dart' as path_lib;
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sodium/sodium_sumo.dart';

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

  // Completer to keep background isolate alive
  Completer<void>? _syncCompleter;

  // Stores active uploads with an identifiable parameter (Task ID)
  final Set<String> _activeTaskIds = {};

  Timer? _retryWakeTimer;
  int? _retryWakeAt;
  StreamSubscription<InternetStatus>? _connectivitySubscription;
  Future<void> Function()? _retryWakeHandler;

  // Store the last 5 task durations to calculate a responsive rolling average
  final Queue<int> _recentTaskDurationsMs = Queue<int>();
  static const int _maxHistoryLength = 5;

  /// Static function "init" to start the process.
  static Future<void> init({Future<void> Function()? retryWakeHandler}) async {
    if (retryWakeHandler != null) {
      _instance._retryWakeHandler = retryWakeHandler;
    }
    if (_instance._activeTaskIds.isNotEmpty || _instance._isDispatching) {
      logger.info("Already running.");
      // Return the existing future if it's already processing to prevent premature exit
      if (_instance._syncCompleter != null &&
          !_instance._syncCompleter!.isCompleted) {
        return _instance._syncCompleter!.future;
      }
      return;
    }

    _instance._cancelRetryWakeTimer();

    await ModelItemTask.recoverInterruptedTasks();

    _instance._syncCompleter = Completer<void>();

    // Clear history on a fresh start for accurate session estimates
    _instance._recentTaskDurationsMs.clear();

    // Fire and forget start, but block init() using the completer
    _instance.start();

    return _instance._syncCompleter!.future;
  }

  /// Updates the rolling average history with a newly completed task's duration
  void _recordTaskDuration(int durationMs) {
    _recentTaskDurationsMs.addLast(durationMs);
    if (_recentTaskDurationsMs.length > _maxHistoryLength) {
      _recentTaskDurationsMs.removeFirst();
    }
  }

  /// Dispatcher function
  Future<void> start() async {
    // Maintains running state in a flag to ignore start request if already running
    if (_isDispatching) return;

    _isDispatching = true;

    try {
      bool hasInternet = await InternetConnection().hasInternetAccess;
      if (!hasInternet) {
        _waitForConnectivity();
        _checkCompletion();
        return;
      }
      await _cancelConnectivityWake();

      // Concurrency limits
      final maxConcurrentProcesses = TransferConcurrencyPolicy.maxConcurrent(
        isMobile: Platform.isAndroid || Platform.isIOS,
      );
      bool tasksDispatched = false;

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
          logger.info("Starting queued transfer task");
          tasksDispatched = true;
          // Initiate task process without awaiting to allow parallel execution up to the limit
          dispatchTask(pendingTaskId);
        }
      }

      // If loop finished and nothing was queued while nothing is active, complete the process
      if (!tasksDispatched && _activeTaskIds.isEmpty) {
        await _scheduleNextRetryWake();
        _checkCompletion();
      }
    } catch (e, s) {
      logger.error('Error in dispatcher', error: e.toString(), stackTrace: s);
      await _scheduleNextRetryWake();
      _checkCompletion();
    } finally {
      // Release dispatcher lock so finishing processes can re-trigger it
      _isDispatching = false;
    }
  }

  /// Internal processor handling individual tasks
  Future<void> dispatchTask(String taskId) async {
    final DateTime taskStartTime = DateTime.now();
    String? failure;
    OperationLease? lease;
    var queueNext = true;
    try {
      final queuedTask = await ModelItemTask.get(taskId);
      if (queuedTask == null) return;
      final operationId = await _operationIdForTask(queuedTask);
      lease = await ExclusiveOperationCoordinator.tryAcquire(operationId);
      if (lease == null) {
        queueNext = false;
        return;
      }
      ModelItemTask? itemTask = await ModelItemTask.get(taskId);
      if (itemTask == null) return;
      await itemTask.markRunning();

      if (itemTask.task == ItemTask.download.value) {
        await checkInitDownload(itemTask);
      } else if (itemTask.task == ItemTask.upload.value) {
        await checkInitUpload(itemTask);
      } else {
        await itemTask.markBlocked('unknown_task_type');
      }
    } catch (e, s) {
      failure = e.runtimeType.toString();
      logger.error("Transfer task failed", error: e.toString(), stackTrace: s);
    } finally {
      await lease?.release();
      final remainingTask = await ModelItemTask.get(taskId);
      if (remainingTask != null &&
          remainingTask.state == TransferTaskState.running) {
        await remainingTask.scheduleRetry(failure ?? 'transfer_incomplete');
      }
      // Remove from active processes using the identifiable parameter
      _activeTaskIds.remove(taskId);

      final int individualTaskMs =
          DateTime.now().difference(taskStartTime).inMilliseconds;
      _recordTaskDuration(individualTaskMs);

      // Continue with other eligible tasks. Retry-waiting tasks remain persisted.
      if (queueNext) {
        start();
      } else {
        _checkCompletion();
      }
    }
  }

  Future<String> _operationIdForTask(ModelItemTask task) async {
    if (task.task == ItemTask.upload.value) {
      final item = await ModelItem.get(task.id);
      final fileHash = item?.fileHash;
      if (fileHash != null) {
        final opaqueHash = sha256.convert(utf8.encode(fileHash)).toString();
        return 'transfer:upload:$opaqueHash';
      }
    }
    return downloadOperationId(task.id);
  }

  static String downloadOperationId(String itemId) =>
      'transfer:download:$itemId';

  /// Evaluates if the task queue has fully emptied, allowing the isolate to shut down gracefully
  void _checkCompletion() {
    if (_activeTaskIds.isEmpty) {
      if (_syncCompleter != null && !_syncCompleter!.isCompleted) {
        _syncCompleter!.complete();
      }
    }
  }

  static Duration retryWakeDelay(int nextAttemptAt, {DateTime? now}) {
    final current = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
    return Duration(milliseconds: (nextAttemptAt - current).clamp(1, 900000));
  }

  Future<void> _scheduleNextRetryWake() async {
    final nextAttemptAt = await ModelItemTask.fetchNextWakeAt();
    if (nextAttemptAt == null) {
      _cancelRetryWakeTimer();
      return;
    }
    if (_retryWakeTimer?.isActive == true &&
        _retryWakeAt != null &&
        _retryWakeAt! <= nextAttemptAt) {
      return;
    }
    _cancelRetryWakeTimer();
    _retryWakeAt = nextAttemptAt;
    _retryWakeTimer = Timer(retryWakeDelay(nextAttemptAt), () {
      _retryWakeTimer = null;
      _retryWakeAt = null;
      unawaited(_restartFromWake());
    });
  }

  void _cancelRetryWakeTimer() {
    _retryWakeTimer?.cancel();
    _retryWakeTimer = null;
    _retryWakeAt = null;
  }

  void _waitForConnectivity() {
    _connectivitySubscription ??=
        InternetConnection().onStatusChange.listen((status) {
      if (status == InternetStatus.connected) {
        unawaited(_restartFromConnectivity());
      }
    });
  }

  Future<void> _cancelConnectivityWake() async {
    final subscription = _connectivitySubscription;
    _connectivitySubscription = null;
    await subscription?.cancel();
  }

  Future<void> _restartFromConnectivity() async {
    await _cancelConnectivityWake();
    await _restartFromWake();
  }

  Future<void> _restartFromWake() async {
    try {
      if (!await InternetConnection().hasInternetAccess) {
        _waitForConnectivity();
        return;
      }
      final handler = _retryWakeHandler;
      if (handler != null) {
        await handler();
      } else {
        await TaskManager.init();
      }
    } catch (e, s) {
      logger.error('Retry wake failed', error: e, stackTrace: s);
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
    if (await inFile.length() != modelItem.size ||
        !await _fileMatchesHash(inFile, modelFile.id)) {
      await itemTask.markBlocked('upload_source_changed');
      logger.warning('Upload paused because source changed');
      return false;
    }
    // check if already uploaded
    if (modelFile.uploadedAt > 0) {
      await ModelItemTask.completeTask(itemTask.id);
      return true;
    }
    int partToUpload = await ModelPart.getPartToUploadForFileHash(
        modelFile.id, modelFile.parts);
    if (partToUpload > modelFile.parts) {
      modelFile.uploadedAt = DateTime.now().toUtc().millisecondsSinceEpoch;
      await modelFile.update(["uploaded_at"]);
      await ModelItemTask.completeTask(itemTask.id);
      return true;
    }
    final api = BackendApi();
    // handle storage providers
    if (modelFile.storageId == null) {
      // check server if already uploaded and get file+parts
      if (simulateTesting()) {
        modelFile.storageId = 99;
        modelFile.providerId = 99;
        List<String> attrs = ["storage_id", "provider_id"];
        await modelFile.update(attrs);
      } else {
        final filePartResult = await api.post(
          endpoint: '/get-file-parts',
          jsonBody: {"file_hash": modelFile.id},
          retryUnauthorized: true,
        );
        final fileStatus = filePartResult["success"];
        if (fileStatus == 1) {
          final filePartData = filePartResult["data"];
          final fileMap = filePartData["file"];
          final partMapList = filePartData["parts"];
          final newFileModel = await ModelFile.fromServerMap(fileMap);
          await newFileModel.upcertFromServer(overwrite: true);
          for (Map<String, dynamic> partMap in partMapList) {
            final partModel = await ModelPart.fromServerMap(partMap);
            await partModel.upcertFromServer(overwrite: true);
          }
          await itemTask.markPending();
          return true;
        } else {
          final errorMessageCode =
              int.tryParse(filePartResult["message"].toString());
          if (errorMessageCode == null) {
            return false;
          } else if (errorMessageCode != 13) {
            return true;
          }
        }

        // call Api and set
        int fileSize = inFile.lengthSync();
        int bufferSize = 1000;
        int chunks = (fileSize / 4096).ceil();
        int expectedSize = fileSize + 24 + (chunks * 17) + bufferSize;
        final providerResult = await api.post(
            endpoint: '/get-upload-storage-provider',
            jsonBody: {"file_hash": modelFile.id, "file_size": expectedSize},
            retryUnauthorized: true);
        final selectionStatus =
            UploadStorageSelectionPolicy.classify(providerResult);
        if (selectionStatus == UploadStorageSelectionStatus.storageFull) {
          logger.error('No upload storage has enough capacity');
          await ModelState.set(AppString.storageFull.string, "yes");
          EventStream().publish(AppEvent(
            type: EventType.system,
            id: modelFile.id,
            key: EventKey.storageFull,
            value: true,
          ));
          await itemTask.markBlocked('storage_full');
          return false;
        } else if (selectionStatus ==
            UploadStorageSelectionStatus.retryableFailure) {
          logger
              .warning('Upload storage selection failed; task will be retried');
          return false;
        } else {
          final providerData = providerResult["data"];
          modelFile.storageId = providerData["storage_id"];
          modelFile.providerId = providerData["provider_id"];
          List<String> attrs = ["storage_id", "provider_id"];
          await modelFile.update(attrs);
          await ModelState.set(AppString.storageFull.string, "no");
          EventStream().publish(AppEvent(
            type: EventType.system,
            id: modelFile.id,
            key: EventKey.storageFull,
            value: false,
          ));
        }
      }
    }
    if (modelFile.providerId == 0) {
      await itemTask.markBlocked('invalid_storage_provider');
      return true;
    }

    Map<String, dynamic> uploadInfo = {};
    final storageProvider =
        StorageProviderExtension.fromValue(modelFile.providerId ?? 0);
    if (storageProvider == StorageProvider.fife ||
        storageProvider == StorageProvider.backblaze) {
      final urlResult = await api.post(
        endpoint: '/b2/get-upload-url',
        jsonBody: {"storage_id": modelFile.storageId},
        retryUnauthorized: true,
      );
      final status = urlResult["success"];
      if (status <= 0) {
        logger.error('Failed to get B2 upload authorization');
        return true;
      } else {
        final urlData = urlResult["data"];
        uploadInfo["provider"] = "b2";
        uploadInfo["url"] = urlData["uploadUrl"];
        uploadInfo["token"] = urlData["authorizationToken"];
        uploadInfo["storage_id"] = modelFile.storageId;
      }
    } else if (storageProvider.usesPresignedS3Url) {
      String fileId = '${modelFile.id}_$partToUpload';
      final providerPath = storageProvider.apiPath!;
      final urlResult = await api.post(
        endpoint: '/$providerPath/get-upload-url',
        jsonBody: {"storage_id": modelFile.storageId, "file_id": fileId},
        retryUnauthorized: true,
      );
      final status = urlResult["success"];
      if (status <= 0) {
        logger.error('Failed to get upload authorization');
        return true;
      } else {
        uploadInfo["provider"] = "s3";
        uploadInfo["url"] = urlResult["data"];
      }
    } else {
      // simulation
      String fileHashPart = '${modelFile.id}_$partToUpload';
      Map<String, dynamic> partData = {
        "id": fileHashPart,
        "data": {"sha1": ""},
        "size": 0,
        "uploaded": 1,
        AppString.cipher.string: "",
        AppString.nonce.string: ""
      };
      ModelPart modelPart = await ModelPart.fromMap(partData);
      await modelPart.insert();
      // simulate progress
      int parts = modelFile.parts;
      int partsUploaded = partToUpload;
      final int percent = parts > 0 ? (partsUploaded * 100 ~/ parts) : 0;
      final int uploaded = percent.clamp(0, 100);
      itemTask.progress = uploaded;
      await itemTask.update(["progress"]);
      await itemTask.markPending();
      await Future.delayed(const Duration(seconds: 1));
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
        path_lib.join(tempDir.path, "$fileHashPart.crypt.ready");
    final encryptedFile = File(encryptedFilePath);
    final existingPart = await ModelPart.get(fileHashPart);
    var artifactReady = await encryptedFile.exists() && existingPart != null;
    if (artifactReady) {
      final artifactSha1 = await _sha1ForFile(encryptedFile);
      artifactReady = await encryptedFile.length() == existingPart.size &&
          existingPart.data['sha1'] == artifactSha1;
    }
    if (!artifactReady) {
      if (await encryptedFile.exists()) await encryptedFile.delete();
      final partialFile = File('$encryptedFilePath.partial');
      if (await partialFile.exists()) await partialFile.delete();
      final sourceFile = File(inFilePath);
      final sourceBefore = await sourceFile.stat();
      FileSplitter fileSplitter = FileSplitter(file: File(inFilePath));
      final range = fileSplitter.getStartEndIndexForPart(part);
      SodiumSumo sodium = await SodiumSumoInit.init();
      CryptoUtils cryptoUtils = CryptoUtils(sodium);
      ExecutionResult fileEncryptionResult = await cryptoUtils.encryptFile(
          inFilePath, partialFile.path,
          start: range.start, end: range.end);
      if (fileEncryptionResult.isSuccess) {
        final sourceAfter = await sourceFile.stat();
        if (sourceBefore.size != sourceAfter.size ||
            sourceBefore.modified != sourceAfter.modified ||
            !await _fileMatchesHash(sourceFile, fileHash)) {
          if (await partialFile.exists()) await partialFile.delete();
          await itemTask.markBlocked('upload_source_changed');
          return false;
        }
        // may fail due to low storage
        String encryptionKeyBase64 = fileEncryptionResult.getResult()!["key"];
        Uint8List encryptionKeyBytes = base64Decode(encryptionKeyBase64);
        String? masterKeyBase64 = await getMasterKey();
        if (masterKeyBase64 == null) {
          if (await partialFile.exists()) await partialFile.delete();
          return false;
        }
        Uint8List masterKeyBytes = base64Decode(masterKeyBase64);
        Map<String, dynamic> encryptionKeyCipher = cryptoUtils
            .getFileEncryptionKeyCipher(encryptionKeyBytes, masterKeyBytes);
        int fileSize = await partialFile.length();
        String sha1Hash = await _sha1ForFile(partialFile);
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
        await partialFile.rename(encryptedFile.path);
      } else {
        if (await partialFile.exists()) await partialFile.delete();
        logger.error("Encryption failed",
            error: fileEncryptionResult.failureReason);
        return false;
      }
    }
    Map<String, String> headers = {};

    String sha1Hash = await _sha1ForFile(encryptedFile);
    int contentLength = await encryptedFile.length();
    String method = 'POST';
    if (uploadInfo["provider"] == "b2") {
      String? userId = await getSignedInUserId();
      headers = {
        "authorization": uploadInfo["token"],
        "X-Bz-Content-Sha1": sha1Hash,
        "X-Bz-File-Name": '$userId%2F$fileHashPart',
        "Content-Length": contentLength.toString(),
        "Content-Type": "application/octet-stream",
      };
    } else if (uploadInfo["provider"] == "s3") {
      method = 'PUT';
      headers = {
        "Content-Length": contentLength.toString(),
        "Content-Type": "application/octet-stream",
      };
    }
    String uploadUrl = uploadInfo["url"];
    logger.info("Uploading encrypted file part");
    final modelFile = await ModelFile.get(fileHash);
    final partCount = modelFile?.parts ?? 1;
    var lastProgress = itemTask.progress;
    UploadFileResult? uploadResult;
    if (uploadInfo["provider"] == "b2") {
      final storedPart = await ModelPart.get(fileHashPart);
      if (storedPart == null) {
        logger.error("PushFilePart", error: "file or part missing");
        return true;
      }
      final uploadAttempted =
          B2UploadRecoveryPolicy.wasAttempted(storedPart.data);
      if (uploadAttempted) {
        final recoveryResult = await BackendApi().post(
          endpoint: '/b2/find-uploaded-file',
          jsonBody: {
            "storage_id": uploadInfo["storage_id"],
            "file_id": fileHashPart,
            "content_sha1": sha1Hash,
            "content_length": contentLength,
          },
          retryUnauthorized: true,
        );
        if (recoveryResult["success"] != 1) {
          logger.warning('Unable to reconcile an earlier B2 upload attempt');
          return true;
        }
        final recoveredFileId =
            B2UploadRecoveryPolicy.recoveredFileId(recoveryResult);
        if (recoveredFileId != null) {
          logger.info('Recovered an already uploaded B2 file part');
          uploadResult = UploadFileResult.success({"fileId": recoveredFileId});
        }
      } else {
        storedPart.data = B2UploadRecoveryPolicy.markAttempted(storedPart.data);
        await storedPart.update(["data"]);
      }
    }
    uploadResult ??= await uploadFileStream(
        method: method,
        file: encryptedFile,
        url: uploadUrl,
        headers: headers,
        onProgress: (sent, total) async {
          final currentPartPercent = total <= 0 ? 100 : sent * 100 ~/ total;
          final overall = (((part - 1) * 100 + currentPartPercent) ~/ partCount)
              .clamp(0, 99);
          if (overall <= lastProgress) return;
          lastProgress = overall;
          itemTask.progress = overall;
          await itemTask.update(["progress"]);
        });
    // update uploaded
    if (uploadResult.succeeded) {
      logger.info("Encrypted file part uploaded");

      //update
      ModelPart? modelPart = await ModelPart.get(fileHashPart);
      if (modelPart == null) {
        logger.error("PushFilePart", error: "file or part missing");
        return true;
      }
      modelPart.uploaded = 1;
      List<String> partAttrs = ["uploaded"];

      if (uploadResult.data.containsKey("fileId")) {
        String b2FileId = uploadResult.data["fileId"];
        Map<String, dynamic> partData = modelPart.data;
        partData["fileId"] = b2FileId;
        modelPart.data = partData;
        partAttrs.add("data");
      }
      await modelPart.update(partAttrs);
      // Broadcast upload progress
      if (modelFile != null) {
        int parts = modelFile.parts;
        int partsUploaded =
            await ModelPart.getPartsUploadedForFileHash(fileHash, parts);
        final int percent = parts > 0 ? (partsUploaded * 100 ~/ parts) : 0;
        final int uploaded = percent.clamp(0, 100);
        itemTask.progress = uploaded;
        await itemTask.update(["progress"]);
      }
      if (await encryptedFile.exists()) await encryptedFile.delete();
      // A retry reuses the ready artifact and therefore does not pass through
      // artifact creation. Transition only after the part is durably recorded
      // so both fresh uploads and retries immediately continue/finalize.
      await itemTask.markPending();
    } else {
      logger.error("Upload file part failed");
      if (!uploadResult.isRetryable) {
        await itemTask.markBlocked(
            'upload_${uploadResult.failureKind?.name ?? 'failed'}');
      }
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
      await itemTask.scheduleRetry('missing_file_metadata');
      return;
    }
    final parts = modelFile.parts;
    if (parts <= 0) {
      await itemTask.markBlocked('invalid_part_count');
      return;
    }
    final staging = DownloadStaging(
      baseDirectory: await getAppTempDirectory(),
      itemId: modelItem.id,
      fileHash: modelFile.id,
      partCount: parts,
      expectedPlaintextLength: modelItem.size,
    );
    final manifest = await staging.load();
    int? partToDownload;
    for (var part = 1; part <= parts; part++) {
      if (!manifest.completedParts.contains(part)) {
        partToDownload = part;
        break;
      }
    }

    if (partToDownload == null) {
      await _finalizeDownload(itemTask, modelItem, staging);
      return;
    }
    String fileHashPart = '${modelFile.id}_$partToDownload';
    ModelPart? modelPart = await ModelPart.get(fileHashPart);
    if (modelPart == null ||
        modelPart.cipher == null ||
        modelPart.nonce == null) {
      await itemTask.scheduleRetry('missing_part_metadata');
      return;
    }
    String downloadUrl = await getDownloadUrl(modelFile, partToDownload);
    if (downloadUrl.isNotEmpty) {
      logger.info("Fetched download authorization");
      final tempFile = staging.encryptedPart(partToDownload);
      final fileSink = tempFile.openWrite(mode: FileMode.write);
      final downloadResult = await downloadFileStream(
          url: downloadUrl, headers: null, fileOut: fileSink, onProgress: null);
      if (downloadResult.succeeded) {
        logger.info("Downloaded encrypted file part");
        final contentLength = await tempFile.length();
        final expectedSha1 = modelPart.data['sha1']?.toString();
        final actualSha1 = await _sha1ForFile(tempFile);
        final checksumMatches = expectedSha1 == null ||
            expectedSha1.isEmpty ||
            expectedSha1 == actualSha1;
        if (modelPart.size == contentLength && checksumMatches) {
          String keyCipherBase64 = modelPart.cipher!;
          String keyNonceBase64 = modelPart.nonce!;
          SodiumSumo sodium = await SodiumSumoInit.init();
          CryptoUtils cryptoUtils = CryptoUtils(sodium);
          String? masterKeyBase64 = await getMasterKey();
          if (masterKeyBase64 == null) {
            return;
          }
          Uint8List? fileEncryptionKeyBytes =
              cryptoUtils.getFileEncryptionKeyBytes(
                  keyCipherBase64, keyNonceBase64, masterKeyBase64);
          if (fileEncryptionKeyBytes != null) {
            final plainPartial = staging.plainPartPartial(partToDownload);
            ExecutionResult decryptionResult = await cryptoUtils.decryptFile(
                tempFile.path, plainPartial.path, fileEncryptionKeyBytes,
                writeMode: FileMode.write);
            if (decryptionResult.isSuccess) {
              logger.info("Decrypted file part");
              final readyPart = staging.readyPart(partToDownload);
              if (await readyPart.exists()) await readyPart.delete();
              await plainPartial.rename(readyPart.path);
              await staging.markComplete(manifest, partToDownload);
              itemTask.progress = (partToDownload * 100 ~/ parts).clamp(0, 100);
              await itemTask.update(["progress"]);
              if (manifest.completedParts.length == parts) {
                await _finalizeDownload(itemTask, modelItem, staging);
              } else {
                await itemTask.markPending();
              }
            } else {
              String error = decryptionResult.failureReason ?? "";
              logger.error("File part decryption failed", error: error);
            }
          }
        } else {
          logger.error("Downloaded file part integrity check failed");
        }
        if (await tempFile.exists()) await tempFile.delete();
      } else {
        final retry =
            downloadResult.isRetryable ? "retryable" : "non-retryable";
        logger.warning("Download failed ($retry); retaining metadata and task");
        if (!downloadResult.isRetryable) {
          await itemTask.markBlocked(
              'download_${downloadResult.failureKind?.name ?? 'failed'}');
        }
      }
    }
  }

  Future<void> _finalizeDownload(ModelItemTask itemTask, ModelItem modelItem,
      DownloadStaging staging) async {
    await staging.assemble();
    if (await staging.assembledFile.length() != modelItem.size ||
        !await _fileMatchesHash(staging.assembledFile, modelItem.fileHash!)) {
      await itemTask.markBlocked('download_integrity_mismatch');
      logger.error('Final download integrity check failed');
      return;
    }

    final finalFilePath = await ModelItem.getPathForItem(modelItem.id);
    await File(finalFilePath).parent.create(recursive: true);
    final finalFile = File(finalFilePath);
    if (await Directory(finalFilePath).exists()) {
      await itemTask.markBlocked('destination_conflict');
      return;
    }
    if (await finalFile.exists()) {
      if (await _fileMatchesHash(finalFile, modelItem.fileHash!)) {
        await ModelItemTask.completeTask(itemTask.id);
        await staging.cleanup();
      } else {
        await itemTask.markBlocked('destination_conflict');
      }
      return;
    }
    await moveFileSafely(staging.assembledFile.path, finalFilePath);
    if (!await finalFile.exists() ||
        !await _fileMatchesHash(finalFile, modelItem.fileHash!)) {
      throw const FileSystemException('Finalized download verification failed');
    }
    await ModelItemTask.completeTask(itemTask.id);
    await staging.cleanup();
  }

  static Future<String> _sha1ForFile(File file) async {
    return (await sha1.bind(file.openRead()).first).toString();
  }

  static Future<bool> _fileMatchesHash(File file, String expectedHash) async {
    final fileHashKey = await getFileHashKey();
    if (fileHashKey == null || !await file.exists()) return false;
    final sodium = await SodiumSumoInit.init();
    final secureKey = sodium.secureCopy(base64Decode(fileHashKey));
    try {
      final consumer = sodium.crypto.genericHash.createConsumer(
        key: secureKey,
        outLen: sodium.crypto.genericHash.bytes,
      );
      await file
          .openRead()
          .map(
              (chunk) => chunk is Uint8List ? chunk : Uint8List.fromList(chunk))
          .pipe(consumer);
      final digest = await consumer.hash;
      return base64UrlEncode(digest).replaceAll('=', '') == expectedHash;
    } finally {
      secureKey.dispose();
    }
  }

  static Future<String> getDownloadUrl(ModelFile modelFile, int part) async {
    final api = BackendApi();
    final storageProvider =
        StorageProviderExtension.fromValue(modelFile.providerId ?? 0);
    final providerPath = storageProvider.apiPath ?? 'b2';
    final downloadResult = await api.post(
      endpoint: '/$providerPath/get-download-url',
      jsonBody: {
        "storage_id": modelFile.storageId,
        "file_id": '${modelFile.id}_$part'
      },
      retryUnauthorized: true,
    );
    final status = downloadResult["success"];
    String downloadUrl = "";
    if (status > 0) {
      downloadUrl = downloadResult["data"];
    } else {
      logger.error("Failed to get download authorization");
    }
    return downloadUrl;
  }
}
