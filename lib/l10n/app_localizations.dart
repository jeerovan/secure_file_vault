import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_el.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fa.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_he.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_id.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_nl.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_th.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_uk.dart';
import 'app_localizations_vi.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('el'),
    Locale('en'),
    Locale('es'),
    Locale('fa'),
    Locale('fr'),
    Locale('he'),
    Locale('hi'),
    Locale('id'),
    Locale('it'),
    Locale('ja'),
    Locale('ko'),
    Locale('nl'),
    Locale('pt'),
    Locale('ru'),
    Locale('th'),
    Locale('tr'),
    Locale('uk'),
    Locale('vi'),
    Locale('zh')
  ];

  /// App title
  ///
  /// In en, this message translates to:
  /// **'FiFe'**
  String get appTitle;

  /// Consent text shown before continuing, with clickable Terms of Service and Privacy Policy links
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our {terms} and {privacy}.'**
  String continueAgreementText(String terms, String privacy);

  /// Clickable label for the terms of service link
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfService;

  /// Clickable label for the privacy policy link
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// Connector text between terms and privacy policy
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get andLabel;

  /// The label for the theme selection option in settings
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// Tooltip for the theme toggle button
  ///
  /// In en, this message translates to:
  /// **'Day/night theme'**
  String get themeTooltip;

  /// The label for the system logging configuration
  ///
  /// In en, this message translates to:
  /// **'Logging'**
  String get logging;

  /// Action to navigate to the issue tracker
  ///
  /// In en, this message translates to:
  /// **'Report Issue'**
  String get reportIssue;

  /// Link to the project source code repository
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCode;

  /// Information for users on desktop platforms
  ///
  /// In en, this message translates to:
  /// **'Desktop App'**
  String get desktopApp;

  /// Information for users on mobile platforms
  ///
  /// In en, this message translates to:
  /// **'Mobile App'**
  String get mobileApp;

  /// Call to action to leave a store rating
  ///
  /// In en, this message translates to:
  /// **'Leave a review'**
  String get leaveReview;

  /// Option to share the application link with others
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Static prefix for the current version number display
  ///
  /// In en, this message translates to:
  /// **'Version: '**
  String get versionLabel;

  /// Status shown while fetching package information
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Button text to log out the user
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// Main title for the settings screen bottom bar
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsPageTitle;

  /// Label for selecting the app language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Prompt text instructing the user to tap and choose an option
  ///
  /// In en, this message translates to:
  /// **'Tap to select'**
  String get tapToSelect;

  /// Tagline displayed below the app name on the onboarding page
  ///
  /// In en, this message translates to:
  /// **'Your Private Files Ferry'**
  String get appTagline;

  /// Description explaining the app purpose on the onboarding welcome page
  ///
  /// In en, this message translates to:
  /// **'An open-source, cloud storage service built with zero-trust architecture. Your data is encrypted locally before it ever leaves your device.'**
  String get onboardingPurposeDescription;

  /// Error message shown when storage providers fail to load
  ///
  /// In en, this message translates to:
  /// **'Failed to fetch.'**
  String get failedToFetch;

  /// Title for the onboarding page listing supported storage providers
  ///
  /// In en, this message translates to:
  /// **'Supported Storage'**
  String get supportedStorageTitle;

  /// Description for the supported storage onboarding page
  ///
  /// In en, this message translates to:
  /// **'Connect your favorite providers. Start right away with FiFe\'s built-in 1 GB free secure storage.'**
  String get supportedStorageDescription;

  /// Name of the default FiFe storage provider card
  ///
  /// In en, this message translates to:
  /// **'FiFe Cloud'**
  String get fifeCloud;

  /// Subtitle for the default FiFe cloud storage card
  ///
  /// In en, this message translates to:
  /// **'Start backups instantly'**
  String get startBackupsInstantly;

  /// Displayed free storage size for the built-in FiFe cloud
  ///
  /// In en, this message translates to:
  /// **'1.0 GB'**
  String get freeStorageSizeOneGb;

  /// Label indicating a storage plan is free
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freeLabel;

  /// Disclaimer about provider free storage and pay-as-you-go support
  ///
  /// In en, this message translates to:
  /// **'* Free storage as mentioned on provider\'s website. Pay-as-you-go with compatible providers.'**
  String get providerStorageDisclaimer;

  /// Title for the onboarding benefits page
  ///
  /// In en, this message translates to:
  /// **'Why Use FiFe?'**
  String get whyUseFifeTitle;

  /// Benefit title about using free cloud storage from multiple providers
  ///
  /// In en, this message translates to:
  /// **'Claim Free Cloud Storage'**
  String get claimFreeCloudStorageTitle;

  /// Benefit description about aggregating free storage across providers
  ///
  /// In en, this message translates to:
  /// **'Maximize your space by connecting multiple cloud providers. Securely take advantage of their free storage tiers in one unified app.'**
  String get claimFreeCloudStorageDescription;

  /// Benefit title highlighting strong security
  ///
  /// In en, this message translates to:
  /// **'Top-Notch Security'**
  String get topNotchSecurityTitle;

  /// Benefit description explaining local encryption and decryption
  ///
  /// In en, this message translates to:
  /// **'Powered by advanced Sodium cryptography. All encryption and decryption happens entirely locally on your device.'**
  String get topNotchSecurityDescription;

  /// Benefit title for bring your own key support
  ///
  /// In en, this message translates to:
  /// **'Bring Your Own Key (BYOK)'**
  String get bringYourOwnKeyTitle;

  /// Benefit description for using your own accounts and keys
  ///
  /// In en, this message translates to:
  /// **'Maintain complete sovereignty over your data across all cloud storage providers. Keep encrypted storage using your own accounts.'**
  String get bringYourOwnKeyDescription;

  /// Benefit title for pay-as-you-go storage support
  ///
  /// In en, this message translates to:
  /// **'Pay-as-you-go for storage.'**
  String get payAsYouGoStorageTitle;

  /// Benefit description for pay-as-you-go compatible providers
  ///
  /// In en, this message translates to:
  /// **'Pay for used storage only with compatible providers. No middleman, no data lock-in.'**
  String get payAsYouGoStorageDescription;

  /// Title for the onboarding security page
  ///
  /// In en, this message translates to:
  /// **'Zero-Knowledge Privacy'**
  String get zeroKnowledgePrivacyTitle;

  /// Subtitle describing zero-knowledge privacy guarantees
  ///
  /// In en, this message translates to:
  /// **'Your data is locked on your device before it ever leaves. We cannot see, read, or scan your files.'**
  String get zeroKnowledgePrivacyDescription;

  /// Step title for local file selection in the security flow
  ///
  /// In en, this message translates to:
  /// **'1. Local Selection'**
  String get localSelectionTitle;

  /// Step description for local file selection in the security flow
  ///
  /// In en, this message translates to:
  /// **'You select a directory. All processing begins securely on your local device.'**
  String get localSelectionDescription;

  /// Step title for metadata encryption in the security flow
  ///
  /// In en, this message translates to:
  /// **'2. Metadata Encryption'**
  String get metadataEncryptionTitle;

  /// Step description for metadata encryption in the security flow
  ///
  /// In en, this message translates to:
  /// **'File information (titles, types, and sizes) is encrypted before being sent to the server.'**
  String get metadataEncryptionDescription;

  /// Step title for file content encryption in the security flow
  ///
  /// In en, this message translates to:
  /// **'3. Content Encryption'**
  String get contentEncryptionTitle;

  /// Step description for file content encryption in the security flow
  ///
  /// In en, this message translates to:
  /// **'The actual file content is fragmented and encrypted before uploading to cloud storage.'**
  String get contentEncryptionDescription;

  /// Step title for the zero-knowledge server step in the security flow
  ///
  /// In en, this message translates to:
  /// **'4. Blind Server'**
  String get blindServerTitle;

  /// Step description explaining that servers only handle encrypted data
  ///
  /// In en, this message translates to:
  /// **'Our servers have zero knowledge. We only see encrypted blobs, ensuring absolute privacy.'**
  String get blindServerDescription;

  /// Title for the open-source verification callout
  ///
  /// In en, this message translates to:
  /// **'Don\'t trust, verify.'**
  String get dontTrustVerifyTitle;

  /// Description for the open-source verification callout
  ///
  /// In en, this message translates to:
  /// **'100% Open Source. You can inspect the code to see exactly how your files are encrypted.'**
  String get openSourceVerificationDescription;

  /// Primary button label shown on the final onboarding page
  ///
  /// In en, this message translates to:
  /// **'Get Started'**
  String get getStarted;

  /// Primary button label used to move to the next onboarding page
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Error message shown when the user is not authorized to access the key
  ///
  /// In en, this message translates to:
  /// **'Unauthorized'**
  String get unauthorized;

  /// Button label used to retry the failed access key check
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// Generic error dialog title
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorTitle;

  /// Dialog title shown when access key verification fails
  ///
  /// In en, this message translates to:
  /// **'Failure'**
  String get failureTitle;

  /// Error message shown when the entered recovery phrase is not a valid mnemonic
  ///
  /// In en, this message translates to:
  /// **'Invalid word list'**
  String get invalidWordList;

  /// Error message shown when the provided recovery phrase cannot decrypt the stored key
  ///
  /// In en, this message translates to:
  /// **'Invalid access key'**
  String get invalidAccessKey;

  /// Error message shown when an unexpected exception occurs during access key decryption
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred during decryption.'**
  String get unexpectedDecryptionError;

  /// Error message shown when the selected text file does not contain exactly 24 words
  ///
  /// In en, this message translates to:
  /// **'The file does not contain exactly 24 words.'**
  String get fileMustContainExactly24Words;

  /// Snackbar message shown when reading the selected file fails
  ///
  /// In en, this message translates to:
  /// **'Error reading file'**
  String get errorReadingFile;

  /// App bar title for the access key decode screen
  ///
  /// In en, this message translates to:
  /// **'Encryption'**
  String get encryptionTitle;

  /// Instruction text on the access key decode screen
  ///
  /// In en, this message translates to:
  /// **'Enter your 24-word recovery phrase or load a .txt file to securely enable cloud sync.'**
  String get accessKeyDecodeDescription;

  /// Label for the recovery phrase input field
  ///
  /// In en, this message translates to:
  /// **'Recovery Phrase'**
  String get recoveryPhraseLabel;

  /// Hint text shown inside the recovery phrase input field
  ///
  /// In en, this message translates to:
  /// **'word1 word2 word3...'**
  String get recoveryPhraseHint;

  /// Button label used to paste clipboard text into the recovery phrase field
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// Live counter showing how many recovery words have been entered
  ///
  /// In en, this message translates to:
  /// **'{count} / 24 words'**
  String wordCountLabel(int count);

  /// Validation message shown when the recovery phrase field is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter your recovery phrase'**
  String get pleaseEnterRecoveryPhrase;

  /// Validation message shown when the recovery phrase does not contain exactly 24 words
  ///
  /// In en, this message translates to:
  /// **'Must contain exactly 24 words'**
  String get mustContainExactly24Words;

  /// Primary button label used to verify the recovery phrase
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// Separator label between manual input and file upload actions
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get orLabel;

  /// Button label used to load the recovery phrase from a text file
  ///
  /// In en, this message translates to:
  /// **'Load from .txt File'**
  String get loadFromTxtFile;

  /// Title for the desktop save file dialog when saving the access key
  ///
  /// In en, this message translates to:
  /// **'Save Access Key'**
  String get saveAccessKey;

  /// Snackbar message shown after the access key file is saved successfully
  ///
  /// In en, this message translates to:
  /// **'File saved successfully.'**
  String get fileSavedSuccessfully;

  /// Text shared alongside the access key file in the mobile share sheet
  ///
  /// In en, this message translates to:
  /// **'Here is your access key.'**
  String get accessKeyShareMessage;

  /// Generic snackbar message shown after a failed file save or share operation
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get pleaseTryAgain;

  /// Snackbar message shown after copying the access key to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// App bar title for the access key screen
  ///
  /// In en, this message translates to:
  /// **'Access Key'**
  String get accessKeyTitle;

  /// Instruction text explaining the importance of safely storing the access key
  ///
  /// In en, this message translates to:
  /// **'Please save this key in a secure place. Only this will allow you to access your encrypted data.'**
  String get accessKeyDescription;

  /// Button label used to copy the access key to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Button label used to save the access key as a text file
  ///
  /// In en, this message translates to:
  /// **'Download as Text File'**
  String get downloadAsTextFile;

  /// Button label used to proceed to the next step after viewing the access key
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// App bar title for the access key notice screen
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get importantTitle;

  /// Primary warning text explaining the importance of the 24-word recovery key
  ///
  /// In en, this message translates to:
  /// **'On the next page you\'ll see a series of 24 words. This is your unique and private encryption key and it is the ONLY way to recover your data in case of logout, device loss or malfunction.'**
  String get accessKeyNoticePrimary;

  /// Warning text reminding the user to store the recovery key outside the app
  ///
  /// In en, this message translates to:
  /// **'We do not store the key. It is YOUR responsibility to store it in a safe place outside of {appName} app.'**
  String accessKeyNoticeResponsibility(String appName);

  /// Confirmation button label acknowledging the warning before showing the access key
  ///
  /// In en, this message translates to:
  /// **'I understand.\nShow me the key.'**
  String get showKeyConfirmation;

  /// Snackbar message shown when a storage provider is added successfully
  ///
  /// In en, this message translates to:
  /// **'Storage added successfully'**
  String get storageAddedSuccessfully;

  /// Error message shown when provider validation fails because of a network error
  ///
  /// In en, this message translates to:
  /// **'Network error occurred during validation.'**
  String get networkErrorDuringValidation;

  /// Primary button label used to validate credentials and connect a storage provider
  ///
  /// In en, this message translates to:
  /// **'Verify & Connect'**
  String get verifyAndConnect;

  /// Validation message shown when a required input field is empty
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// Informational text explaining local verification and encryption of credentials
  ///
  /// In en, this message translates to:
  /// **'Your keys are verified locally and encrypted before transmission.'**
  String get providerKeysVerifiedLocally;

  /// Section title prompting the user to enter provider credentials
  ///
  /// In en, this message translates to:
  /// **'Enter your credentials'**
  String get enterYourCredentials;

  /// Bottom app bar title for connecting a specific storage provider
  ///
  /// In en, this message translates to:
  /// **'Connect {provider}'**
  String connectProvider(String provider);

  /// Snackbar message shown when the user has reached the maximum allowed number of registered devices
  ///
  /// In en, this message translates to:
  /// **'Device limit reached'**
  String get deviceLimitReached;

  /// Snackbar message shown when signing out a device fails
  ///
  /// In en, this message translates to:
  /// **'Please try again!'**
  String get pleaseTryAgainWithExclamation;

  /// Snackbar message shown when the user tries to sign out the current device from the device list
  ///
  /// In en, this message translates to:
  /// **'Not this device!'**
  String get notThisDevice;

  /// Dialog title shown before signing out a device
  ///
  /// In en, this message translates to:
  /// **'Confirm signout device'**
  String get confirmSignoutDeviceTitle;

  /// Confirmation dialog message asking whether the user wants to proceed
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get areYouSure;

  /// Button label used to cancel a dialog action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button label used to confirm a dialog action
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// Empty state message shown when no devices are available
  ///
  /// In en, this message translates to:
  /// **'No device found'**
  String get noDeviceFound;

  /// Tooltip for the back navigation button
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backTooltip;

  /// Title for the devices screen
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devicesTitle;

  /// Snackbar message shown when a file cannot be opened and the user should long press to download it
  ///
  /// In en, this message translates to:
  /// **'Long press to download'**
  String get longPressToDownload;

  /// Snackbar message shown when some selected items still exist locally during archive action
  ///
  /// In en, this message translates to:
  /// **'Few items exists locally.'**
  String get fewItemsExistLocally;

  /// Title shown in the multi-select app bar with the number of selected items
  ///
  /// In en, this message translates to:
  /// **'{count} Selected'**
  String selectedItemsCount(int count);

  /// Tooltip label for deleting selected items
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Tooltip label for viewing file information
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get info;

  /// Tooltip label for downloading selected items
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// Tooltip label for archiving selected items
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive;

  /// Popup menu item label for the premium subscription page using the non-translated app name
  ///
  /// In en, this message translates to:
  /// **'{appName} Pro'**
  String appPro(String appName);

  /// Popup menu item label for the logs page
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

  /// Popup menu item label for the settings page
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Popup menu item label for the trash page
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get trash;

  /// Popup menu item label for the storage providers page
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storage;

  /// Popup menu item label for the search page
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// Popup menu item label for the database debug page
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get database;

  /// Dialog title shown when confirming addition of a sync folder
  ///
  /// In en, this message translates to:
  /// **'Add folder'**
  String get addFolderTitle;

  /// Button label used to confirm an action in a dialog
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Empty state message shown at the device root when no sync folders have been added
  ///
  /// In en, this message translates to:
  /// **'Tap + to add sync folder.'**
  String get tapPlusToAddSyncFolder;

  /// Empty state message shown when the current folder has no items
  ///
  /// In en, this message translates to:
  /// **'This Folder is empty.'**
  String get thisFolderIsEmpty;

  /// Error message shown when the requested file metadata cannot be found
  ///
  /// In en, this message translates to:
  /// **'File not found'**
  String get fileNotFound;

  /// Section title showing the number of encrypted file parts
  ///
  /// In en, this message translates to:
  /// **'File Parts ({count})'**
  String filePartsTitle(int count);

  /// Bottom app bar title for the file details screen
  ///
  /// In en, this message translates to:
  /// **'File Details'**
  String get fileDetailsTitle;

  /// Subtitle shown below the file name on the file details screen
  ///
  /// In en, this message translates to:
  /// **'Encrypted Backup'**
  String get encryptedBackup;

  /// Metadata label showing the file size
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sizeLabel;

  /// Metadata label showing the storage provider
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get providerLabel;

  /// Metadata label showing when the file was uploaded
  ///
  /// In en, this message translates to:
  /// **'Uploaded At'**
  String get uploadedAtLabel;

  /// Metadata label showing the file upload status
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// Status value shown when the file upload completed successfully
  ///
  /// In en, this message translates to:
  /// **'Uploaded'**
  String get uploadedStatus;

  /// Error text shown when loading logs fails
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String errorWithMessage(String message);

  /// Empty state text shown when there are no logs to display
  ///
  /// In en, this message translates to:
  /// **'No logs available'**
  String get noLogsAvailable;

  /// Hint text for the log search field
  ///
  /// In en, this message translates to:
  /// **'Search logs..'**
  String get searchLogsHint;

  /// Tooltip for the button that clears all logs
  ///
  /// In en, this message translates to:
  /// **'Clear logs'**
  String get clearLogs;

  /// Hint text shown in the search field requiring at least three characters
  ///
  /// In en, this message translates to:
  /// **'Search with min 3 characters'**
  String get searchWithMinThreeCharacters;

  /// Empty state message shown before the user starts typing in the search screen
  ///
  /// In en, this message translates to:
  /// **'Type below to search'**
  String get typeBelowToSearch;

  /// Empty state message shown when the search returns no items
  ///
  /// In en, this message translates to:
  /// **'No results.'**
  String get noResults;

  /// Title shown on the sign in screen
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcomeTitle;

  /// Subtitle on the sign in screen prompting the user to continue into the app
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue to {appName}'**
  String signInToContinue(String appName);

  /// Validation message shown when the email field is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter your email'**
  String get pleaseEnterYourEmail;

  /// Validation message shown when the email format is invalid
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get pleaseEnterValidEmailAddress;

  /// Label for the email input field
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddressLabel;

  /// Hint text shown in the email input field
  ///
  /// In en, this message translates to:
  /// **'your.email@example.com'**
  String get emailAddressHint;

  /// Button label shown when sending OTP failed and the user can retry
  ///
  /// In en, this message translates to:
  /// **'Retry Sending OTP'**
  String get retrySendingOtp;

  /// Primary button label used to request an OTP
  ///
  /// In en, this message translates to:
  /// **'Send OTP'**
  String get sendOtp;

  /// Title shown on the OTP verification step
  ///
  /// In en, this message translates to:
  /// **'Check your email'**
  String get checkYourEmail;

  /// Message shown after sending the OTP to the user's email
  ///
  /// In en, this message translates to:
  /// **'We\'ve sent a 6-digit code to\n{email}'**
  String sentSixDigitCodeTo(String email);

  /// Validation message shown when the OTP field is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter the OTP'**
  String get pleaseEnterOtp;

  /// Validation message shown when the OTP is shorter than six digits
  ///
  /// In en, this message translates to:
  /// **'OTP must be 6 digits'**
  String get otpMustBeSixDigits;

  /// Label for the OTP input field
  ///
  /// In en, this message translates to:
  /// **'Enter OTP'**
  String get enterOtpLabel;

  /// Hint text shown in the OTP input field
  ///
  /// In en, this message translates to:
  /// **'000000'**
  String get otpHint;

  /// Button label shown when OTP verification failed and the user can retry
  ///
  /// In en, this message translates to:
  /// **'Retry Verification'**
  String get retryVerification;

  /// Primary button label used to verify the OTP
  ///
  /// In en, this message translates to:
  /// **'Verify OTP'**
  String get verifyOtp;

  /// Button label used to go back and enter a different email address
  ///
  /// In en, this message translates to:
  /// **'Use a different email'**
  String get useDifferentEmail;

  /// Title shown when the user is already signed in
  ///
  /// In en, this message translates to:
  /// **'Already Signed In'**
  String get alreadySignedIn;

  /// Snackbar message shown when sending the OTP fails
  ///
  /// In en, this message translates to:
  /// **'Sending OTP failed. Please try again!'**
  String get sendingOtpFailedPleaseTryAgain;

  /// Snackbar message shown when verifying the OTP fails
  ///
  /// In en, this message translates to:
  /// **'OTP verification failed. Please try again.'**
  String get otpVerificationFailedPleaseTryAgain;

  /// App bar title for the SQLite database viewer screen
  ///
  /// In en, this message translates to:
  /// **'DB Viewer'**
  String get dbViewerTitle;

  /// Empty state message shown before a database table is selected
  ///
  /// In en, this message translates to:
  /// **'Select a table to view its data'**
  String get selectTableToViewData;

  /// Hint text for the table selection dropdown
  ///
  /// In en, this message translates to:
  /// **'Select a table'**
  String get selectTable;

  /// Dialog title shown when storage permission is permanently denied
  ///
  /// In en, this message translates to:
  /// **'Permission Required'**
  String get permissionRequiredTitle;

  /// Dialog description explaining why storage permission is needed and asking the user to open settings
  ///
  /// In en, this message translates to:
  /// **'To automatically back up, manage, and secure your files in the background, we need access to your device storage. Your data is encrypted locally, ensuring total privacy. Please allow access to continue.'**
  String get storagePermissionSettingsDescription;

  /// Button label used to open the system app settings screen
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get openSettings;

  /// Snackbar message shown when the user denies storage permission
  ///
  /// In en, this message translates to:
  /// **'Storage permission is required to continue'**
  String get storagePermissionRequiredToContinue;

  /// Main title on the storage permission onboarding screen
  ///
  /// In en, this message translates to:
  /// **'Secure Local Access'**
  String get secureLocalAccessTitle;

  /// Description on the storage permission page explaining why access is needed
  ///
  /// In en, this message translates to:
  /// **'To explore, encrypt, and back up your files automatically, we need access to your device storage.'**
  String get storagePermissionPageDescription;

  /// Button loading label shown while permission status is being checked
  ///
  /// In en, this message translates to:
  /// **'Verifying...'**
  String get verifying;

  /// Primary button label used to request storage permission
  ///
  /// In en, this message translates to:
  /// **'Grant Access'**
  String get grantAccess;

  /// Footer note emphasizing the app's privacy model on the storage permission screen
  ///
  /// In en, this message translates to:
  /// **'Zero-knowledge encrypted storage'**
  String get zeroKnowledgeEncryptedStorage;

  /// Snackbar message shown when a Pro subscription is required for modifying storage
  ///
  /// In en, this message translates to:
  /// **'Requires {appName} Pro.'**
  String requiresAppPro(String appName);

  /// Empty state message shown when no storage providers are available
  ///
  /// In en, this message translates to:
  /// **'No storage found'**
  String get noStorageFound;

  /// Button label that opens help about connecting a storage provider
  ///
  /// In en, this message translates to:
  /// **'How to connect'**
  String get howToConnect;

  /// Button label used to modify a connected storage provider
  ///
  /// In en, this message translates to:
  /// **'Modify'**
  String get modify;

  /// Storage usage label showing used and total storage
  ///
  /// In en, this message translates to:
  /// **'{used} / {total} Used'**
  String storageUsed(String used, String total);

  /// Percentage label showing storage usage percent
  ///
  /// In en, this message translates to:
  /// **'{value}%'**
  String percentageLabel(String value);

  /// Label showing the maximum free storage available for an unconnected provider
  ///
  /// In en, this message translates to:
  /// **'Up to {size} free'**
  String upToFree(String size);

  /// Status label shown for a storage provider that has not been connected
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// Button label used to connect a storage provider
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// Dialog title for changing the storage capacity of a provider
  ///
  /// In en, this message translates to:
  /// **'Modify Storage Capacity'**
  String get modifyStorageCapacityTitle;

  /// Helper text in the modify storage dialog
  ///
  /// In en, this message translates to:
  /// **'Enter the new storage limit for this provider.'**
  String get enterNewStorageLimitForProvider;

  /// Prefix text shown before the numeric storage size input
  ///
  /// In en, this message translates to:
  /// **'Size: '**
  String get sizePrefix;

  /// Suffix text shown after the numeric storage size input
  ///
  /// In en, this message translates to:
  /// **' GB'**
  String get gbSuffix;

  /// Validation message shown when the storage size field is empty
  ///
  /// In en, this message translates to:
  /// **'Please enter a size'**
  String get pleaseEnterSize;

  /// Validation message shown when the entered storage size is invalid
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number greater than 1'**
  String get enterValidNumberGreaterThanOne;

  /// Button label used to submit the storage size dialog
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// Snackbar message shown after a successful subscription purchase
  ///
  /// In en, this message translates to:
  /// **'Successfully subscribed to {appName} Pro!'**
  String successfullySubscribedToAppPro(String appName);

  /// Snackbar message shown when the purchase flow is cancelled or fails
  ///
  /// In en, this message translates to:
  /// **'Purchase cancelled or failed.'**
  String get purchaseCancelledOrFailed;

  /// Snackbar message shown when previous purchases are restored successfully
  ///
  /// In en, this message translates to:
  /// **'Purchases restored successfully!'**
  String get purchasesRestoredSuccessfully;

  /// Snackbar message shown when restore purchases finds no active subscription
  ///
  /// In en, this message translates to:
  /// **'No active subscriptions found.'**
  String get noActiveSubscriptionsFound;

  /// Snackbar message shown when no management URL is available
  ///
  /// In en, this message translates to:
  /// **'Please manage subscriptions in your device settings.'**
  String get manageSubscriptionsInDeviceSettings;

  /// Title of the free subscription plan card
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get freePlanTitle;

  /// Price label for the free plan
  ///
  /// In en, this message translates to:
  /// **'\$0.00 / forever'**
  String get freeForeverPrice;

  /// Benefit listed under the free plan
  ///
  /// In en, this message translates to:
  /// **'Enjoy free storage from providers'**
  String get freeBenefitProviderStorage;

  /// Benefit listed under the free plan
  ///
  /// In en, this message translates to:
  /// **'Sync up to 3 devices securely'**
  String get freeBenefitSyncThreeDevices;

  /// Title of the yearly pro subscription plan
  ///
  /// In en, this message translates to:
  /// **'{appName} Pro - Yearly'**
  String appProYearlyTitle(String appName);

  /// Benefit listed under the Pro plan
  ///
  /// In en, this message translates to:
  /// **'Modify storage limit for each provider'**
  String get proBenefitModifyStorageLimit;

  /// Benefit listed under the Pro plan
  ///
  /// In en, this message translates to:
  /// **'Sync up to 10 devices'**
  String get proBenefitSyncTenDevices;

  /// Button label used to restore previous purchases
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get restorePurchases;

  /// Footnote explaining that the subscription is tied to the email account rather than a device
  ///
  /// In en, this message translates to:
  /// **'* Subscription is associated with email account, not the device'**
  String get subscriptionAssociatedWithEmailNotDevice;

  /// Title shown in the expired subscription banner
  ///
  /// In en, this message translates to:
  /// **'Subscription Expired'**
  String get subscriptionExpiredTitle;

  /// Description shown in the expired subscription banner
  ///
  /// In en, this message translates to:
  /// **'Your {appName} Pro benefits have been paused. Renew below to restore your storage limits and device syncs.'**
  String subscriptionExpiredDescription(String appName);

  /// Title shown when the user has an active Pro subscription
  ///
  /// In en, this message translates to:
  /// **'{appName} Pro is Active'**
  String appProIsActive(String appName);

  /// Summary of active Pro subscription benefits
  ///
  /// In en, this message translates to:
  /// **'✓ Modify storage limits for each provider\n✓ Cross sync up to 10 devices'**
  String get activePlanBenefitsSummary;

  /// Button label used to open subscription management
  ///
  /// In en, this message translates to:
  /// **'Manage Subscription'**
  String get manageSubscription;

  /// Badge shown on the current active plan
  ///
  /// In en, this message translates to:
  /// **'CURRENT'**
  String get currentPlanBadge;

  /// Primary call to action for purchasing the Pro plan
  ///
  /// In en, this message translates to:
  /// **'Subscribe Now'**
  String get subscribeNow;

  /// Call to action shown when subscription purchase is not supported on the current platform
  ///
  /// In en, this message translates to:
  /// **'Subscribe on mobile app'**
  String get subscribeOnMobileApp;

  /// Tooltip label for recovering selected items from the trash
  ///
  /// In en, this message translates to:
  /// **'Recover'**
  String get recover;

  /// Tooltip label for emptying the trash
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get empty;

  /// Empty state text shown when the trash has no items
  ///
  /// In en, this message translates to:
  /// **'No items.'**
  String get noItems;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
        'ar',
        'de',
        'el',
        'en',
        'es',
        'fa',
        'fr',
        'he',
        'hi',
        'id',
        'it',
        'ja',
        'ko',
        'nl',
        'pt',
        'ru',
        'th',
        'tr',
        'uk',
        'vi',
        'zh'
      ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'el':
      return AppLocalizationsEl();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fa':
      return AppLocalizationsFa();
    case 'fr':
      return AppLocalizationsFr();
    case 'he':
      return AppLocalizationsHe();
    case 'hi':
      return AppLocalizationsHi();
    case 'id':
      return AppLocalizationsId();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ko':
      return AppLocalizationsKo();
    case 'nl':
      return AppLocalizationsNl();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'th':
      return AppLocalizationsTh();
    case 'tr':
      return AppLocalizationsTr();
    case 'uk':
      return AppLocalizationsUk();
    case 'vi':
      return AppLocalizationsVi();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
