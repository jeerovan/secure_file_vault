enum SetupStep {
  loading,
  signin,
  checkAccessKey,
  generateAccessKey,
  decodeAccessKey,
  showAccessKey,
  registerDevice,
  manageDevices,
  storagePermission,
  /* planSelection, */
  complete,
}

enum Tables {
  profiles,
  items,
  files,
  parts,
  changes,
  settings,
  states,
  logs,
  transfers
}

extension TablesExtension on Tables {
  String get string {
    switch (this) {
      case Tables.profiles:
        return "profiles";
      case Tables.items:
        return "items";
      case Tables.files:
        return "files";
      case Tables.parts:
        return "parts";
      case Tables.changes:
        return "changes";
      case Tables.settings:
        return "settings";
      case Tables.states:
        return "states";
      case Tables.logs:
        return "logs";
      case Tables.transfers:
        return "transfers";
    }
  }
}

enum PageType {
  settings,
  categories,
  addEditCategory,
  addEditGroup,
  items,
  editNote,
  archive,
  starred,
  search,
  mediaViewer,
  userTask,
  planStatus,
  planSubscribe,
  signIn,
  selectKeyType,
  accessKey,
  accessKeyInput,
  accessKeyCreate,
  passwordInput,
  passwordCreate,
  devices,
}

enum ExecutionStatus {
  failure,
  success,
}

enum ExecutionMode {
  appForeground,
  appBackground,
  fcmBackground,
}

extension ExecutionModeExtension on ExecutionMode {
  String get string {
    switch (this) {
      case ExecutionMode.appForeground:
        return "AppForground";
      case ExecutionMode.appBackground:
        return "AppBackground";
      case ExecutionMode.fcmBackground:
        return "FcmBackground";
    }
  }
}

enum AppTask {
  registerDevice,
  checkEncryptionKeys,
  pushLocalContent,
  checkCloudSync,
  signOut,
}

enum AppString {
  // app
  appName,
  deviceId,
  fcmId,
  installedAt,
  reviewDialogShown,
  deviceRegistered,
  loggingEnabled,
  dataSeeded,
  simulateTesting,

  // Supabase
  supabaseInitialized,

  // RevenueCat
  hasValidPlan,
  planStorageFull,
  planRcId,

  //sign-in
  signedIn,
  otpSentTo,
  otpSentAt,

  // Sync
  encryptionKeyType,
  hasEncryptionKeys,
  syncInProgress,
  pushedLocalContentForSync,
  lastChangesFetchedAt,
  lastProfilesChangesFetchedAt,
  lastFilesChangesFetchedAt,
  lastItemsChangesFetchedAt,
  lastPartsChangesFetchedAt,
  hideSyncButton,

  // Cipher
  masterKey,
  accessKey,
  serverKeys,
  privateKeys,
  key,
  cipher,
  nonce,
  encrypted,
  decrypted,
  keyCipher,
  keyNonce,
  textCipher,
  textNonce,
  debugCipherData,

  // API
  tableMaps,
}

extension AppStringExtension on AppString {
  String get string {
    switch (this) {
      case AppString.tableMaps:
        return "table_maps";
      case AppString.serverKeys:
        return 'server_keys';
      case AppString.privateKeys:
        return 'private_keys';
      case AppString.masterKey:
        return 'master_key';
      case AppString.accessKey:
        return 'access_key';
      case AppString.cipher:
        return 'cipher';
      case AppString.hideSyncButton:
        return "hide_sync_button";
      case AppString.simulateTesting:
        return "simulate_testing";
      case AppString.signedIn:
        return "signed_in";
      case AppString.dataSeeded:
        return "data_seeded";
      case AppString.loggingEnabled:
        return "logging_enabled";
      case AppString.planRcId:
        return "plan_rc_id";
      case AppString.supabaseInitialized:
        return "supabase_initialized";
      case AppString.syncInProgress:
        return "sync_in_progress";
      case AppString.fcmId:
        return "fcm_id";
      case AppString.encryptionKeyType:
        return "encryption_key_type";
      case AppString.hasEncryptionKeys:
        return "has_encryption_keys";
      case AppString.pushedLocalContentForSync:
        return 'pushed_local_content_for_sync';
      case AppString.hasValidPlan:
        return 'has_valid_plan';
      case AppString.planStorageFull:
        return 'rc_plan_full';
      case AppString.deviceRegistered:
        return "device_registered";
      case AppString.appName:
        return "FiFe";
      case AppString.reviewDialogShown:
        return "review_dialog_shown";
      case AppString.installedAt:
        return "installed_at";
      case AppString.deviceId:
        return "device_id";
      case AppString.lastChangesFetchedAt:
        return "last_changes_fetched_at";
      case AppString.lastProfilesChangesFetchedAt:
        return "last_profiles_changes_fetched_at";
      case AppString.lastFilesChangesFetchedAt:
        return "last_files_changes_fetched_at";
      case AppString.lastItemsChangesFetchedAt:
        return "last_items_changes_fetched_at";
      case AppString.lastPartsChangesFetchedAt:
        return "last_parts_changes_fetched_at";
      case AppString.otpSentTo:
        return "otp_sent_to";
      case AppString.otpSentAt:
        return "otp_sent_at";
      case AppString.keyCipher:
        return "key_cipher";
      case AppString.keyNonce:
        return "key_nonce";
      case AppString.textCipher:
        return "text_cipher";
      case AppString.textNonce:
        return "text_nonce";
      case AppString.key:
        return "key";
      case AppString.nonce:
        return "nonce";
      case AppString.encrypted:
        return "encrypted";
      case AppString.decrypted:
        return "decrypted";
      case AppString.debugCipherData:
        return "debug_cipher_data";
    }
  }
}

enum SyncChangeTask {
  delete,
  pushMap,
  pushMapFile,
  pushFile,

  fetchFile, // requires only file

  pushMapDeleteFile,
  deleteFile,
}

extension SyncChangeTaskExtension on SyncChangeTask {
  int get value {
    switch (this) {
      case SyncChangeTask.delete:
        return 10;
      case SyncChangeTask.pushMap:
        return 20;
      case SyncChangeTask.pushFile:
        return 30;
      case SyncChangeTask.pushMapFile:
        return 40;
      case SyncChangeTask.fetchFile:
        return 50;
      case SyncChangeTask.pushMapDeleteFile:
        return 60;
      case SyncChangeTask.deleteFile:
        return 70;
    }
  }

  static SyncChangeTask? fromValue(int value) {
    switch (value) {
      case 10:
        return SyncChangeTask.delete;
      case 20:
        return SyncChangeTask.pushMap;
      case 30:
        return SyncChangeTask.pushFile;
      case 40:
        return SyncChangeTask.pushMapFile;
      case 50:
        return SyncChangeTask.fetchFile;
      case 60:
        return SyncChangeTask.pushMapDeleteFile;
      case 70:
        return SyncChangeTask.deleteFile;
      default:
        return null;
    }
  }
}

enum SyncState {
  initial,
  uploading,
  uploaded,
  downloading,
  downloaded,
  downloadable, // mark only when file is available to download (fully uploaded on server from other device),
}

extension SyncStateExtension on SyncState {
  int get value {
    switch (this) {
      case SyncState.initial:
        return 0;
      case SyncState.uploading:
        return 10;
      case SyncState.uploaded:
        return 20;
      case SyncState.downloading:
        return 30;
      case SyncState.downloaded:
        return 40;
      case SyncState.downloadable:
        return 50;
    }
  }

  static SyncState? fromValue(int value) {
    switch (value) {
      case 0:
        return SyncState.initial;
      case 10:
        return SyncState.uploading;
      case 20:
        return SyncState.uploaded;
      case 30:
        return SyncState.downloading;
      case 40:
        return SyncState.downloaded;
      case 50:
        return SyncState.downloadable;
      default:
        return null;
    }
  }
}

enum ScanState {
  initial,
  exists,
  modified,
}

extension ScanStateExtension on ScanState {
  int get value {
    switch (this) {
      case ScanState.initial:
        return 0;
      case ScanState.exists:
        return 1;
      case ScanState.modified:
        return 2;
    }
  }

  static ScanState? fromValue(int value) {
    switch (value) {
      case 0:
        return ScanState.initial;
      case 1:
        return ScanState.exists;
      case 2:
        return ScanState.modified;
    }
    return null;
  }
}
