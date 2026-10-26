// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get localSessionCleanupTitle => 'Clearing local data';

  @override
  String get localSessionCleanupDescription =>
      'Your session has ended. FiFe needs to finish clearing its local account data before you can sign in again. Your original files are kept. Try again to finish.';

  @override
  String get localSessionCleanupInProgress =>
      'Clearing FiFe data from this device…';

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'By continuing, you agree to our $terms and $privacy.';
  }

  @override
  String get termsOfService => 'Terms of Service';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get andLabel => ' and ';

  @override
  String get theme => 'Theme';

  @override
  String get themeTooltip => 'Day/night theme';

  @override
  String get logging => 'Logging';

  @override
  String get appLockTitle => 'App lock';

  @override
  String get appLockDescription =>
      'Use your device’s fingerprint, face or PIN to protect FiFe.';

  @override
  String get appLockTimeout => 'Lock timeout';

  @override
  String get appLockTimeoutDescription =>
      'Require authentication after this much time away from FiFe. App restarts always require authentication.';

  @override
  String get appLockAuthenticate => 'Authenticate to unlock FiFe.';

  @override
  String get appLockChangeSettings =>
      'Authenticate to change App lock settings.';

  @override
  String get appLockAuthHint => 'Verify your identity';

  @override
  String get appLocked => 'FiFe is locked';

  @override
  String get appLockUnlock => 'Unlock';

  @override
  String get appLockUnavailable =>
      'Device authentication is unavailable. Set up a device PIN, passcode or biometrics in your device settings, then try again.';

  @override
  String get appLockAuthenticationFailed =>
      'Authentication was not completed. Try again.';

  @override
  String get appLockStorageError =>
      'App lock settings could not be read or saved. Retry to keep your vault protected.';

  @override
  String get quickSyncNotificationSettingTitle => 'Auto sync notification';

  @override
  String get autoSyncInterval => 'Auto sync interval';

  @override
  String get autoSyncIntervalDescription =>
      'Sync automatically while the auto sync notification is enabled.';

  @override
  String syncIntervalMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get autoSyncIntervalSaveError =>
      'Could not save the interval. Try again.';

  @override
  String get autoSyncIntervalApplyError =>
      'Interval saved. Turn the auto sync notification off and on to apply it.';

  @override
  String get sync => 'Sync';

  @override
  String get quickSyncNotificationTitle => 'File sync service';

  @override
  String quickSyncNotificationText(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Run every $minutes minutes',
      one: 'Run every 1 minute',
    );
    return '$_temp0';
  }

  @override
  String get quickSyncNotificationInProgress => 'In progress...';

  @override
  String get reportIssue => 'Report Issue';

  @override
  String get sourceCode => 'Source Code';

  @override
  String get desktopApp => 'Desktop App';

  @override
  String get mobileApp => 'Mobile App';

  @override
  String get leaveReview => 'Leave a review';

  @override
  String get share => 'Share';

  @override
  String get versionLabel => 'Version: ';

  @override
  String get loading => 'Loading...';

  @override
  String get signOut => 'Sign out';

  @override
  String get settingsPageTitle => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get tapToSelect => 'Tap to select';

  @override
  String get appTagline => 'Your Private Files Ferry';

  @override
  String get onboardingPurposeDescription =>
      'An open-source, cloud storage service built with zero-trust architecture. Your data is encrypted locally before it ever leaves your device.';

  @override
  String get failedToFetch => 'Failed to fetch.';

  @override
  String get supportedStorageTitle => 'Supported Storage';

  @override
  String get supportedStorageDescription =>
      'Connect your favorite providers. Start right away with FiFe\'s built-in 1 GB free secure storage.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Start backups instantly';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Free';

  @override
  String get providerStorageDisclaimer =>
      '* Free storage as mentioned on provider\'s website. Pay-as-you-go with compatible providers.';

  @override
  String get whyUseFifeTitle => 'Why Use FiFe?';

  @override
  String get claimFreeCloudStorageTitle => 'Claim Free Cloud Storage';

  @override
  String get claimFreeCloudStorageDescription =>
      'Maximize your space by connecting multiple cloud providers. Securely take advantage of their free storage tiers in one unified app.';

  @override
  String get topNotchSecurityTitle => 'Top-Notch Security';

  @override
  String get topNotchSecurityDescription =>
      'Powered by advanced Sodium cryptography. All encryption and decryption happens entirely locally on your device.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Maintain complete sovereignty over your data across all cloud storage providers. Keep encrypted storage using your own accounts.';

  @override
  String get payAsYouGoStorageTitle => 'Pay-as-you-go for storage.';

  @override
  String get payAsYouGoStorageDescription =>
      'Pay for used storage only with compatible providers. No middleman, no data lock-in.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Zero-Knowledge Privacy';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Your data is locked on your device before it ever leaves. We cannot see, read, or scan your files.';

  @override
  String get localSelectionTitle => '1. Local Selection';

  @override
  String get localSelectionDescription =>
      'You select a directory. All processing begins securely on your local device.';

  @override
  String get metadataEncryptionTitle => '2. Metadata Encryption';

  @override
  String get metadataEncryptionDescription =>
      'File information (titles, types, and sizes) is encrypted before being sent to the server.';

  @override
  String get contentEncryptionTitle => '3. Content Encryption';

  @override
  String get contentEncryptionDescription =>
      'The actual file content is fragmented and encrypted before uploading to cloud storage.';

  @override
  String get blindServerTitle => '4. Blind Server';

  @override
  String get blindServerDescription =>
      'Our servers have zero knowledge. We only see encrypted blobs, ensuring absolute privacy.';

  @override
  String get dontTrustVerifyTitle => 'Don\'t trust, verify.';

  @override
  String get openSourceVerificationDescription =>
      '100% Open Source. You can inspect the code to see exactly how your files are encrypted.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get next => 'Next';

  @override
  String get unauthorized => 'Unauthorized';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get errorTitle => 'Error';

  @override
  String get failureTitle => 'Failure';

  @override
  String get invalidWordList => 'Invalid word list';

  @override
  String get invalidAccessKey => 'Invalid access key';

  @override
  String get unexpectedDecryptionError =>
      'An unexpected error occurred during decryption.';

  @override
  String get fileMustContainExactly24Words =>
      'The file does not contain exactly 24 words.';

  @override
  String get errorReadingFile => 'Error reading file';

  @override
  String get encryptionTitle => 'Encryption';

  @override
  String get accessKeyDecodeDescription =>
      'Enter your 24-word recovery phrase or load a .txt file to securely enable cloud sync.';

  @override
  String get recoveryPhraseLabel => 'Recovery Phrase';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => 'Paste';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 words';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'Please enter your recovery phrase';

  @override
  String get mustContainExactly24Words => 'Must contain exactly 24 words';

  @override
  String get verify => 'Verify';

  @override
  String get orLabel => 'OR';

  @override
  String get loadFromTxtFile => 'Load from .txt File';

  @override
  String get saveAccessKey => 'Save Access Key';

  @override
  String get fileSavedSuccessfully => 'File saved successfully.';

  @override
  String get accessKeyShareMessage => 'Here is your access key.';

  @override
  String get pleaseTryAgain => 'Please try again.';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get accessKeyTitle => 'Access Key';

  @override
  String get accessKeyDescription =>
      'Please save this key in a secure place. Only this will allow you to access your encrypted data.';

  @override
  String get copy => 'Copy';

  @override
  String get downloadAsTextFile => 'Download as Text File';

  @override
  String get continueLabel => 'Continue';

  @override
  String get importantTitle => 'Important';

  @override
  String get accessKeyNoticePrimary =>
      'On the next page you\'ll see a series of 24 words. This is your unique and private encryption key and it is the ONLY way to recover your data in case of logout, device loss or malfunction.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'We do not store the key. It is YOUR responsibility to store it in a safe place outside of $appName app.';
  }

  @override
  String get showKeyConfirmation => 'I understand.\nShow me the key.';

  @override
  String get storageAddedSuccessfully => 'Storage added successfully';

  @override
  String get networkErrorDuringValidation =>
      'Network error occurred during validation.';

  @override
  String get verifyAndConnect => 'Verify & Connect';

  @override
  String get requiredField => 'Required';

  @override
  String get providerKeysVerifiedLocally =>
      'Your keys are verified locally and encrypted before transmission.';

  @override
  String get enterYourCredentials => 'Enter your credentials';

  @override
  String connectProvider(String provider) {
    return 'Connect $provider';
  }

  @override
  String get deviceLimitReached => 'Device limit reached';

  @override
  String get pleaseTryAgainWithExclamation => 'Please try again!';

  @override
  String get notThisDevice => 'Not this device!';

  @override
  String get confirmSignoutDeviceTitle => 'Confirm signout device';

  @override
  String get areYouSure => 'Are you sure?';

  @override
  String get cancel => 'Cancel';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'No device found';

  @override
  String get backTooltip => 'Back';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get longPressToDownload => 'Long press to download';

  @override
  String get fewItemsExistLocally => 'Few items exists locally.';

  @override
  String selectedItemsCount(int count) {
    return '$count Selected';
  }

  @override
  String get delete => 'Delete';

  @override
  String get info => 'Info';

  @override
  String get download => 'Download';

  @override
  String get archive => 'Archive';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Logs';

  @override
  String get settings => 'Settings';

  @override
  String get trash => 'Trash';

  @override
  String get storage => 'Storage';

  @override
  String get search => 'Search';

  @override
  String get database => 'Database';

  @override
  String get addFolderTitle => 'Add folder';

  @override
  String get confirm => 'Confirm';

  @override
  String get tapPlusToAddSyncFolder => 'Tap + to add sync folder.';

  @override
  String get thisFolderIsEmpty => 'This Folder is empty.';

  @override
  String get fileNotFound => 'File not found';

  @override
  String filePartsTitle(int count) {
    return 'File Parts ($count)';
  }

  @override
  String get fileDetailsTitle => 'File Details';

  @override
  String get encryptedBackup => 'Encrypted Backup';

  @override
  String get sizeLabel => 'Size';

  @override
  String get providerLabel => 'Provider';

  @override
  String get uploadedAtLabel => 'Uploaded At';

  @override
  String get statusLabel => 'Status';

  @override
  String get uploadedStatus => 'Uploaded';

  @override
  String errorWithMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get noLogsAvailable => 'No logs available';

  @override
  String get searchLogsHint => 'Search logs..';

  @override
  String get clearLogs => 'Clear logs';

  @override
  String get searchWithMinThreeCharacters => 'Search with min 3 characters';

  @override
  String get typeBelowToSearch => 'Type below to search';

  @override
  String get noResults => 'No results.';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String signInToContinue(String appName) {
    return 'Sign in to continue to $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Please enter your email';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Please enter a valid email address';

  @override
  String get emailAddressLabel => 'Email Address';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'Retry Sending OTP';

  @override
  String get sendOtp => 'Send OTP';

  @override
  String get checkYourEmail => 'Check your email';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'We\'ve sent a 6-digit code to\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Please enter the OTP';

  @override
  String get otpMustBeSixDigits => 'OTP must be 6 digits';

  @override
  String get enterOtpLabel => 'Enter OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Retry Verification';

  @override
  String get verifyOtp => 'Verify OTP';

  @override
  String get useDifferentEmail => 'Use a different email';

  @override
  String get alreadySignedIn => 'Already Signed In';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Sending OTP failed. Please try again!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'OTP verification failed. Please try again.';

  @override
  String get dbViewerTitle => 'DB Viewer';

  @override
  String get selectTableToViewData => 'Select a table to view its data';

  @override
  String get selectTable => 'Select a table';

  @override
  String get permissionRequiredTitle => 'Permission Required';

  @override
  String get storagePermissionSettingsDescription =>
      'To automatically back up, manage, and secure your files in the background, we need access to your device storage. Your data is encrypted locally, ensuring total privacy. Please allow access to continue.';

  @override
  String get openSettings => 'Open Settings';

  @override
  String get secureLocalAccessTitle => 'Secure Local Access';

  @override
  String get storagePermissionPageDescription =>
      'To explore, encrypt, and back up your files automatically, we need access to your device storage.';

  @override
  String get verifying => 'Verifying...';

  @override
  String get grantAccess => 'Grant Access';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Zero-knowledge encrypted storage';

  @override
  String get notificationPermissionTitle => 'Notifications Access';

  @override
  String get notificationPermissionPageDescription =>
      'To quickly sync and upload your files in the background from the notification panel, we need permission to show a notification. You may disable it anytime from the settings.';

  @override
  String get notificationPermissionGrantButton => 'Allow Notifications';

  @override
  String get notificationPermissionSettingsDescription =>
      'Notifications are required to provide you a quick sync utility via notification panel. Please enable them in the system settings to ensure your data is all uploaded.';

  @override
  String requiresAppPro(String appName) {
    return 'Requires $appName Pro.';
  }

  @override
  String get noStorageFound => 'No storage found';

  @override
  String get howToConnect => 'How to connect';

  @override
  String get modify => 'Modify';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total Used';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Up to $size free';
  }

  @override
  String get notConnected => 'Not connected';

  @override
  String get connect => 'Connect';

  @override
  String get modifyStorageCapacityTitle => 'Modify Storage Capacity';

  @override
  String get enterNewStorageLimitForProvider =>
      'Enter the new storage limit for this provider.';

  @override
  String get sizePrefix => 'Size: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Please enter a size';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Enter a valid number greater than 1';

  @override
  String get submit => 'Submit';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Successfully subscribed to $appName Pro!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Purchase cancelled or failed.';

  @override
  String get purchasesRestoredSuccessfully =>
      'Purchases restored successfully!';

  @override
  String get noActiveSubscriptionsFound => 'No active subscriptions found.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Please manage subscriptions in your device settings.';

  @override
  String get freePlanTitle => 'Free';

  @override
  String get freeForeverPrice => '\$0.00 / forever';

  @override
  String get freeBenefitProviderStorage => 'Enjoy free storage from providers';

  @override
  String get freeBenefitSyncThreeDevices => 'Sync up to 3 devices securely';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Yearly';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Modify storage limit for each provider';

  @override
  String get proBenefitSyncTenDevices => 'Sync up to 10 devices';

  @override
  String get restorePurchases => 'Restore Purchases';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Subscription is associated with email account, not the device';

  @override
  String get subscriptionExpiredTitle => 'Subscription Expired';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Your $appName Pro benefits have been paused. Renew below to restore your storage limits and device syncs.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro is Active';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Modify storage limits for each provider\n✓ Cross sync up to 10 devices';

  @override
  String get manageSubscription => 'Manage Subscription';

  @override
  String get currentPlanBadge => 'CURRENT';

  @override
  String get subscribeNow => 'Subscribe Now';

  @override
  String get subscribeOnMobileApp => 'Subscribe on mobile app';

  @override
  String get recover => 'Recover';

  @override
  String get empty => 'Empty';

  @override
  String get noItems => 'No items.';

  @override
  String get lostRecoveryPhrase => 'Lost recovery phrase';

  @override
  String get lostRecoveryIntro =>
      'If another device is still signed in, export your recovery phrase from it before starting over.';

  @override
  String get lostRecoveryDeleteConsequence =>
      'Your existing FiFe vault, backed-up files and old encryption keys will be permanently deleted.';

  @override
  String get lostRecoveryDevicesConsequence =>
      'All existing device registrations will be removed.';

  @override
  String get lostRecoveryLogoutConsequence =>
      'Other devices will sign out and clear their FiFe local data when they next discover their removal while online.';

  @override
  String get lostRecoveryKeepConsequence =>
      'Your email account, subscription, cloud storage connections and provider credentials will be kept. Files in your own folders outside FiFe will also be kept.';

  @override
  String get lostRecoveryWaitConsequence =>
      'Your new vault will stay locked until cloud deletion is verified. This may take 15 minutes or longer. You can close FiFe and resume later.';

  @override
  String get lostRecoveryNewPhraseConsequence =>
      'You stay signed in on this device. After deletion is verified, generate and save a new 24-word recovery phrase.';

  @override
  String get recoveryResetUnavailable =>
      'Vault reset is temporarily unavailable. Try again later.';

  @override
  String get recoveryResetSigninRequired =>
      'Sign in again to verify your session before resetting the vault.';

  @override
  String get recoveryResetContinue => 'Continue to reset';

  @override
  String get recoveryResetConfirmTitle => 'Permanently delete your FiFe vault?';

  @override
  String get recoveryResetConfirmBody =>
      'This cannot be undone. Your existing recovery phrase will stop working, and all your devices will be removed.';

  @override
  String get recoveryResetDelete => 'Delete vault and start fresh';

  @override
  String get recoveryResetPendingTitle => 'Deleting your previous vault';

  @override
  String get recoveryResetPendingBody =>
      'FiFe is verifying cloud deletion. You can close the app and return later.';

  @override
  String recoveryResetWaitUntil(String when) {
    return 'Verification cannot finish before $when.';
  }

  @override
  String get recoveryResetStorageBlocked =>
      'Cloud deletion needs attention. Restore access and deletion permissions for your linked storage, then try again.';

  @override
  String get recoveryResetSignin => 'Sign in again to resume this reset.';

  @override
  String recoveryResetSigninAs(String email) {
    return 'Sign in as $email to resume this reset.';
  }

  @override
  String get recoveryResetNeedsConfirmation =>
      'Confirm the reset to continue. FiFe will check whether it has already started.';

  @override
  String get recoveryResetConfirmationWait =>
      'A previous confirmation is still valid. Check again after it expires before starting a new confirmation.';

  @override
  String recoveryResetConfirmationUntil(String when) {
    return 'Check again after $when.';
  }

  @override
  String get recoveryResetMissingKeys =>
      'The new recovery keys are not available on this device. Continue on the device that started the reset. If those keys were lost, wait for deletion to finish, then sign in and choose “Lost recovery phrase” again.';

  @override
  String get recoveryResetDiscard => 'Return to sign-in';

  @override
  String get recoveryResetDiscardBody =>
      'This clears the unfinished recovery setup on this device. You will need the new recovery phrase or another vault reset after signing in.';

  @override
  String get recoveryPhraseSaved => 'I have saved my new recovery phrase.';

  @override
  String get recoveryResetStarting => 'Starting reset…';

  @override
  String get sessionExpiredRetained =>
      'Your sign-in session expired. Sign in again to unlock your vault. Your local data is kept.';

  @override
  String get signinVerifiedContinue =>
      'Your email is verified. Continue to finish signing in.';

  @override
  String get noSupportedApplication =>
      'No supported application to view this file.';

  @override
  String get fileAccessUnavailable =>
      'Unable to access this file. Check its folder permissions and try again.';

  @override
  String get unableToOpenFile => 'Unable to open this file. Please try again.';

  @override
  String get fileNotAvailable =>
      'This file is not available on this device or in a completed backup.';
}
