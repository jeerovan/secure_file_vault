// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Persian (`fa`).
class AppLocalizationsFa extends AppLocalizations {
  AppLocalizationsFa([String locale = 'fa']) : super(locale);

  @override
  String get localSessionCleanupTitle => 'پاک کردن داده‌های محلی';

  @override
  String get localSessionCleanupDescription =>
      'نشست شما پایان یافته است. FiFe باید پیش از ورود دوباره، پاک کردن داده‌های محلی حساب را کامل کند. فایل‌های اصلی شما حفظ می‌شوند. برای تکمیل دوباره تلاش کنید.';

  @override
  String get localSessionCleanupInProgress =>
      'در حال پاک کردن داده‌های FiFe از این دستگاه…';

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'با ادامه دادن، شما با $terms و $privacy ما موافقت می‌کنید.';
  }

  @override
  String get termsOfService => 'شرایط استفاده';

  @override
  String get privacyPolicy => 'سیاست حریم خصوصی';

  @override
  String get andLabel => ' و ';

  @override
  String get theme => 'تم';

  @override
  String get themeTooltip => 'تم روز/شب';

  @override
  String get logging => 'گزارش‌ها';

  @override
  String get appLockTitle => 'قفل برنامه';

  @override
  String get appLockDescription =>
      'برای محافظت از FiFe از اثر انگشت، چهره یا پین دستگاه خود استفاده کنید.';

  @override
  String get appLockTimeout => 'زمان قفل شدن';

  @override
  String get appLockTimeoutDescription =>
      'پس از این مدت دور بودن از FiFe، احراز هویت لازم است. راه‌اندازی مجدد برنامه همیشه به احراز هویت نیاز دارد.';

  @override
  String get appLockAuthenticate => 'برای باز کردن FiFe احراز هویت کنید.';

  @override
  String get appLockChangeSettings =>
      'برای تغییر تنظیمات قفل برنامه احراز هویت کنید.';

  @override
  String get appLockAuthHint => 'هویت خود را تأیید کنید';

  @override
  String get appLocked => 'FiFe قفل است';

  @override
  String get appLockUnlock => 'باز کردن قفل';

  @override
  String get appLockUnavailable =>
      'احراز هویت دستگاه در دسترس نیست. در تنظیمات دستگاه پین، رمز عبور یا اطلاعات زیست‌سنجی تنظیم کنید و دوباره تلاش کنید.';

  @override
  String get appLockAuthenticationFailed =>
      'احراز هویت کامل نشد. دوباره تلاش کنید.';

  @override
  String get appLockStorageError =>
      'خواندن یا ذخیرهٔ تنظیمات قفل برنامه ممکن نشد. برای حفظ امنیت گاوصندوق دوباره تلاش کنید.';

  @override
  String get quickSyncNotificationSettingTitle => 'اعلان همگام‌سازی خودکار';

  @override
  String get autoSyncInterval => 'فاصلهٔ همگام‌سازی خودکار';

  @override
  String get autoSyncIntervalDescription =>
      'تا زمانی که اعلان همگام‌سازی خودکار فعال است، همگام‌سازی به‌صورت خودکار انجام می‌شود.';

  @override
  String syncIntervalMinutes(int minutes) {
    return '$minutes دقیقه';
  }

  @override
  String get autoSyncIntervalSaveError =>
      'ذخیرهٔ فاصلهٔ زمانی ممکن نشد. دوباره تلاش کنید.';

  @override
  String get autoSyncIntervalApplyError =>
      'فاصلهٔ زمانی ذخیره شد. برای اعمال آن، اعلان همگام‌سازی خودکار را خاموش و دوباره روشن کنید.';

  @override
  String get sync => 'همگام‌سازی';

  @override
  String get quickSyncNotificationTitle => 'سرویس همگام‌سازی فایل‌ها';

  @override
  String quickSyncNotificationText(int minutes) {
    return 'اجرا هر $minutes دقیقه';
  }

  @override
  String get quickSyncNotificationInProgress => 'در حال انجام...';

  @override
  String get reportIssue => 'گزارش مشکل';

  @override
  String get sourceCode => 'کد منبع';

  @override
  String get desktopApp => 'نسخه دسکتاپ';

  @override
  String get mobileApp => 'نسخه موبایل';

  @override
  String get leaveReview => 'ثبت نظر';

  @override
  String get share => 'اشتراک‌گذاری';

  @override
  String get versionLabel => 'نسخه: ';

  @override
  String get loading => 'در حال بارگذاری...';

  @override
  String get signOut => 'خروج از حساب';

  @override
  String get settingsPageTitle => 'تنظیمات';

  @override
  String get language => 'زبان';

  @override
  String get tapToSelect => 'برای انتخاب لمس کنید';

  @override
  String get appTagline => 'قایق خصوصی فایل‌های شما';

  @override
  String get onboardingPurposeDescription =>
      'یک سرویس متن‌باز ذخیره‌سازی ابری با معماری zero-trust. داده‌های شما پیش از خروج از دستگاه، به‌صورت محلی رمزگذاری می‌شوند.';

  @override
  String get failedToFetch => 'دریافت اطلاعات ناموفق بود.';

  @override
  String get supportedStorageTitle => 'فضاهای ذخیره‌سازی پشتیبانی‌شده';

  @override
  String get supportedStorageDescription =>
      'ارائه‌دهنده‌های دلخواهتان را وصل کنید. همین حالا با 1 گیگابایت فضای امن و رایگان FiFe شروع کنید.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'شروع فوری پشتیبان‌گیری';

  @override
  String get freeStorageSizeOneGb => '1.0 گیگابایت';

  @override
  String get freeLabel => 'رایگان';

  @override
  String get providerStorageDisclaimer =>
      '* فضای رایگان طبق اطلاعات درج‌شده در وب‌سایت ارائه‌دهنده. پرداخت به‌ازای مصرف برای ارائه‌دهنده‌های سازگار.';

  @override
  String get whyUseFifeTitle => 'چرا FiFe؟';

  @override
  String get claimFreeCloudStorageTitle => 'استفاده از فضای ابری رایگان';

  @override
  String get claimFreeCloudStorageDescription =>
      'با اتصال چند ارائه‌دهنده ابری، فضای بیشتری در اختیار داشته باشید. از طرح‌های رایگان آن‌ها در یک برنامه یکپارچه و امن استفاده کنید.';

  @override
  String get topNotchSecurityTitle => 'امنیت در بالاترین سطح';

  @override
  String get topNotchSecurityDescription =>
      'با استفاده از رمزنگاری پیشرفته Sodium. تمام فرایند رمزگذاری و رمزگشایی به‌طور کامل روی دستگاه شما انجام می‌شود.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'کنترل کامل داده‌های خود را در همه ارائه‌دهنده‌های فضای ابری حفظ کنید. با حساب‌های خودتان از فضای رمزگذاری‌شده استفاده کنید.';

  @override
  String get payAsYouGoStorageTitle => 'پرداخت فقط به‌اندازه مصرف.';

  @override
  String get payAsYouGoStorageDescription =>
      'فقط برای فضای استفاده‌شده نزد ارائه‌دهنده‌های سازگار هزینه پرداخت کنید. بدون واسطه و بدون قفل شدن داده‌ها.';

  @override
  String get zeroKnowledgePrivacyTitle => 'حریم خصوصی Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'داده‌های شما پیش از خروج از دستگاه قفل می‌شوند. ما نمی‌توانیم فایل‌های شما را ببینیم، بخوانیم یا بررسی کنیم.';

  @override
  String get localSelectionTitle => '1. انتخاب محلی';

  @override
  String get localSelectionDescription =>
      'شما یک پوشه را انتخاب می‌کنید. تمام پردازش‌ها با امنیت کامل روی دستگاه شما آغاز می‌شود.';

  @override
  String get metadataEncryptionTitle => '2. رمزگذاری فراداده';

  @override
  String get metadataEncryptionDescription =>
      'اطلاعات فایل مانند نام، نوع و اندازه، پیش از ارسال به سرور رمزگذاری می‌شوند.';

  @override
  String get contentEncryptionTitle => '3. رمزگذاری محتوا';

  @override
  String get contentEncryptionDescription =>
      'محتوای اصلی فایل پیش از بارگذاری در فضای ابری، تکه‌تکه و رمزگذاری می‌شود.';

  @override
  String get blindServerTitle => '4. سرور ناآگاه';

  @override
  String get blindServerDescription =>
      'سرورهای ما هیچ دانشی از داده‌های شما ندارند. ما فقط داده‌های رمزگذاری‌شده را می‌بینیم و این یعنی حریم خصوصی کامل.';

  @override
  String get dontTrustVerifyTitle => 'اعتماد نکنید، بررسی کنید.';

  @override
  String get openSourceVerificationDescription =>
      '100٪ متن‌باز. می‌توانید کد را بررسی کنید و دقیقاً ببینید فایل‌هایتان چگونه رمزگذاری می‌شوند.';

  @override
  String get getStarted => 'شروع کنید';

  @override
  String get next => 'بعدی';

  @override
  String get unauthorized => 'غیرمجاز';

  @override
  String get tryAgain => 'تلاش دوباره';

  @override
  String get errorTitle => 'خطا';

  @override
  String get failureTitle => 'ناموفق';

  @override
  String get invalidWordList => 'فهرست واژه‌ها معتبر نیست';

  @override
  String get invalidAccessKey => 'کلید دسترسی معتبر نیست';

  @override
  String get unexpectedDecryptionError =>
      'هنگام رمزگشایی یک خطای غیرمنتظره رخ داد.';

  @override
  String get fileMustContainExactly24Words =>
      'فایل باید دقیقاً شامل 24 کلمه باشد.';

  @override
  String get errorReadingFile => 'خطا در خواندن فایل';

  @override
  String get encryptionTitle => 'رمزگذاری';

  @override
  String get accessKeyDecodeDescription =>
      'عبارت بازیابی 24 کلمه‌ای خود را وارد کنید یا یک فایل .txt بارگذاری کنید تا همگام‌سازی ابری به‌صورت امن فعال شود.';

  @override
  String get recoveryPhraseLabel => 'عبارت بازیابی';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => 'چسباندن';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 کلمه';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'لطفاً عبارت بازیابی را وارد کنید';

  @override
  String get mustContainExactly24Words => 'باید دقیقاً شامل 24 کلمه باشد';

  @override
  String get verify => 'تأیید';

  @override
  String get orLabel => 'یا';

  @override
  String get loadFromTxtFile => 'بارگذاری از فایل .txt';

  @override
  String get saveAccessKey => 'ذخیره کلید دسترسی';

  @override
  String get fileSavedSuccessfully => 'فایل با موفقیت ذخیره شد.';

  @override
  String get accessKeyShareMessage => 'این هم کلید دسترسی شما.';

  @override
  String get pleaseTryAgain => 'لطفاً دوباره تلاش کنید.';

  @override
  String get copiedToClipboard => 'در کلیپ‌بورد کپی شد';

  @override
  String get accessKeyTitle => 'کلید دسترسی';

  @override
  String get accessKeyDescription =>
      'لطفاً این کلید را در جایی امن نگه دارید. فقط با این کلید می‌توانید به داده‌های رمزگذاری‌شده خود دسترسی داشته باشید.';

  @override
  String get copy => 'کپی';

  @override
  String get downloadAsTextFile => 'دانلود به‌صورت فایل متنی';

  @override
  String get continueLabel => 'ادامه';

  @override
  String get importantTitle => 'مهم';

  @override
  String get accessKeyNoticePrimary =>
      'در صفحه بعد، مجموعه‌ای از 24 کلمه را می‌بینید. این کلید رمزگذاری خصوصی و منحصربه‌فرد شماست و تنها راه بازیابی اطلاعات شما در صورت خروج از حساب، گم شدن دستگاه یا خرابی آن است.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'ما این کلید را ذخیره نمی‌کنیم. نگهداری آن در محلی امن و خارج از برنامه $appName کاملاً بر عهده شماست.';
  }

  @override
  String get showKeyConfirmation => 'متوجه شدم.\nکلید را به من نشان بده.';

  @override
  String get storageAddedSuccessfully => 'فضای ذخیره‌سازی با موفقیت اضافه شد';

  @override
  String get networkErrorDuringValidation =>
      'هنگام اعتبارسنجی خطای شبکه رخ داد.';

  @override
  String get verifyAndConnect => 'تأیید و اتصال';

  @override
  String get requiredField => 'ضروری';

  @override
  String get providerKeysVerifiedLocally =>
      'کلیدهای شما به‌صورت محلی بررسی و پیش از ارسال رمزگذاری می‌شوند.';

  @override
  String get enterYourCredentials => 'اطلاعات ورود خود را وارد کنید';

  @override
  String connectProvider(String provider) {
    return 'اتصال $provider';
  }

  @override
  String get deviceLimitReached => 'به سقف تعداد دستگاه‌ها رسیده‌اید';

  @override
  String get pleaseTryAgainWithExclamation => 'لطفاً دوباره تلاش کنید!';

  @override
  String get notThisDevice => 'نه این دستگاه!';

  @override
  String get confirmSignoutDeviceTitle => 'تأیید خروج دستگاه';

  @override
  String get areYouSure => 'مطمئن هستید؟';

  @override
  String get cancel => 'انصراف';

  @override
  String get ok => 'باشه';

  @override
  String get noDeviceFound => 'دستگاهی پیدا نشد';

  @override
  String get backTooltip => 'بازگشت';

  @override
  String get devicesTitle => 'دستگاه‌ها';

  @override
  String get longPressToDownload => 'برای دانلود، لمس طولانی کنید';

  @override
  String get fewItemsExistLocally =>
      'بعضی از موارد هنوز به‌صورت محلی وجود دارند.';

  @override
  String selectedItemsCount(int count) {
    return '$count مورد انتخاب شد';
  }

  @override
  String get delete => 'حذف';

  @override
  String get info => 'اطلاعات';

  @override
  String get download => 'دانلود';

  @override
  String get archive => 'بایگانی';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'گزارش‌ها';

  @override
  String get settings => 'تنظیمات';

  @override
  String get trash => 'زباله‌دان';

  @override
  String get storage => 'فضای ذخیره‌سازی';

  @override
  String get search => 'جستجو';

  @override
  String get database => 'پایگاه داده';

  @override
  String get addFolderTitle => 'افزودن پوشه';

  @override
  String get confirm => 'تأیید';

  @override
  String get tapPlusToAddSyncFolder =>
      'برای افزودن پوشه همگام‌سازی، + را لمس کنید.';

  @override
  String get thisFolderIsEmpty => 'این پوشه خالی است.';

  @override
  String get fileNotFound => 'فایل پیدا نشد';

  @override
  String filePartsTitle(int count) {
    return 'بخش‌های فایل ($count)';
  }

  @override
  String get fileDetailsTitle => 'جزئیات فایل';

  @override
  String get encryptedBackup => 'نسخه پشتیبان رمزگذاری‌شده';

  @override
  String get sizeLabel => 'اندازه';

  @override
  String get providerLabel => 'ارائه‌دهنده';

  @override
  String get uploadedAtLabel => 'تاریخ بارگذاری';

  @override
  String get statusLabel => 'وضعیت';

  @override
  String get uploadedStatus => 'بارگذاری شد';

  @override
  String errorWithMessage(String message) {
    return 'خطا: $message';
  }

  @override
  String get noLogsAvailable => 'گزارشی موجود نیست';

  @override
  String get searchLogsHint => 'جستجو در گزارش‌ها...';

  @override
  String get clearLogs => 'پاک کردن گزارش‌ها';

  @override
  String get searchWithMinThreeCharacters => 'با حداقل 3 حرف جستجو کنید';

  @override
  String get typeBelowToSearch => 'برای جستجو، پایین بنویسید';

  @override
  String get noResults => 'نتیجه‌ای پیدا نشد.';

  @override
  String get welcomeTitle => 'خوش آمدید';

  @override
  String signInToContinue(String appName) {
    return 'برای ادامه در $appName وارد شوید';
  }

  @override
  String get pleaseEnterYourEmail => 'لطفاً ایمیل خود را وارد کنید';

  @override
  String get pleaseEnterValidEmailAddress =>
      'لطفاً یک آدرس ایمیل معتبر وارد کنید';

  @override
  String get emailAddressLabel => 'آدرس ایمیل';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'ارسال دوباره OTP';

  @override
  String get sendOtp => 'ارسال OTP';

  @override
  String get checkYourEmail => 'ایمیل خود را بررسی کنید';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'یک کد 6 رقمی به\n$email\nارسال کردیم';
  }

  @override
  String get pleaseEnterOtp => 'لطفاً OTP را وارد کنید';

  @override
  String get otpMustBeSixDigits => 'OTP باید 6 رقمی باشد';

  @override
  String get enterOtpLabel => 'وارد کردن OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'تلاش دوباره برای تأیید';

  @override
  String get verifyOtp => 'تأیید OTP';

  @override
  String get useDifferentEmail => 'استفاده از ایمیل دیگر';

  @override
  String get alreadySignedIn => 'قبلاً وارد شده‌اید';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'ارسال OTP ناموفق بود. لطفاً دوباره تلاش کنید!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'تأیید OTP ناموفق بود. لطفاً دوباره تلاش کنید.';

  @override
  String get dbViewerTitle => 'نمایشگر پایگاه داده';

  @override
  String get selectTableToViewData => 'برای دیدن داده‌ها، یک جدول انتخاب کنید';

  @override
  String get selectTable => 'انتخاب جدول';

  @override
  String get permissionRequiredTitle => 'نیاز به مجوز';

  @override
  String get storagePermissionSettingsDescription =>
      'برای پشتیبان‌گیری خودکار، مدیریت و محافظت از فایل‌ها در پس‌زمینه، به دسترسی فضای ذخیره‌سازی دستگاه شما نیاز داریم. داده‌های شما به‌صورت محلی رمزگذاری می‌شوند تا حریم خصوصی کامل حفظ شود. برای ادامه، لطفاً دسترسی را فعال کنید.';

  @override
  String get openSettings => 'باز کردن تنظیمات';

  @override
  String get secureLocalAccessTitle => 'دسترسی محلی امن';

  @override
  String get storagePermissionPageDescription =>
      'برای مرور، رمزگذاری و پشتیبان‌گیری خودکار از فایل‌ها، به دسترسی فضای ذخیره‌سازی دستگاه شما نیاز داریم.';

  @override
  String get verifying => 'در حال بررسی...';

  @override
  String get grantAccess => 'اعطای دسترسی';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'فضای ذخیره‌سازی رمزگذاری‌شده Zero-Knowledge';

  @override
  String get notificationPermissionTitle => 'دسترسی به اعلان‌ها';

  @override
  String get notificationPermissionPageDescription =>
      'برای همگام‌سازی سریع و بارگذاری فایل‌های شما در پس‌زمینه از طریق پنل اعلان‌ها، به اجازه نمایش اعلان نیاز داریم. هر زمان بخواهید می‌توانید آن را از تنظیمات غیرفعال کنید.';

  @override
  String get notificationPermissionGrantButton => 'اجازه به اعلان‌ها';

  @override
  String get notificationPermissionSettingsDescription =>
      'اعلان‌ها برای ارائه قابلیت همگام‌سازی سریع از طریق پنل اعلان‌ها ضروری هستند. لطفاً آن‌ها را در تنظیمات سیستم فعال کنید تا مطمئن شوید همه داده‌های شما بارگذاری می‌شوند.';

  @override
  String requiresAppPro(String appName) {
    return 'نیاز به $appName Pro دارد.';
  }

  @override
  String get noStorageFound => 'فضای ذخیره‌سازی پیدا نشد';

  @override
  String get howToConnect => 'روش اتصال';

  @override
  String get modify => 'ویرایش';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total استفاده شده';
  }

  @override
  String percentageLabel(String value) {
    return '%$value';
  }

  @override
  String upToFree(String size) {
    return 'تا $size رایگان';
  }

  @override
  String get notConnected => 'متصل نشده';

  @override
  String get connect => 'اتصال';

  @override
  String get modifyStorageCapacityTitle => 'ویرایش ظرفیت فضای ذخیره‌سازی';

  @override
  String get enterNewStorageLimitForProvider =>
      'مقدار جدید فضای ذخیره‌سازی این ارائه‌دهنده را وارد کنید.';

  @override
  String get sizePrefix => 'اندازه: ';

  @override
  String get gbSuffix => ' گیگابایت';

  @override
  String get pleaseEnterSize => 'لطفاً یک مقدار وارد کنید';

  @override
  String get enterValidNumberGreaterThanOne =>
      'یک عدد معتبر بزرگ‌تر از 1 وارد کنید';

  @override
  String get submit => 'ثبت';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'اشتراک $appName Pro با موفقیت فعال شد!';
  }

  @override
  String get purchaseCancelledOrFailed => 'خرید لغو شد یا انجام نشد.';

  @override
  String get purchasesRestoredSuccessfully =>
      'خریدهای قبلی با موفقیت بازیابی شدند!';

  @override
  String get noActiveSubscriptionsFound => 'اشتراک فعالی پیدا نشد.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'لطفاً اشتراک‌ها را از تنظیمات دستگاه خود مدیریت کنید.';

  @override
  String get freePlanTitle => 'رایگان';

  @override
  String get freeForeverPrice => '\$0.00 / همیشگی';

  @override
  String get freeBenefitProviderStorage =>
      'استفاده از فضای رایگان ارائه‌دهنده‌ها';

  @override
  String get freeBenefitSyncThreeDevices => 'همگام‌سازی امن تا 3 دستگاه';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - سالانه';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'ویرایش محدودیت فضای هر ارائه‌دهنده';

  @override
  String get proBenefitSyncTenDevices => 'همگام‌سازی تا 10 دستگاه';

  @override
  String get restorePurchases => 'بازیابی خریدها';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* اشتراک به حساب ایمیل شما متصل است، نه به دستگاه';

  @override
  String get subscriptionExpiredTitle => 'اشتراک منقضی شده است';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'مزایای $appName Pro شما فعلاً متوقف شده‌اند. برای بازگرداندن محدودیت‌های فضا و همگام‌سازی دستگاه‌ها، در پایین اشتراک خود را تمدید کنید.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro فعال است';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ ویرایش محدودیت فضای هر ارائه‌دهنده\n✓ همگام‌سازی بین دستگاه‌ها تا 10 دستگاه';

  @override
  String get manageSubscription => 'مدیریت اشتراک';

  @override
  String get currentPlanBadge => 'فعلی';

  @override
  String get subscribeNow => 'همین حالا مشترک شوید';

  @override
  String get subscribeOnMobileApp => 'از نسخه موبایل مشترک شوید';

  @override
  String get recover => 'بازیابی';

  @override
  String get empty => 'خالی کردن';

  @override
  String get noItems => 'موردی وجود ندارد.';

  @override
  String get lostRecoveryPhrase => 'عبارت بازیابی را گم کرده‌ام';

  @override
  String get lostRecoveryIntro =>
      'اگر دستگاه دیگری هنوز وارد حساب است، پیش از شروع دوباره عبارت بازیابی را از آن صادر کنید.';

  @override
  String get lostRecoveryDeleteConsequence =>
      'خزانه فعلی FiFe، فایل‌های پشتیبان‌گیری‌شده و کلیدهای رمزگذاری قدیمی شما برای همیشه حذف خواهند شد.';

  @override
  String get lostRecoveryDevicesConsequence =>
      'ثبت همهٔ دستگاه‌های فعلی حذف خواهد شد.';

  @override
  String get lostRecoveryLogoutConsequence =>
      'دستگاه‌های دیگر وقتی آنلاین شوند و حذف شدن خود را تشخیص دهند، از حساب خارج شده و داده‌های محلی FiFe را پاک می‌کنند.';

  @override
  String get lostRecoveryKeepConsequence =>
      'حساب ایمیل، اشتراک، اتصال‌های فضای ذخیره‌سازی ابری و اطلاعات ورود ارائه‌دهندگان حفظ می‌شوند. فایل‌های پوشه‌های شخصی شما خارج از FiFe نیز حفظ خواهند شد.';

  @override
  String get lostRecoveryWaitConsequence =>
      'خزانهٔ جدید تا تأیید حذف ابری قفل می‌ماند. این کار ممکن است ۱۵ دقیقه یا بیشتر طول بکشد. می‌توانید FiFe را ببندید و بعداً ادامه دهید.';

  @override
  String get lostRecoveryNewPhraseConsequence =>
      'در این دستگاه وارد حساب می‌مانید. پس از تأیید حذف، یک عبارت بازیابی جدید 24 کلمه‌ای ایجاد و ذخیره کنید.';

  @override
  String get recoveryResetUnavailable =>
      'بازنشانی گاوصندوق موقتاً در دسترس نیست. لطفاً بعداً دوباره تلاش کنید.';

  @override
  String get recoveryResetSigninRequired =>
      'پیش از بازنشانی صندوق، دوباره وارد شوید تا نشست شما تأیید شود.';

  @override
  String get recoveryResetContinue => 'ادامهٔ بازنشانی';

  @override
  String get recoveryResetConfirmTitle => 'خزانهٔ FiFe برای همیشه حذف شود؟';

  @override
  String get recoveryResetConfirmBody =>
      'این کار برگشت‌پذیر نیست. عبارت بازیابی فعلی دیگر کار نمی‌کند و همهٔ دستگاه‌هایتان حذف می‌شوند.';

  @override
  String get recoveryResetDelete => 'حذف خزانه و شروع دوباره';

  @override
  String get recoveryResetPendingTitle => 'در حال حذف خزانهٔ قبلی';

  @override
  String get recoveryResetPendingBody =>
      'FiFe در حال تأیید حذف ابری است. می‌توانید برنامه را ببندید و بعداً برگردید.';

  @override
  String recoveryResetWaitUntil(String when) {
    return 'تأیید نمی‌تواند پیش از $when پایان یابد.';
  }

  @override
  String get recoveryResetStorageBlocked =>
      'حذف ابری به رسیدگی نیاز دارد. دسترسی و مجوز حذف فضای ذخیره‌سازی متصل را بازگردانید و دوباره تلاش کنید.';

  @override
  String get recoveryResetSignin => 'برای ادامهٔ بازنشانی دوباره وارد شوید.';

  @override
  String recoveryResetSigninAs(String email) {
    return 'برای ادامهٔ بازنشانی با $email وارد شوید.';
  }

  @override
  String get recoveryResetNeedsConfirmation =>
      'برای ادامه، بازنشانی را تأیید کنید. FiFe بررسی می‌کند که آیا از قبل شروع شده است.';

  @override
  String get recoveryResetConfirmationWait =>
      'تأیید قبلی هنوز معتبر است. پیش از شروع تأیید جدید، پس از پایان اعتبار آن دوباره بررسی کنید.';

  @override
  String recoveryResetConfirmationUntil(String when) {
    return 'پس از $when دوباره بررسی کنید.';
  }

  @override
  String get recoveryResetMissingKeys =>
      'کلیدهای بازیابی جدید روی این دستگاه موجود نیستند. در دستگاهی که بازنشانی را آغاز کرده ادامه دهید. اگر کلیدها گم شده‌اند، منتظر پایان حذف بمانید، سپس وارد شوید و دوباره «عبارت بازیابی را گم کرده‌ام» را انتخاب کنید.';

  @override
  String get recoveryResetDiscard => 'بازگشت به ورود';

  @override
  String get recoveryResetDiscardBody =>
      'این کار تنظیمات ناتمام بازیابی را روی این دستگاه پاک می‌کند. پس از ورود به عبارت بازیابی جدید یا بازنشانی دوبارهٔ خزانه نیاز دارید.';

  @override
  String get recoveryPhraseSaved => 'عبارت بازیابی جدیدم را ذخیره کرده‌ام.';

  @override
  String get recoveryResetStarting => 'در حال شروع بازنشانی…';

  @override
  String get sessionExpiredRetained =>
      'نشست ورود شما منقضی شده است. برای باز کردن گاوصندوق دوباره وارد شوید. داده‌های محلی شما حفظ می‌شوند.';

  @override
  String get signinVerifiedContinue =>
      'ایمیل شما تأیید شده است. برای تکمیل ورود ادامه دهید.';

  @override
  String get noSupportedApplication =>
      'برنامهٔ سازگاری برای نمایش این فایل وجود ندارد.';

  @override
  String get fileAccessUnavailable =>
      'دسترسی به این فایل ممکن نیست. مجوزهای پوشه را بررسی کنید و دوباره تلاش کنید.';

  @override
  String get unableToOpenFile =>
      'باز کردن این فایل ممکن نیست. لطفاً دوباره تلاش کنید.';

  @override
  String get fileNotAvailable =>
      'این فایل در این دستگاه یا در یک نسخهٔ پشتیبان کامل‌شده موجود نیست.';

  @override
  String get downloadRecoveryPhrase => 'دانلود عبارت بازیابی';

  @override
  String get recoveryPhraseExportHint =>
      'برای مشاهده، کپی یا ذخیرهٔ عبارت بازیابی، هویت خود را تأیید کنید.';

  @override
  String get recoveryPhraseExportAuth =>
      'برای مشاهدهٔ عبارت بازیابی، هویت خود را تأیید کنید';

  @override
  String get recoveryPhraseExportWarning =>
      'هر کسی این کلمات را داشته باشد می‌تواند خزانهٔ شما را باز کند. نسخهٔ خود را خصوصی و خارج از FiFe نگه دارید.';

  @override
  String get recoveryPhraseUnavailable =>
      'عبارت بازیابی بارگیری نشد. دوباره تلاش کنید یا از نسخهٔ پشتیبان ذخیره‌شده یا دستگاه دیگری که در آن وارد شده‌اید استفاده کنید.';
}
