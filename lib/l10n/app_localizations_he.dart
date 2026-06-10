// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'בהמשך השימוש, אתה מסכים ל$terms ול$privacy שלנו.';
  }

  @override
  String get termsOfService => 'תנאי השירות';

  @override
  String get privacyPolicy => 'מדיניות הפרטיות';

  @override
  String get andLabel => ' ו-';

  @override
  String get theme => 'ערכת נושא';

  @override
  String get themeTooltip => 'ערכת יום/לילה';

  @override
  String get logging => 'יומנים';

  @override
  String get reportIssue => 'דיווח על תקלה';

  @override
  String get sourceCode => 'קוד מקור';

  @override
  String get desktopApp => 'אפליקציית מחשב';

  @override
  String get mobileApp => 'אפליקציה לנייד';

  @override
  String get leaveReview => 'השארת ביקורת';

  @override
  String get share => 'שיתוף';

  @override
  String get versionLabel => 'גרסה: ';

  @override
  String get loading => 'טוען...';

  @override
  String get signOut => 'התנתקות';

  @override
  String get settingsPageTitle => 'הגדרות';

  @override
  String get language => 'שפה';

  @override
  String get tapToSelect => 'הקש כדי לבחור';

  @override
  String get appTagline => 'המעבורת הפרטית לקבצים שלך';

  @override
  String get onboardingPurposeDescription =>
      'שירות אחסון ענן בקוד פתוח שנבנה בארכיטקטורת zero-trust. הנתונים שלך מוצפנים מקומית עוד לפני שהם עוזבים את המכשיר.';

  @override
  String get failedToFetch => 'הטעינה נכשלה.';

  @override
  String get supportedStorageTitle => 'שירותי אחסון נתמכים';

  @override
  String get supportedStorageDescription =>
      'חבר את הספקים המועדפים עליך. אפשר להתחיל מיד עם 1 ג׳יגה-בייט אחסון מאובטח חינמי של FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'התחל גיבויים מיד';

  @override
  String get freeStorageSizeOneGb => '1.0 ג״ב';

  @override
  String get freeLabel => 'חינם';

  @override
  String get providerStorageDisclaimer =>
      '* נפח האחסון החינמי בהתאם למידע באתר הספק. תשלום לפי שימוש אצל ספקים תואמים.';

  @override
  String get whyUseFifeTitle => 'למה להשתמש ב-FiFe?';

  @override
  String get claimFreeCloudStorageTitle => 'נצל אחסון ענן חינמי';

  @override
  String get claimFreeCloudStorageDescription =>
      'הגדל את נפח האחסון שלך על ידי חיבור כמה ספקי ענן. נצל בצורה מאובטחת את החבילות החינמיות שלהם בתוך אפליקציה אחת.';

  @override
  String get topNotchSecurityTitle => 'אבטחה ברמה הגבוהה ביותר';

  @override
  String get topNotchSecurityDescription =>
      'מופעל באמצעות הצפנת Sodium מתקדמת. כל פעולות ההצפנה והפענוח מתבצעות כולן מקומית במכשיר שלך.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'שמור על שליטה מלאה בנתונים שלך בכל ספקי האחסון בענן. השתמש באחסון מוצפן דרך החשבונות שלך.';

  @override
  String get payAsYouGoStorageTitle => 'תשלום לפי שימוש עבור אחסון.';

  @override
  String get payAsYouGoStorageDescription =>
      'שלם רק על האחסון שבו השתמשת אצל ספקים תואמים. בלי מתווך ובלי נעילת נתונים.';

  @override
  String get zeroKnowledgePrivacyTitle => 'פרטיות Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'הנתונים שלך ננעלים במכשיר עוד לפני שהם יוצאים ממנו. איננו יכולים לראות, לקרוא או לסרוק את הקבצים שלך.';

  @override
  String get localSelectionTitle => '1. בחירה מקומית';

  @override
  String get localSelectionDescription =>
      'אתה בוחר תיקייה. כל העיבוד מתחיל באופן מאובטח במכשיר המקומי שלך.';

  @override
  String get metadataEncryptionTitle => '2. הצפנת מטא-נתונים';

  @override
  String get metadataEncryptionDescription =>
      'פרטי הקבצים, כמו שמות, סוגים וגדלים, מוצפנים לפני שליחתם לשרת.';

  @override
  String get contentEncryptionTitle => '3. הצפנת תוכן';

  @override
  String get contentEncryptionDescription =>
      'תוכן הקובץ עצמו מפוצל ומוצפן לפני ההעלאה לאחסון בענן.';

  @override
  String get blindServerTitle => '4. שרת עיוור';

  @override
  String get blindServerDescription =>
      'לשרתים שלנו אין כל ידע על הנתונים שלך. אנחנו רואים רק בלוקים מוצפנים, וכך נשמרת פרטיות מלאה.';

  @override
  String get dontTrustVerifyTitle => 'אל תסמוך, בדוק.';

  @override
  String get openSourceVerificationDescription =>
      '100% קוד פתוח. אפשר לבדוק את הקוד ולראות בדיוק איך הקבצים שלך מוצפנים.';

  @override
  String get getStarted => 'התחל';

  @override
  String get next => 'הבא';

  @override
  String get unauthorized => 'אין הרשאה';

  @override
  String get tryAgain => 'נסה שוב';

  @override
  String get errorTitle => 'שגיאה';

  @override
  String get failureTitle => 'כישלון';

  @override
  String get invalidWordList => 'רשימת מילים לא תקינה';

  @override
  String get invalidAccessKey => 'מפתח גישה לא תקין';

  @override
  String get unexpectedDecryptionError =>
      'אירעה שגיאה בלתי צפויה במהלך הפענוח.';

  @override
  String get fileMustContainExactly24Words =>
      'הקובץ חייב להכיל בדיוק 24 מילים.';

  @override
  String get errorReadingFile => 'שגיאה בקריאת הקובץ';

  @override
  String get encryptionTitle => 'הצפנה';

  @override
  String get accessKeyDecodeDescription =>
      'הזן את משפט השחזור בן 24 המילים שלך או טען קובץ .txt כדי לאפשר סנכרון ענן בצורה מאובטחת.';

  @override
  String get recoveryPhraseLabel => 'משפט שחזור';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => 'הדבק';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 מילים';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'נא להזין את משפט השחזור שלך';

  @override
  String get mustContainExactly24Words => 'חייב להכיל בדיוק 24 מילים';

  @override
  String get verify => 'אימות';

  @override
  String get orLabel => 'או';

  @override
  String get loadFromTxtFile => 'טען מקובץ .txt';

  @override
  String get saveAccessKey => 'שמור מפתח גישה';

  @override
  String get fileSavedSuccessfully => 'הקובץ נשמר בהצלחה.';

  @override
  String get accessKeyShareMessage => 'הנה מפתח הגישה שלך.';

  @override
  String get pleaseTryAgain => 'נסה שוב בבקשה.';

  @override
  String get copiedToClipboard => 'הועתק ללוח';

  @override
  String get accessKeyTitle => 'מפתח גישה';

  @override
  String get accessKeyDescription =>
      'שמור את המפתח הזה במקום בטוח. רק באמצעותו תוכל לגשת לנתונים המוצפנים שלך.';

  @override
  String get copy => 'העתק';

  @override
  String get downloadAsTextFile => 'הורד כקובץ טקסט';

  @override
  String get continueLabel => 'המשך';

  @override
  String get importantTitle => 'חשוב';

  @override
  String get accessKeyNoticePrimary =>
      'בעמוד הבא תראה סדרה של 24 מילים. זהו מפתח ההצפנה הייחודי והפרטי שלך, וזו הדרך היחידה לשחזר את הנתונים שלך במקרה של התנתקות, אובדן מכשיר או תקלה.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'אנחנו לא שומרים את המפתח. האחריות לשמור אותו במקום בטוח, מחוץ לאפליקציית $appName, היא שלך בלבד.';
  }

  @override
  String get showKeyConfirmation => 'אני מבין.\nהצג לי את המפתח.';

  @override
  String get storageAddedSuccessfully => 'האחסון נוסף בהצלחה';

  @override
  String get networkErrorDuringValidation => 'אירעה שגיאת רשת במהלך האימות.';

  @override
  String get verifyAndConnect => 'אמת והתחבר';

  @override
  String get requiredField => 'שדה חובה';

  @override
  String get providerKeysVerifiedLocally =>
      'המפתחות שלך נבדקים מקומית ומוצפנים לפני השליחה.';

  @override
  String get enterYourCredentials => 'הזן את פרטי ההתחברות שלך';

  @override
  String connectProvider(String provider) {
    return 'התחברות אל $provider';
  }

  @override
  String get deviceLimitReached => 'הגעת למספר המכשירים המרבי';

  @override
  String get pleaseTryAgainWithExclamation => 'נסה שוב בבקשה!';

  @override
  String get notThisDevice => 'לא המכשיר הזה!';

  @override
  String get confirmSignoutDeviceTitle => 'אישור ניתוק מכשיר';

  @override
  String get areYouSure => 'האם אתה בטוח?';

  @override
  String get cancel => 'ביטול';

  @override
  String get ok => 'אישור';

  @override
  String get noDeviceFound => 'לא נמצא מכשיר';

  @override
  String get backTooltip => 'חזרה';

  @override
  String get devicesTitle => 'מכשירים';

  @override
  String get longPressToDownload => 'לחץ לחיצה ארוכה כדי להוריד';

  @override
  String get fewItemsExistLocally => 'חלק מהפריטים עדיין קיימים באופן מקומי.';

  @override
  String selectedItemsCount(int count) {
    return 'נבחרו $count';
  }

  @override
  String get delete => 'מחק';

  @override
  String get info => 'מידע';

  @override
  String get download => 'הורד';

  @override
  String get archive => 'ארכיון';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'יומנים';

  @override
  String get settings => 'הגדרות';

  @override
  String get trash => 'אשפה';

  @override
  String get storage => 'אחסון';

  @override
  String get search => 'חיפוש';

  @override
  String get database => 'מסד נתונים';

  @override
  String get addFolderTitle => 'הוספת תיקייה';

  @override
  String get confirm => 'אישור';

  @override
  String get tapPlusToAddSyncFolder => 'הקש על + כדי להוסיף תיקיית סנכרון.';

  @override
  String get thisFolderIsEmpty => 'התיקייה הזו ריקה.';

  @override
  String get fileNotFound => 'הקובץ לא נמצא';

  @override
  String filePartsTitle(int count) {
    return 'חלקי קובץ ($count)';
  }

  @override
  String get fileDetailsTitle => 'פרטי קובץ';

  @override
  String get encryptedBackup => 'גיבוי מוצפן';

  @override
  String get sizeLabel => 'גודל';

  @override
  String get providerLabel => 'ספק';

  @override
  String get uploadedAtLabel => 'הועלה בתאריך';

  @override
  String get statusLabel => 'סטטוס';

  @override
  String get uploadedStatus => 'הועלה';

  @override
  String errorWithMessage(String message) {
    return 'שגיאה: $message';
  }

  @override
  String get noLogsAvailable => 'אין יומנים זמינים';

  @override
  String get searchLogsHint => 'חיפוש ביומנים...';

  @override
  String get clearLogs => 'נקה יומנים';

  @override
  String get searchWithMinThreeCharacters => 'חפש עם לפחות 3 תווים';

  @override
  String get typeBelowToSearch => 'הקלד למטה כדי לחפש';

  @override
  String get noResults => 'לא נמצאו תוצאות.';

  @override
  String get welcomeTitle => 'ברוך הבא';

  @override
  String signInToContinue(String appName) {
    return 'התחבר כדי להמשיך אל $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'נא להזין את כתובת האימייל שלך';

  @override
  String get pleaseEnterValidEmailAddress => 'נא להזין כתובת אימייל תקינה';

  @override
  String get emailAddressLabel => 'כתובת אימייל';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'שלח OTP שוב';

  @override
  String get sendOtp => 'שלח OTP';

  @override
  String get checkYourEmail => 'בדוק את האימייל שלך';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'שלחנו קוד בן 6 ספרות אל\n$email';
  }

  @override
  String get pleaseEnterOtp => 'נא להזין את ה-OTP';

  @override
  String get otpMustBeSixDigits => 'ה-OTP חייב להכיל 6 ספרות';

  @override
  String get enterOtpLabel => 'הזן OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'נסה את האימות שוב';

  @override
  String get verifyOtp => 'אמת OTP';

  @override
  String get useDifferentEmail => 'השתמש בכתובת אימייל אחרת';

  @override
  String get alreadySignedIn => 'כבר מחובר';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'שליחת ה-OTP נכשלה. נסה שוב בבקשה!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'אימות ה-OTP נכשל. נסה שוב בבקשה.';

  @override
  String get dbViewerTitle => 'מציג מסד נתונים';

  @override
  String get selectTableToViewData => 'בחר טבלה כדי לראות את הנתונים שלה';

  @override
  String get selectTable => 'בחר טבלה';

  @override
  String get permissionRequiredTitle => 'נדרשת הרשאה';

  @override
  String get storagePermissionSettingsDescription =>
      'כדי לגבות, לנהל ולאבטח את הקבצים שלך באופן אוטומטי ברקע, אנחנו צריכים גישה לאחסון במכשיר שלך. הנתונים שלך מוצפנים מקומית, כך שהפרטיות נשמרת במלואה. אפשר גישה כדי להמשיך.';

  @override
  String get openSettings => 'פתח הגדרות';

  @override
  String get storagePermissionRequiredToContinue =>
      'נדרשת הרשאת אחסון כדי להמשיך';

  @override
  String get secureLocalAccessTitle => 'גישה מקומית מאובטחת';

  @override
  String get storagePermissionPageDescription =>
      'כדי לעיין, להצפין ולגבות את הקבצים שלך באופן אוטומטי, דרושה לנו גישה לאחסון במכשיר שלך.';

  @override
  String get verifying => 'מאמת...';

  @override
  String get grantAccess => 'תן גישה';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'אחסון מוצפן בשיטת Zero-Knowledge';

  @override
  String requiresAppPro(String appName) {
    return 'נדרש $appName Pro.';
  }

  @override
  String get noStorageFound => 'לא נמצא אחסון';

  @override
  String get howToConnect => 'איך מתחברים';

  @override
  String get modify => 'ערוך';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total בשימוש';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'עד $size בחינם';
  }

  @override
  String get notConnected => 'לא מחובר';

  @override
  String get connect => 'התחבר';

  @override
  String get modifyStorageCapacityTitle => 'שינוי קיבולת אחסון';

  @override
  String get enterNewStorageLimitForProvider =>
      'הזן את מגבלת האחסון החדשה עבור הספק הזה.';

  @override
  String get sizePrefix => 'גודל: ';

  @override
  String get gbSuffix => ' ג״ב';

  @override
  String get pleaseEnterSize => 'נא להזין גודל';

  @override
  String get enterValidNumberGreaterThanOne => 'הזן מספר תקין גדול מ-1';

  @override
  String get submit => 'שלח';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'המינוי ל-$appName Pro הופעל בהצלחה!';
  }

  @override
  String get purchaseCancelledOrFailed => 'הרכישה בוטלה או נכשלה.';

  @override
  String get purchasesRestoredSuccessfully => 'הרכישות שוחזרו בהצלחה!';

  @override
  String get noActiveSubscriptionsFound => 'לא נמצאו מנויים פעילים.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'נהל את המנויים שלך דרך הגדרות המכשיר.';

  @override
  String get freePlanTitle => 'חינם';

  @override
  String get freeForeverPrice => '\$0.00 / לתמיד';

  @override
  String get freeBenefitProviderStorage => 'תהנה מאחסון חינמי מהספקים';

  @override
  String get freeBenefitSyncThreeDevices => 'סנכרון מאובטח עד 3 מכשירים';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - שנתי';
  }

  @override
  String get proBenefitModifyStorageLimit => 'שינוי מגבלת האחסון עבור כל ספק';

  @override
  String get proBenefitSyncTenDevices => 'סנכרון עד 10 מכשירים';

  @override
  String get restorePurchases => 'שחזור רכישות';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* המינוי משויך לחשבון האימייל ולא למכשיר';

  @override
  String get subscriptionExpiredTitle => 'המינוי פג תוקף';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'ההטבות של $appName Pro הושהו. חדש את המינוי למטה כדי לשחזר את מגבלות האחסון והסנכרון שלך.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro פעיל';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ שינוי מגבלות אחסון לכל ספק\n✓ סנכרון בין מכשירים עד 10 מכשירים';

  @override
  String get manageSubscription => 'ניהול מינוי';

  @override
  String get currentPlanBadge => 'נוכחי';

  @override
  String get subscribeNow => 'הצטרף עכשיו';

  @override
  String get subscribeOnMobileApp => 'הירשם דרך האפליקציה בנייד';

  @override
  String get recover => 'שחזר';

  @override
  String get empty => 'רוקן';

  @override
  String get noItems => 'אין פריטים.';
}
