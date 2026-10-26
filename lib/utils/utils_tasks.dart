import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_vault_bb/models/model_file.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_part.dart';
import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:file_vault_bb/models/model_state.dart';
import 'package:file_vault_bb/services/service_backend.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_reconciliation_coordinator.dart';
import 'package:file_vault_bb/storage/local_item_access.dart';
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
import '../services/service_sync_budget.dart';
import '../services/service_session_work.dart';
import '../services/service_session_cleanup.dart';
import '../services/service_managed_upload.dart';
import '../storage/storage_sqlite.dart';
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
    return SessionWork.run(() => _init(retryWakeHandler: retryWakeHandler));
  }

  static Future<void> _init({Future<void> Function()? retryWakeHandler}) async {
    SyncBudget.check();
    if (await SecureStorage()
        .containsKey(key: AppString.recoveryResetStage.string)) {
      return;
    }
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

    _instance._syncCompleter = Completer<void>();

    // Clear history on a fresh start for accurate session estimates
    _instance._recentTaskDurationsMs.clear();

    // Fire and forget start, but block init() using the completer
    _instance.start(prepare: true);

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
  Future<void> start({bool prepare = false}) async {
    // Maintains running state in a flag to ignore start request if already running
    if (_isDispatching) return;
    if (SyncBudget.current?.interrupted == true) {
      _checkCompletion();
      return;
    }

    _isDispatching = true;

    try {
      if (prepare) {
        // Hold the dispatcher guard across cleanup/network and queue recovery.
        // A second sync start must join this run's existing completer.
        await ManagedUploadClient().drainCleanup();
        await ModelItemTask.recoverInterruptedTasks();
      }
      // An idle queue needs neither a network probe nor a transfer-sized
      // reserve. Keep blocked/future-retry work intact and schedule its wake.
      if (await ModelItemTask.fetchPendingTask(_activeTaskIds) == null) {
        await _scheduleNextRetryWake();
        _checkCompletion();
        return;
      }
      bool hasInternet = await InternetConnection().hasInternetAccess;
      SyncBudget.check();
      if (!hasInternet) {
        _waitForConnectivity();
        _checkCompletion();
        return;
      }
      await _cancelConnectivityWake();

      // Concurrency limits
      final maxConcurrentProcesses = SyncBudget.current != null
          ? 1
          : TransferConcurrencyPolicy.maxConcurrent(
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
        SyncBudget.check(reserve: const Duration(seconds: 5));

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
    } on SessionInvalidated {
      // Cleanup already canceled this session. Settle startup without querying
      // its cleared queue or scheduling a wake for the next signed-in account.
      _checkCompletion();
    } catch (e, s) {
      logger.error('Error in dispatcher', error: e.toString(), stackTrace: s);
      try {
        await _scheduleNextRetryWake();
      } on SessionInvalidated {
        // Revocation can also arrive while recovering from another failure.
      } finally {
        _checkCompletion();
      }
    } finally {
      // Release dispatcher lock so finishing processes can re-trigger it
      _isDispatching = false;
    }
  }

  /// Internal processor handling individual tasks
  Future<void> dispatchTask(String taskId) async {
    try {
      await SessionWork.run(() => _dispatchTask(taskId));
    } on SessionInvalidated {
      _activeTaskIds.remove(taskId);
      _checkCompletion();
    }
  }

  Future<void> _dispatchTask(String taskId) async {
    final DateTime taskStartTime = DateTime.now();
    String? failure;
    OperationLease? lease;
    var queueNext = true;
    try {
      SyncBudget.check(reserve: const Duration(seconds: 5));
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
      try {
        await lease?.release();
        final remainingTask = await ModelItemTask.get(taskId);
        if (remainingTask != null &&
            remainingTask.state == TransferTaskState.running) {
          if (SyncBudget.current?.interrupted == true) {
            await remainingTask.markInterrupted(SyncBudget.current!.reason);
          } else {
            await remainingTask.scheduleRetry(failure ?? 'transfer_incomplete');
          }
        }
      } catch (error, stackTrace) {
        logger.error('Transfer cleanup failed',
            error: error, stackTrace: stackTrace);
        if (_syncCompleter?.isCompleted == false) {
          _syncCompleter!.completeError(error, stackTrace);
        }
      }
      // Remove from active processes using the identifiable parameter
      _activeTaskIds.remove(taskId);

      final int individualTaskMs =
          DateTime.now().difference(taskStartTime).inMilliseconds;
      _recordTaskDuration(individualTaskMs);

      // Continue with other eligible tasks. Retry-waiting tasks remain persisted.
      if (queueNext &&
          SessionWork.active &&
          SyncBudget.current?.interrupted != true) {
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

  Future<void> _scheduleNextRetryWake({
    Duration minimumDelay = Duration.zero,
  }) async {
    if (SyncBudget.current != null) return;
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
    final dueDelay = retryWakeDelay(nextAttemptAt);
    final delay = dueDelay < minimumDelay ? minimumDelay : dueDelay;
    _retryWakeTimer = Timer(delay, () {
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
    if (SyncBudget.current != null) return;
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

  static Future<void> stopBackgroundWakes() async {
    _instance._cancelRetryWakeTimer();
    await _instance._cancelConnectivityWake();
    _instance._retryWakeHandler = null;
  }

  Future<void> _restartFromConnectivity() async {
    await _cancelConnectivityWake();
    await _restartFromWake();
  }

  Future<void> _restartFromWake() async {
    final revision = SessionWork.revision;
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
      // A wake can arrive before the earlier metadata pass releases its lease.
      // Recheck durable queued work after the handler, including that skipped
      // pass, without spinning on a past deadline or reviving an old session.
      if (SessionWork.active &&
          !SessionWork.authenticationRequired &&
          SessionWork.revision == revision) {
        await _scheduleNextRetryWake(minimumDelay: const Duration(seconds: 5));
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
    return LocalItemAccess.withAccess(
        modelItem.id,
        (inFilePath) =>
            _uploadFromAccessiblePath(itemTask, modelItem, inFilePath));
  }

  Future<bool> _uploadFromAccessiblePath(
      ModelItemTask itemTask, ModelItem modelItem, String inFilePath) async {
    final inFile = File(inFilePath);
    try {
      // exists() also returns false when access is denied. Only a genuine
      // not-found error may remove source metadata; other failures must retry.
      final source = await inFile.open(mode: FileMode.read);
      await source.close();
    } on FileSystemException catch (error) {
      final code = error.osError?.errorCode;
      if (code != 2 && !(Platform.isWindows && code == 3)) rethrow;
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
      // S3 authorization is object-scoped and needs the prepared ciphertext's
      // integrity values. Request it immediately before transfer below.
      uploadInfo["provider"] = "b2";
      uploadInfo["storage_id"] = modelFile.storageId;
    } else if (storageProvider.usesPresignedS3Url) {
      uploadInfo["provider"] = "s3";
      uploadInfo["provider_path"] = storageProvider.apiPath!;
      uploadInfo["storage_id"] = modelFile.storageId;
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
    final range =
        FileSplitter(file: File(inFilePath)).getStartEndIndexForPart(part);
    await _checkPartBudget('upload', range.end - range.start);
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
        SyncBudget.check();
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
    final modelFile = await ModelFile.get(fileHash);
    final partCount = modelFile?.parts ?? 1;
    var lastProgress = itemTask.progress;
    Future<void> onProgress(int sent, int total) async {
      final currentPartPercent = total <= 0 ? 100 : sent * 100 ~/ total;
      final overall =
          (((part - 1) * 100 + currentPartPercent) ~/ partCount).clamp(0, 99);
      if (overall <= lastProgress) return;
      lastProgress = overall;
      itemTask.progress = overall;
      await itemTask.update(["progress"]);
    }

    final transferWatch = Stopwatch()..start();
    final managedClient = ManagedUploadClient();
    final preparedPart = await ModelPart.get(fileHashPart);
    if (preparedPart == null) return true;
    final managed = await managedClient.transfer(
      part: fileHashPart,
      storageId: uploadInfo['storage_id'] as int,
      sha1: sha1Hash,
      md5: base64Encode((await md5.bind(encryptedFile.openRead()).first).bytes),
      size: contentLength,
      partMetadata: {
        'cipher': preparedPart.cipher,
        'nonce': preparedPart.nonce
      },
      send: (url, signedHeaders) => uploadFileStream(
          method: 'PUT',
          file: encryptedFile,
          url: url,
          headers: signedHeaders,
          onProgress: onProgress),
    );
    final existing = managed.existing;
    if (existing != null) {
      final acceptedPart = await ModelPart.fromServerMap(
          Map<String, dynamic>.from(existing['part'] as Map));
      final acceptedFile = await ModelFile.fromServerMap(
          Map<String, dynamic>.from(existing['file'] as Map));
      if (acceptedPart.id != fileHashPart ||
          acceptedFile.id != fileHash ||
          acceptedPart.uploaded != 1) {
        return true;
      }
      await StorageSqlite.instance.runInTransaction(() async {
        // Replace the abandoned local encryption key and its pending change
        // together; otherwise a later sync could overwrite the accepted key.
        await acceptedPart.upcertFromServer(overwrite: true);
        await StorageSqlite.instance
            .delete(Tables.changes.string, 'parts|$fileHashPart');
        final currentFile = await ModelFile.get(fileHash);
        if (currentFile != null) {
          currentFile.storageId = acceptedFile.storageId;
          currentFile.providerId = acceptedFile.providerId;
          if (acceptedFile.parts > 0) currentFile.parts = acceptedFile.parts;
          await currentFile.update(['storage_id', 'provider_id', 'parts']);
        }
      });
      if (managed.sent && transferWatch.elapsedMilliseconds > 0) {
        await _recordTransferRate(
            'upload', contentLength, transferWatch.elapsedMilliseconds);
      }
      if (existing['cleanupRequired'] == true) {
        await managedClient.abandon(fileHashPart);
      } else {
        await managedClient.forget(fileHashPart);
      }
      if (await encryptedFile.exists()) await encryptedFile.delete();
      await itemTask.markPending();
      return true;
    }
    if (managed.supported && managed.result == null) return true;
    if (!managed.supported &&
        uploadInfo["provider"] == "b2" &&
        uploadInfo["url"] == null) {
      final contentMd5 =
          base64Encode((await md5.bind(encryptedFile.openRead()).first).bytes);
      final result = await BackendApi().post(
        endpoint: '/b2/get-upload-url',
        jsonBody: {
          "storage_id": uploadInfo["storage_id"],
          "upload_protocol": "s3",
          "file_id": fileHashPart,
          "content_sha1": sha1Hash,
          "content_md5": contentMd5,
          "content_length": contentLength,
        },
        retryUnauthorized: true,
      );
      final descriptor = result["data"];
      if (result["success"] != 1 ||
          descriptor is! Map ||
          descriptor["uploadUrl"] is! String) {
        logger.warning('Unable to obtain B2 upload authorization');
        return true;
      }
      uploadInfo["url"] = descriptor["uploadUrl"];
      if (descriptor["protocol"] == "s3") {
        final signedHeaders = descriptor["headers"];
        if (descriptor["method"] != "PUT" ||
            signedHeaders is! Map ||
            signedHeaders.entries.any(
                (entry) => entry.key is! String || entry.value is! String)) {
          logger.warning('Invalid B2 S3 upload authorization');
          return true;
        }
        uploadInfo["protocol"] = "s3";
        uploadInfo["headers"] = Map<String, String>.from(signedHeaders);
      } else {
        // A backend predating S3 negotiation ignores the additional request
        // fields and returns the original native POST authorization.
        if (descriptor["authorizationToken"] is! String) return true;
        uploadInfo["token"] = descriptor["authorizationToken"];
      }
    }
    if (!managed.supported &&
        uploadInfo["provider"] == "s3" &&
        uploadInfo["url"] == null) {
      final providerPath = uploadInfo["provider_path"];
      final result = await BackendApi().post(
        endpoint: '/$providerPath/get-upload-url',
        jsonBody: {
          "storage_id": uploadInfo["storage_id"],
          "file_id": fileHashPart,
        },
        retryUnauthorized: true,
      );
      if (result["success"] != 1 || result["data"] is! String) {
        logger.warning('Unable to obtain S3 upload authorization');
        return true;
      }
      uploadInfo["url"] = result["data"];
    }
    String method = 'POST';
    if (!managed.supported &&
        uploadInfo["provider"] == "b2" &&
        uploadInfo["protocol"] == "s3") {
      method = 'PUT';
      headers = Map<String, String>.from(uploadInfo["headers"]);
    } else if (!managed.supported && uploadInfo["provider"] == "b2") {
      String? userId = await getSignedInUserId();
      final generation = ModelSetting.get(AppString.vaultGeneration.string);
      final prefix = generation.isEmpty || generation == 'legacy'
          ? '$userId/'
          : '$userId/vaults/$generation/';
      headers = {
        "authorization": uploadInfo["token"],
        "X-Bz-Content-Sha1": sha1Hash,
        "X-Bz-File-Name": Uri.encodeComponent('$prefix$fileHashPart'),
        "Content-Length": contentLength.toString(),
        "Content-Type": "application/octet-stream",
      };
    } else if (!managed.supported && uploadInfo["provider"] == "s3") {
      method = 'PUT';
      headers = {
        "Content-Length": contentLength.toString(),
        "Content-Type": "application/octet-stream",
      };
    }
    String uploadUrl = uploadInfo["url"] ?? '';
    logger.info("Uploading encrypted file part");
    UploadFileResult? uploadResult = managed.result;
    if (!managed.supported && uploadInfo["provider"] == "b2") {
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
    final needsUpload = managed.sent || uploadResult == null;
    uploadResult ??= await uploadFileStream(
        method: method,
        file: encryptedFile,
        url: uploadUrl,
        headers: headers,
        onProgress: onProgress);
    // update uploaded
    if (uploadResult.succeeded) {
      SyncBudget.check();
      final uploadedVersion = uploadResult.data["fileId"];
      if (uploadInfo["provider"] == "b2" &&
          (uploadedVersion is! String || uploadedVersion.isEmpty)) {
        // A committed upload whose version header was lost is reconciled on
        // the next attempt. Keep its ciphertext/key instead of losing identity.
        logger
            .warning('B2 upload version is missing; retaining retry artifact');
        return true;
      }
      if (needsUpload && transferWatch.elapsedMilliseconds > 0) {
        await _recordTransferRate(
            'upload', contentLength, transferWatch.elapsedMilliseconds);
      }
      logger.info("Encrypted file part uploaded");

      //update
      ModelPart? modelPart = await ModelPart.get(fileHashPart);
      if (modelPart == null) {
        if (managed.supported) await managedClient.abandon(fileHashPart);
        logger.error("PushFilePart", error: "file or part missing");
        return true;
      }
      modelPart.uploaded = 1;
      List<String> partAttrs = ["uploaded"];
      final partData = modelPart.data;
      if (managed.supported) {
        if (uploadResult.data['managedUploadId'] is String) {
          partData['managedUploadId'] = uploadResult.data['managedUploadId'];
        }
      } else {
        partData.remove('managedUploadId');
        partData.remove('managedObjectKey');
        partData['legacyUpload'] = true;
      }

      if (uploadResult.data.containsKey("fileId")) {
        String b2FileId = uploadResult.data["fileId"];
        partData["fileId"] = b2FileId;
      }
      modelPart.data = partData;
      partAttrs.add("data");
      await modelPart.update(partAttrs);
      if (managed.supported) await managedClient.forget(fileHashPart);
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
    SyncBudget.check(reserve: const Duration(seconds: 5));
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
    // Empty uploads legitimately contain no parts. They still go through
    // assembly, length/hash verification and scoped publication below.
    if (parts < 0 || (parts == 0 && modelItem.size != 0)) {
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
    await _checkPartBudget('download', modelPart.size);
    String downloadUrl = await getDownloadUrl(modelFile, partToDownload);
    if (downloadUrl.isNotEmpty) {
      logger.info("Fetched download authorization");
      final tempFile = staging.encryptedPart(partToDownload);
      final fileSink = tempFile.openWrite(mode: FileMode.write);
      final transferWatch = Stopwatch()..start();
      final downloadResult = await downloadFileStream(
          url: downloadUrl, headers: null, fileOut: fileSink, onProgress: null);
      if (downloadResult.succeeded) {
        SyncBudget.check();
        logger.info("Downloaded encrypted file part");
        final contentLength = await tempFile.length();
        final transferMilliseconds = transferWatch.elapsedMilliseconds;
        final expectedSha1 = modelPart.data['sha1']?.toString();
        final actualSha1 = await _sha1ForFile(tempFile);
        final checksumMatches = expectedSha1 == null ||
            expectedSha1.isEmpty ||
            expectedSha1 == actualSha1;
        if (modelPart.size == contentLength && checksumMatches) {
          await _recordTransferRate(
              'download', contentLength, transferMilliseconds);
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
              SyncBudget.check();
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
    SyncBudget.check();
    await staging.assemble();
    if (await staging.assembledFile.length() != modelItem.size ||
        !await _fileMatchesHash(staging.assembledFile, modelItem.fileHash!)) {
      await itemTask.markBlocked('download_integrity_mismatch');
      logger.error('Final download integrity check failed');
      return;
    }

    await LocalItemAccess.withAccess(
        modelItem.id,
        (finalFilePath) =>
            _publishDownload(itemTask, modelItem, staging, finalFilePath));
  }

  Future<void> _publishDownload(ModelItemTask itemTask, ModelItem modelItem,
      DownloadStaging staging, String finalFilePath) async {
    final published = await SessionCleanup.instance.withPublication(() async {
      SyncBudget.check();
      await File(finalFilePath).parent.create(recursive: true);
      final finalFile = File(finalFilePath);
      if (await Directory(finalFilePath).exists()) return false;
      if (await finalFile.exists()) {
        return _fileMatchesHash(finalFile, modelItem.fileHash!);
      }
      await moveFileSafely(staging.assembledFile.path, finalFilePath);
      if (!await finalFile.exists() ||
          !await _fileMatchesHash(finalFile, modelItem.fileHash!)) {
        throw const FileSystemException(
            'Finalized download verification failed');
      }
      return true;
    });
    // Account writes happen only after releasing the publication gate. Cleanup
    // can now invalidate them without leaving an uncompleted filesystem move.
    if (!published) {
      await itemTask.markBlocked('destination_conflict');
      return;
    }
    await ModelItemTask.completeTask(itemTask.id);
    await staging.cleanup();
  }

  static Future<String> _sha1ForFile(File file) async {
    return (await sha1.bind(SyncBudget.guardStream(file.openRead())).first)
        .toString();
  }

  static Future<void> _checkPartBudget(String direction, int bytes) async {
    if (SyncBudget.current == null) return;
    final rate =
        int.tryParse(await ModelState.get('background_${direction}_rate'));
    SyncBudget.check(
        reserve: const Duration(seconds: 5) +
            TransferConcurrencyPolicy.estimatePartDuration(bytes,
                observedBytesPerSecond: rate));
  }

  static Future<void> _recordTransferRate(
      String direction, int bytes, int milliseconds) async {
    if (bytes <= 0 || milliseconds <= 0) return;
    SyncBudget.check();
    await ModelState.set('background_${direction}_rate',
        (bytes * 1000 ~/ milliseconds).toString());
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
      await SyncBudget.guardStream(file.openRead())
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
