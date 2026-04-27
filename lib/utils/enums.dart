enum SetupStep {
  loading,
  onboard,
  signin,
  checkAccessKey,
  generateAccessKey,
  decodeAccessKey,
  showAccessKey,
  registerDevice,
  manageDevices,
  storagePermission,
  explorer,
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
  itemTasks
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
      case Tables.itemTasks:
        return "item_tasks";
    }
  }
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

enum AppString {
  // app
  appName,
  onboarding,
  deviceUuid,
  deviceHash,
  fcmId,
  installedAt,
  reviewDialogShown,
  deviceRegistered,
  loggingEnabled,
  simulateTesting,
  theme,

  //sign-in
  signedIn,
  otpSentTo,
  otpSentAt,
  jwtToken,
  sessionCookie,

  // Recon
  lastReconRunningAt,

  // Sync
  encryptionKeyType,
  hasEncryptionKeys,
  lastSyncRunningAt,
  pushedLocalContentForSync,
  lastChangeTS,
  lastProfileTS,
  lastFileTS,
  lastItemTS,
  lastPartTS,
  hideSyncButton,

  // Cipher
  masterKey,
  accessKey,
  serverKeys,
  privateKeys,
  fileHashKey,
  fileHashKeyContext,
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
      case AppString.sessionCookie:
        return "session_cookie";
      case AppString.jwtToken:
        return "jwt_token";
      case AppString.fileHashKeyContext:
        return "FileHash";
      case AppString.fileHashKey:
        return "file_hash_key";
      case AppString.lastReconRunningAt:
        return "last_recon_running_at";
      case AppString.theme:
        return "theme";
      case AppString.onboarding:
        return "onboarding";
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
      case AppString.loggingEnabled:
        return "logging_enabled";
      case AppString.lastSyncRunningAt:
        return "sync_running_at";
      case AppString.fcmId:
        return "fcm_id";
      case AppString.encryptionKeyType:
        return "encryption_key_type";
      case AppString.hasEncryptionKeys:
        return "has_encryption_keys";
      case AppString.pushedLocalContentForSync:
        return 'pushed_local_content_for_sync';
      case AppString.deviceRegistered:
        return "device_registered";
      case AppString.appName:
        return "FiFe";
      case AppString.reviewDialogShown:
        return "review_dialog_shown";
      case AppString.installedAt:
        return "installed_at";
      case AppString.deviceUuid:
        return "device_id";
      case AppString.deviceHash:
        return "device_hash";
      case AppString.lastChangeTS:
        return "last_changes_fetched_at";
      case AppString.lastProfileTS:
        return "last_profile_ts";
      case AppString.lastFileTS:
        return "last_file_ts";
      case AppString.lastItemTS:
        return "last_item_ts";
      case AppString.lastPartTS:
        return "last_part_ts";
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

enum StorageProvider {
  none,
  fife,
  backblaze,
  cloudflare,
  oracle,
  idrive,
  local
}

extension StorageProviderExtension on StorageProvider {
  int get value {
    switch (this) {
      case StorageProvider.none:
        return 0;
      case StorageProvider.fife:
        return 1;
      case StorageProvider.backblaze:
        return 2;
      case StorageProvider.cloudflare:
        return 3;
      case StorageProvider.oracle:
        return 4;
      case StorageProvider.idrive:
        return 5;
      case StorageProvider.local:
        return 99;
    }
  }

  static String stringFromInt(int value) {
    switch (value) {
      case 0:
        return "Unknown";
      case 1:
        return "FiFe";
      case 2:
        return "BackBlaze B2";
      case 3:
        return "CloudFlare R2";
      case 4:
        return "Oracle Object Storage";
      case 5:
        return "IDrive E2";
      case 99:
        return "Local";
      default:
        return "Unknown";
    }
  }

  static StorageProvider fromValue(int value) {
    switch (value) {
      case 1:
        return StorageProvider.fife;
      case 2:
        return StorageProvider.backblaze;
      case 3:
        return StorageProvider.cloudflare;
      case 4:
        return StorageProvider.oracle;
      case 5:
        return StorageProvider.idrive;
      default:
        return StorageProvider.none;
    }
  }
}

enum ItemTask { none, upload, download }

extension ItemTaskExtension on ItemTask {
  int get value {
    switch (this) {
      case ItemTask.none:
        return 0;
      case ItemTask.upload:
        return 1;
      case ItemTask.download:
        return 2;
    }
  }
}
