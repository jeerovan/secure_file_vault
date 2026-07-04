// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Modern Greek (`el`).
class AppLocalizationsEl extends AppLocalizations {
  AppLocalizationsEl([String locale = 'el']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Συνεχίζοντας, συμφωνείτε με τους $terms και την $privacy.';
  }

  @override
  String get termsOfService => 'Όροι Χρήσης';

  @override
  String get privacyPolicy => 'Πολιτική Απορρήτου';

  @override
  String get andLabel => ' και ';

  @override
  String get theme => 'Θέμα';

  @override
  String get themeTooltip => 'Θέμα ημέρας/νύχτας';

  @override
  String get logging => 'Καταγραφή';

  @override
  String get quickSyncNotificationSettingTitle =>
      'Ειδοποίηση γρήγορου συγχρονισμού';

  @override
  String get quickSyncNotificationTitle => 'Υπηρεσία συγχρονισμού αρχείων';

  @override
  String get quickSyncNotificationText =>
      'Πατήστε το παρακάτω κουμπί για συγχρονισμό';

  @override
  String get quickSyncNotificationButton => 'Συγχρονισμός τώρα';

  @override
  String get quickSyncNotificationInProgress => 'Σε εξέλιξη...';

  @override
  String get reportIssue => 'Αναφορά προβλήματος';

  @override
  String get sourceCode => 'Πηγαίος κώδικας';

  @override
  String get desktopApp => 'Εφαρμογή υπολογιστή';

  @override
  String get mobileApp => 'Εφαρμογή κινητού';

  @override
  String get leaveReview => 'Αφήστε αξιολόγηση';

  @override
  String get share => 'Κοινοποίηση';

  @override
  String get versionLabel => 'Έκδοση: ';

  @override
  String get loading => 'Φόρτωση...';

  @override
  String get signOut => 'Αποσύνδεση';

  @override
  String get settingsPageTitle => 'Ρυθμίσεις';

  @override
  String get language => 'Γλώσσα';

  @override
  String get tapToSelect => 'Πατήστε για επιλογή';

  @override
  String get appTagline => 'Η ιδιωτική μεταφορά των αρχείων σας';

  @override
  String get onboardingPurposeDescription =>
      'Μια υπηρεσία αποθήκευσης cloud ανοιχτού κώδικα, σχεδιασμένη με αρχιτεκτονική zero-trust. Τα δεδομένα σας κρυπτογραφούνται τοπικά στη συσκευή σας πριν φύγουν από αυτή.';

  @override
  String get failedToFetch => 'Η φόρτωση απέτυχε.';

  @override
  String get supportedStorageTitle => 'Υποστηριζόμενοι χώροι αποθήκευσης';

  @override
  String get supportedStorageDescription =>
      'Συνδέστε τους αγαπημένους σας παρόχους. Ξεκινήστε αμέσως με 1 GB δωρεάν ασφαλούς αποθήκευσης από το FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Ξεκινήστε άμεσα αντίγραφα ασφαλείας';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Δωρεάν';

  @override
  String get providerStorageDisclaimer =>
      '* Δωρεάν αποθηκευτικός χώρος όπως αναφέρεται στον ιστότοπο του παρόχου. Χρέωση ανάλογα με τη χρήση με συμβατούς παρόχους.';

  @override
  String get whyUseFifeTitle => 'Γιατί να χρησιμοποιήσετε το FiFe;';

  @override
  String get claimFreeCloudStorageTitle => 'Αξιοποιήστε δωρεάν χώρο στο cloud';

  @override
  String get claimFreeCloudStorageDescription =>
      'Αυξήστε τον διαθέσιμο χώρο σας συνδέοντας πολλούς παρόχους cloud. Αξιοποιήστε με ασφάλεια τα δωρεάν πακέτα τους μέσα από μία ενιαία εφαρμογή.';

  @override
  String get topNotchSecurityTitle => 'Κορυφαία ασφάλεια';

  @override
  String get topNotchSecurityDescription =>
      'Με προηγμένη κρυπτογραφία Sodium. Όλη η κρυπτογράφηση και αποκρυπτογράφηση γίνεται τοπικά στη συσκευή σας.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Διατηρήστε τον πλήρη έλεγχο των δεδομένων σας σε όλους τους παρόχους cloud storage. Χρησιμοποιήστε κρυπτογραφημένη αποθήκευση με τους δικούς σας λογαριασμούς.';

  @override
  String get payAsYouGoStorageTitle => 'Πληρωμή μόνο για ό,τι χρησιμοποιείτε.';

  @override
  String get payAsYouGoStorageDescription =>
      'Πληρώνετε μόνο για τον χώρο που χρησιμοποιείτε με συμβατούς παρόχους. Χωρίς μεσάζοντες, χωρίς κλείδωμα δεδομένων.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Απόρρητο Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Τα δεδομένα σας κλειδώνονται στη συσκευή σας πριν φύγουν από αυτή. Δεν μπορούμε να δούμε, να διαβάσουμε ή να σαρώσουμε τα αρχεία σας.';

  @override
  String get localSelectionTitle => '1. Τοπική επιλογή';

  @override
  String get localSelectionDescription =>
      'Εσείς επιλέγετε έναν φάκελο. Όλη η επεξεργασία ξεκινά με ασφάλεια στη συσκευή σας.';

  @override
  String get metadataEncryptionTitle => '2. Κρυπτογράφηση μεταδεδομένων';

  @override
  String get metadataEncryptionDescription =>
      'Οι πληροφορίες του αρχείου, όπως όνομα, τύπος και μέγεθος, κρυπτογραφούνται πριν σταλούν στον διακομιστή.';

  @override
  String get contentEncryptionTitle => '3. Κρυπτογράφηση περιεχομένου';

  @override
  String get contentEncryptionDescription =>
      'Το ίδιο το περιεχόμενο του αρχείου τεμαχίζεται και κρυπτογραφείται πριν ανέβει στο cloud storage.';

  @override
  String get blindServerTitle => '4. Τυφλός διακομιστής';

  @override
  String get blindServerDescription =>
      'Οι διακομιστές μας δεν γνωρίζουν τίποτα για τα δεδομένα σας. Βλέπουμε μόνο κρυπτογραφημένα δεδομένα, εξασφαλίζοντας απόλυτο απόρρητο.';

  @override
  String get dontTrustVerifyTitle => 'Μην εμπιστεύεστε, επαληθεύστε.';

  @override
  String get openSourceVerificationDescription =>
      '100% ανοιχτός κώδικας. Μπορείτε να ελέγξετε τον κώδικα και να δείτε ακριβώς πώς κρυπτογραφούνται τα αρχεία σας.';

  @override
  String get getStarted => 'Ξεκινήστε';

  @override
  String get next => 'Επόμενο';

  @override
  String get unauthorized => 'Μη εξουσιοδοτημένη πρόσβαση';

  @override
  String get tryAgain => 'Δοκιμάστε ξανά';

  @override
  String get errorTitle => 'Σφάλμα';

  @override
  String get failureTitle => 'Αποτυχία';

  @override
  String get invalidWordList => 'Μη έγκυρη λίστα λέξεων';

  @override
  String get invalidAccessKey => 'Μη έγκυρο κλειδί πρόσβασης';

  @override
  String get unexpectedDecryptionError =>
      'Προέκυψε ένα απρόσμενο σφάλμα κατά την αποκρυπτογράφηση.';

  @override
  String get fileMustContainExactly24Words =>
      'Το αρχείο πρέπει να περιέχει ακριβώς 24 λέξεις.';

  @override
  String get errorReadingFile => 'Σφάλμα κατά την ανάγνωση του αρχείου';

  @override
  String get encryptionTitle => 'Κρυπτογράφηση';

  @override
  String get accessKeyDecodeDescription =>
      'Εισαγάγετε τη φράση ανάκτησης με 24 λέξεις ή φορτώστε ένα αρχείο .txt για να ενεργοποιήσετε με ασφάλεια τον συγχρονισμό στο cloud.';

  @override
  String get recoveryPhraseLabel => 'Φράση ανάκτησης';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => 'Επικόλληση';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 λέξεις';
  }

  @override
  String get pleaseEnterRecoveryPhrase =>
      'Παρακαλώ εισαγάγετε τη φράση ανάκτησης';

  @override
  String get mustContainExactly24Words =>
      'Πρέπει να περιέχει ακριβώς 24 λέξεις';

  @override
  String get verify => 'Επαλήθευση';

  @override
  String get orLabel => 'Ή';

  @override
  String get loadFromTxtFile => 'Φόρτωση από αρχείο .txt';

  @override
  String get saveAccessKey => 'Αποθήκευση κλειδιού πρόσβασης';

  @override
  String get fileSavedSuccessfully => 'Το αρχείο αποθηκεύτηκε με επιτυχία.';

  @override
  String get accessKeyShareMessage => 'Ορίστε το κλειδί πρόσβασής σας.';

  @override
  String get pleaseTryAgain => 'Παρακαλώ δοκιμάστε ξανά.';

  @override
  String get copiedToClipboard => 'Αντιγράφηκε στο πρόχειρο';

  @override
  String get accessKeyTitle => 'Κλειδί πρόσβασης';

  @override
  String get accessKeyDescription =>
      'Αποθηκεύστε αυτό το κλειδί σε ασφαλές σημείο. Μόνο με αυτό θα μπορείτε να αποκτήσετε πρόσβαση στα κρυπτογραφημένα δεδομένα σας.';

  @override
  String get copy => 'Αντιγραφή';

  @override
  String get downloadAsTextFile => 'Λήψη ως αρχείο κειμένου';

  @override
  String get continueLabel => 'Συνέχεια';

  @override
  String get importantTitle => 'Σημαντικό';

  @override
  String get accessKeyNoticePrimary =>
      'Στην επόμενη σελίδα θα δείτε μια σειρά από 24 λέξεις. Αυτό είναι το μοναδικό και ιδιωτικό σας κλειδί κρυπτογράφησης και είναι ο ΜΟΝΑΔΙΚΟΣ τρόπος να ανακτήσετε τα δεδομένα σας σε περίπτωση αποσύνδεσης, απώλειας συσκευής ή βλάβης.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Δεν αποθηκεύουμε αυτό το κλειδί. Είναι ΔΙΚΗ σας ευθύνη να το φυλάξετε σε ασφαλές σημείο εκτός της εφαρμογής $appName.';
  }

  @override
  String get showKeyConfirmation => 'Το κατάλαβα.\nΔείξε μου το κλειδί.';

  @override
  String get storageAddedSuccessfully =>
      'Ο χώρος αποθήκευσης προστέθηκε με επιτυχία';

  @override
  String get networkErrorDuringValidation =>
      'Προέκυψε σφάλμα δικτύου κατά την επαλήθευση.';

  @override
  String get verifyAndConnect => 'Επαλήθευση & σύνδεση';

  @override
  String get requiredField => 'Υποχρεωτικό';

  @override
  String get providerKeysVerifiedLocally =>
      'Τα κλειδιά σας επαληθεύονται τοπικά και κρυπτογραφούνται πριν από τη μεταφορά.';

  @override
  String get enterYourCredentials => 'Εισαγάγετε τα στοιχεία σας';

  @override
  String connectProvider(String provider) {
    return 'Σύνδεση $provider';
  }

  @override
  String get deviceLimitReached => 'Έχει συμπληρωθεί το όριο συσκευών';

  @override
  String get pleaseTryAgainWithExclamation => 'Παρακαλώ δοκιμάστε ξανά!';

  @override
  String get notThisDevice => 'Όχι αυτή η συσκευή!';

  @override
  String get confirmSignoutDeviceTitle => 'Επιβεβαίωση αποσύνδεσης συσκευής';

  @override
  String get areYouSure => 'Είστε βέβαιοι;';

  @override
  String get cancel => 'Ακύρωση';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Δεν βρέθηκε συσκευή';

  @override
  String get backTooltip => 'Πίσω';

  @override
  String get devicesTitle => 'Συσκευές';

  @override
  String get longPressToDownload => 'Παρατεταμένο πάτημα για λήψη';

  @override
  String get fewItemsExistLocally => 'Μερικά στοιχεία υπάρχουν ακόμη τοπικά.';

  @override
  String selectedItemsCount(int count) {
    return 'Επιλέχθηκαν $count';
  }

  @override
  String get delete => 'Διαγραφή';

  @override
  String get info => 'Πληροφορίες';

  @override
  String get download => 'Λήψη';

  @override
  String get archive => 'Αρχειοθέτηση';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Καταγραφές';

  @override
  String get settings => 'Ρυθμίσεις';

  @override
  String get trash => 'Κάδος';

  @override
  String get storage => 'Αποθήκευση';

  @override
  String get search => 'Αναζήτηση';

  @override
  String get database => 'Βάση δεδομένων';

  @override
  String get addFolderTitle => 'Προσθήκη φακέλου';

  @override
  String get confirm => 'Επιβεβαίωση';

  @override
  String get tapPlusToAddSyncFolder =>
      'Πατήστε + για να προσθέσετε φάκελο συγχρονισμού.';

  @override
  String get thisFolderIsEmpty => 'Αυτός ο φάκελος είναι άδειος.';

  @override
  String get fileNotFound => 'Το αρχείο δεν βρέθηκε';

  @override
  String filePartsTitle(int count) {
    return 'Τμήματα αρχείου ($count)';
  }

  @override
  String get fileDetailsTitle => 'Λεπτομέρειες αρχείου';

  @override
  String get encryptedBackup => 'Κρυπτογραφημένο αντίγραφο ασφαλείας';

  @override
  String get sizeLabel => 'Μέγεθος';

  @override
  String get providerLabel => 'Πάροχος';

  @override
  String get uploadedAtLabel => 'Μεταφορτώθηκε στις';

  @override
  String get statusLabel => 'Κατάσταση';

  @override
  String get uploadedStatus => 'Μεταφορτώθηκε';

  @override
  String errorWithMessage(String message) {
    return 'Σφάλμα: $message';
  }

  @override
  String get noLogsAvailable => 'Δεν υπάρχουν καταγραφές';

  @override
  String get searchLogsHint => 'Αναζήτηση στις καταγραφές...';

  @override
  String get clearLogs => 'Εκκαθάριση καταγραφών';

  @override
  String get searchWithMinThreeCharacters =>
      'Αναζήτηση με τουλάχιστον 3 χαρακτήρες';

  @override
  String get typeBelowToSearch => 'Πληκτρολογήστε παρακάτω για αναζήτηση';

  @override
  String get noResults => 'Δεν υπάρχουν αποτελέσματα.';

  @override
  String get welcomeTitle => 'Καλώς ήρθατε';

  @override
  String signInToContinue(String appName) {
    return 'Συνδεθείτε για να συνεχίσετε στο $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Παρακαλώ εισαγάγετε το email σας';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Παρακαλώ εισαγάγετε έγκυρη διεύθυνση email';

  @override
  String get emailAddressLabel => 'Διεύθυνση email';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'Επανάληψη αποστολής OTP';

  @override
  String get sendOtp => 'Αποστολή OTP';

  @override
  String get checkYourEmail => 'Ελέγξτε το email σας';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Στείλαμε έναν 6ψήφιο κωδικό στο\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Παρακαλώ εισαγάγετε το OTP';

  @override
  String get otpMustBeSixDigits => 'Το OTP πρέπει να έχει 6 ψηφία';

  @override
  String get enterOtpLabel => 'Εισαγωγή OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Επανάληψη επαλήθευσης';

  @override
  String get verifyOtp => 'Επαλήθευση OTP';

  @override
  String get useDifferentEmail => 'Χρήση άλλου email';

  @override
  String get alreadySignedIn => 'Έχετε ήδη συνδεθεί';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Η αποστολή OTP απέτυχε. Παρακαλώ δοκιμάστε ξανά!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Η επαλήθευση OTP απέτυχε. Παρακαλώ δοκιμάστε ξανά.';

  @override
  String get dbViewerTitle => 'Προβολή βάσης δεδομένων';

  @override
  String get selectTableToViewData =>
      'Επιλέξτε έναν πίνακα για να δείτε τα δεδομένα του';

  @override
  String get selectTable => 'Επιλέξτε πίνακα';

  @override
  String get permissionRequiredTitle => 'Απαιτείται άδεια';

  @override
  String get storagePermissionSettingsDescription =>
      'Για να δημιουργούμε αυτόματα αντίγραφα ασφαλείας, να διαχειριζόμαστε και να προστατεύουμε τα αρχεία σας στο παρασκήνιο, χρειαζόμαστε πρόσβαση στον χώρο αποθήκευσης της συσκευής σας. Τα δεδομένα σας κρυπτογραφούνται τοπικά, εξασφαλίζοντας πλήρες απόρρητο. Παρακαλώ επιτρέψτε την πρόσβαση για να συνεχίσετε.';

  @override
  String get openSettings => 'Άνοιγμα ρυθμίσεων';

  @override
  String get secureLocalAccessTitle => 'Ασφαλής τοπική πρόσβαση';

  @override
  String get storagePermissionPageDescription =>
      'Για να περιηγείστε, να κρυπτογραφείτε και να δημιουργείτε αυτόματα αντίγραφα ασφαλείας των αρχείων σας, χρειαζόμαστε πρόσβαση στον αποθηκευτικό χώρο της συσκευής σας.';

  @override
  String get verifying => 'Γίνεται επαλήθευση...';

  @override
  String get grantAccess => 'Παραχώρηση πρόσβασης';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Κρυπτογραφημένη αποθήκευση zero-knowledge';

  @override
  String get notificationPermissionTitle => 'Πρόσβαση σε Ειδοποιήσεις';

  @override
  String get notificationPermissionPageDescription =>
      'Για να διατηρούνται τα αρχεία σας συγχρονισμένα και να παρέχονται ενημερώσεις κατάστασης σε πραγματικό χρόνο στο παρασκήνιο, χρειαζόμαστε άδεια για να εμφανίσουμε ειδοποιήσεις.';

  @override
  String get notificationPermissionGrantButton => 'Επιτρέψτε Ειδοποιήσεις';

  @override
  String get notificationPermissionSettingsDescription =>
      'Οι ειδοποιήσεις είναι απαραίτητες για την παρακολούθηση του συγχρονισμού στο παρασκήνιο. Παρακαλώ ενεργοποιήστε τις στις ρυθμίσεις του συστήματος για να διασφαλίσετε ότι τα δεδομένα σας είναι πάντα up to date.';

  @override
  String requiresAppPro(String appName) {
    return 'Απαιτείται $appName Pro.';
  }

  @override
  String get noStorageFound => 'Δεν βρέθηκε χώρος αποθήκευσης';

  @override
  String get howToConnect => 'Πώς να συνδεθείτε';

  @override
  String get modify => 'Τροποποίηση';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total σε χρήση';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Έως $size δωρεάν';
  }

  @override
  String get notConnected => 'Δεν έχει συνδεθεί';

  @override
  String get connect => 'Σύνδεση';

  @override
  String get modifyStorageCapacityTitle =>
      'Τροποποίηση χωρητικότητας αποθήκευσης';

  @override
  String get enterNewStorageLimitForProvider =>
      'Εισαγάγετε το νέο όριο αποθήκευσης για αυτόν τον πάροχο.';

  @override
  String get sizePrefix => 'Μέγεθος: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Παρακαλώ εισαγάγετε μέγεθος';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Εισαγάγετε έναν έγκυρο αριθμό μεγαλύτερο από 1';

  @override
  String get submit => 'Υποβολή';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Η συνδρομή στο $appName Pro ολοκληρώθηκε με επιτυχία!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Η αγορά ακυρώθηκε ή απέτυχε.';

  @override
  String get purchasesRestoredSuccessfully =>
      'Οι αγορές αποκαταστάθηκαν με επιτυχία!';

  @override
  String get noActiveSubscriptionsFound => 'Δεν βρέθηκαν ενεργές συνδρομές.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Παρακαλώ διαχειριστείτε τις συνδρομές από τις ρυθμίσεις της συσκευής σας.';

  @override
  String get freePlanTitle => 'Δωρεάν';

  @override
  String get freeForeverPrice => '\$0.00 / για πάντα';

  @override
  String get freeBenefitProviderStorage =>
      'Αξιοποιήστε δωρεάν χώρο από παρόχους';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Ασφαλής συγχρονισμός έως 3 συσκευών';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Ετήσιο';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Τροποποίηση ορίου αποθήκευσης για κάθε πάροχο';

  @override
  String get proBenefitSyncTenDevices => 'Συγχρονισμός έως 10 συσκευών';

  @override
  String get restorePurchases => 'Επαναφορά αγορών';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Η συνδρομή συνδέεται με το email και όχι με τη συσκευή';

  @override
  String get subscriptionExpiredTitle => 'Η συνδρομή έληξε';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Τα προνόμια του $appName Pro έχουν τεθεί σε παύση. Ανανεώστε παρακάτω για να επαναφέρετε τα όρια αποθήκευσης και τον συγχρονισμό συσκευών.';
  }

  @override
  String appProIsActive(String appName) {
    return 'Το $appName Pro είναι ενεργό';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Τροποποίηση ορίων αποθήκευσης για κάθε πάροχο\n✓ Συγχρονισμός μεταξύ συσκευών έως 10 συσκευές';

  @override
  String get manageSubscription => 'Διαχείριση συνδρομής';

  @override
  String get currentPlanBadge => 'ΤΡΕΧΟΝ';

  @override
  String get subscribeNow => 'Εγγραφή τώρα';

  @override
  String get subscribeOnMobileApp => 'Εγγραφή από την εφαρμογή κινητού';

  @override
  String get recover => 'Επαναφορά';

  @override
  String get empty => 'Άδειασμα';

  @override
  String get noItems => 'Δεν υπάρχουν στοιχεία.';
}
