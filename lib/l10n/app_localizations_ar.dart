// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'بالمتابعة، فإنك توافق على $terms و$privacy.';
  }

  @override
  String get termsOfService => 'شروط الخدمة';

  @override
  String get privacyPolicy => 'سياسة الخصوصية';

  @override
  String get andLabel => ' و ';

  @override
  String get theme => 'المظهر';

  @override
  String get themeTooltip => 'مظهر النهار/الليل';

  @override
  String get logging => 'سجل النظام';

  @override
  String get quickSyncNotificationSettingTitle => 'إشعارات المزامنة السريعة';

  @override
  String get quickSyncNotificationTitle => 'خدمة مزامنة الملفات';

  @override
  String get quickSyncNotificationText => 'اضغط على الزر أدناه للمزامنة';

  @override
  String get quickSyncNotificationButton => 'مزامنة الآن';

  @override
  String get quickSyncNotificationInProgress => 'جارٍ المزامنة...';

  @override
  String get reportIssue => 'الإبلاغ عن مشكلة';

  @override
  String get sourceCode => 'الشفرة المصدرية';

  @override
  String get desktopApp => 'تطبيق الكمبيوتر';

  @override
  String get mobileApp => 'تطبيق الجوال';

  @override
  String get leaveReview => 'اترك تقييمًا';

  @override
  String get share => 'مشاركة';

  @override
  String get versionLabel => 'الإصدار: ';

  @override
  String get loading => 'جارٍ التحميل...';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get settingsPageTitle => 'الإعدادات';

  @override
  String get language => 'اللغة';

  @override
  String get tapToSelect => 'اضغط للاختيار';

  @override
  String get appTagline => 'عبّارتك الخاصة لملفاتك';

  @override
  String get onboardingPurposeDescription =>
      'خدمة تخزين سحابي مفتوحة المصدر مبنية بهندسة عدم الثقة. يتم تشفير بياناتك على جهازك قبل أن تغادره.';

  @override
  String get failedToFetch => 'تعذر التحميل.';

  @override
  String get supportedStorageTitle => 'مساحات التخزين المدعومة';

  @override
  String get supportedStorageDescription =>
      'اربط مزوّديك المفضلين. وابدأ فورًا مع 1 جيجابايت من التخزين الآمن المجاني المدمج في FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'ابدأ النسخ الاحتياطي فورًا';

  @override
  String get freeStorageSizeOneGb => '1.0 جيجابايت';

  @override
  String get freeLabel => 'مجاني';

  @override
  String get providerStorageDisclaimer =>
      '* التخزين المجاني حسب ما هو مذكور في موقع المزوّد. الدفع حسب الاستخدام مع المزوّدين المتوافقين.';

  @override
  String get whyUseFifeTitle => 'لماذا تستخدم FiFe؟';

  @override
  String get claimFreeCloudStorageTitle => 'استفد من التخزين السحابي المجاني';

  @override
  String get claimFreeCloudStorageDescription =>
      'زد المساحة المتاحة لك عبر ربط أكثر من مزوّد سحابي. واستفد بأمان من خططهم المجانية في تطبيق واحد موحّد.';

  @override
  String get topNotchSecurityTitle => 'حماية بمستوى عالٍ';

  @override
  String get topNotchSecurityDescription =>
      'مدعوم بتقنيات Sodium المتقدمة للتشفير. تتم كل عمليات التشفير وفك التشفير محليًا بالكامل على جهازك.';

  @override
  String get bringYourOwnKeyTitle => 'استخدم مفتاحك الخاص (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'احتفظ بالتحكم الكامل في بياناتك عبر جميع مزوّدي التخزين السحابي. واستخدم التخزين المشفّر من خلال حساباتك الخاصة.';

  @override
  String get payAsYouGoStorageTitle => 'الدفع حسب الاستخدام للتخزين.';

  @override
  String get payAsYouGoStorageDescription =>
      'ادفع فقط مقابل المساحة التي تستخدمها مع المزوّدين المتوافقين. بلا وسيط، وبلا احتجاز لبياناتك.';

  @override
  String get zeroKnowledgePrivacyTitle => 'خصوصية دون معرفة';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'تُقفل بياناتك على جهازك قبل أن تغادره. لا يمكننا رؤية ملفاتك أو قراءتها أو فحصها.';

  @override
  String get localSelectionTitle => '1. اختيار محلي';

  @override
  String get localSelectionDescription =>
      'أنت تختار المجلد. وتبدأ كل المعالجة بأمان على جهازك المحلي.';

  @override
  String get metadataEncryptionTitle => '2. تشفير البيانات الوصفية';

  @override
  String get metadataEncryptionDescription =>
      'يتم تشفير معلومات الملف، مثل الاسم والنوع والحجم، قبل إرسالها إلى الخادم.';

  @override
  String get contentEncryptionTitle => '3. تشفير المحتوى';

  @override
  String get contentEncryptionDescription =>
      'يتم تقسيم محتوى الملف نفسه وتشفيره قبل رفعه إلى التخزين السحابي.';

  @override
  String get blindServerTitle => '4. خادم لا يرى البيانات';

  @override
  String get blindServerDescription =>
      'خوادمنا لا تعرف شيئًا عن بياناتك. نحن نرى فقط بيانات مشفّرة، مما يضمن خصوصية كاملة.';

  @override
  String get dontTrustVerifyTitle => 'لا تثق، بل تحقّق.';

  @override
  String get openSourceVerificationDescription =>
      'مفتوح المصدر 100%. يمكنك مراجعة الشفرة لترى بنفسك كيف تُشفَّر ملفاتك.';

  @override
  String get getStarted => 'ابدأ الآن';

  @override
  String get next => 'التالي';

  @override
  String get unauthorized => 'غير مصرح';

  @override
  String get tryAgain => 'حاول مرة أخرى';

  @override
  String get errorTitle => 'خطأ';

  @override
  String get failureTitle => 'فشل';

  @override
  String get invalidWordList => 'قائمة الكلمات غير صحيحة';

  @override
  String get invalidAccessKey => 'مفتاح الوصول غير صحيح';

  @override
  String get unexpectedDecryptionError => 'حدث خطأ غير متوقع أثناء فك التشفير.';

  @override
  String get fileMustContainExactly24Words =>
      'يجب أن يحتوي الملف على 24 كلمة بالضبط.';

  @override
  String get errorReadingFile => 'خطأ في قراءة الملف';

  @override
  String get encryptionTitle => 'التشفير';

  @override
  String get accessKeyDecodeDescription =>
      'أدخل عبارة الاسترداد المكوّنة من 24 كلمة أو حمّل ملف .txt لتفعيل المزامنة السحابية بأمان.';

  @override
  String get recoveryPhraseLabel => 'عبارة الاسترداد';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => 'لصق';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 كلمة';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'يرجى إدخال عبارة الاسترداد';

  @override
  String get mustContainExactly24Words => 'يجب أن تحتوي على 24 كلمة بالضبط';

  @override
  String get verify => 'تحقق';

  @override
  String get orLabel => 'أو';

  @override
  String get loadFromTxtFile => 'تحميل من ملف .txt';

  @override
  String get saveAccessKey => 'حفظ مفتاح الوصول';

  @override
  String get fileSavedSuccessfully => 'تم حفظ الملف بنجاح.';

  @override
  String get accessKeyShareMessage => 'إليك مفتاح الوصول الخاص بك.';

  @override
  String get pleaseTryAgain => 'يرجى المحاولة مرة أخرى.';

  @override
  String get copiedToClipboard => 'تم النسخ إلى الحافظة';

  @override
  String get accessKeyTitle => 'مفتاح الوصول';

  @override
  String get accessKeyDescription =>
      'يرجى حفظ هذا المفتاح في مكان آمن. فهو الوسيلة الوحيدة للوصول إلى بياناتك المشفّرة.';

  @override
  String get copy => 'نسخ';

  @override
  String get downloadAsTextFile => 'تنزيل كملف نصي';

  @override
  String get continueLabel => 'متابعة';

  @override
  String get importantTitle => 'مهم';

  @override
  String get accessKeyNoticePrimary =>
      'في الصفحة التالية سترى 24 كلمة. هذا هو مفتاح التشفير الخاص والفريد لك، وهو الطريقة الوحيدة لاستعادة بياناتك عند تسجيل الخروج أو فقدان الجهاز أو تعطله.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'نحن لا نخزن هذا المفتاح. وتقع عليك مسؤولية الاحتفاظ به في مكان آمن خارج تطبيق $appName.';
  }

  @override
  String get showKeyConfirmation => 'أفهم ذلك.\nأرني المفتاح.';

  @override
  String get storageAddedSuccessfully => 'تمت إضافة مساحة التخزين بنجاح';

  @override
  String get networkErrorDuringValidation => 'حدث خطأ في الشبكة أثناء التحقق.';

  @override
  String get verifyAndConnect => 'تحقق واتصل';

  @override
  String get requiredField => 'مطلوب';

  @override
  String get providerKeysVerifiedLocally =>
      'يتم التحقق من مفاتيحك محليًا وتشفيرها قبل الإرسال.';

  @override
  String get enterYourCredentials => 'أدخل بياناتك';

  @override
  String connectProvider(String provider) {
    return 'ربط $provider';
  }

  @override
  String get deviceLimitReached => 'تم الوصول إلى الحد الأقصى للأجهزة';

  @override
  String get pleaseTryAgainWithExclamation => 'يرجى المحاولة مرة أخرى!';

  @override
  String get notThisDevice => 'ليس هذا الجهاز!';

  @override
  String get confirmSignoutDeviceTitle => 'تأكيد تسجيل خروج الجهاز';

  @override
  String get areYouSure => 'هل أنت متأكد؟';

  @override
  String get cancel => 'إلغاء';

  @override
  String get ok => 'موافق';

  @override
  String get noDeviceFound => 'لم يتم العثور على أجهزة';

  @override
  String get backTooltip => 'رجوع';

  @override
  String get devicesTitle => 'الأجهزة';

  @override
  String get longPressToDownload => 'اضغط مطولًا للتنزيل';

  @override
  String get fewItemsExistLocally => 'بعض العناصر ما تزال موجودة محليًا.';

  @override
  String selectedItemsCount(int count) {
    return 'تم تحديد $count';
  }

  @override
  String get delete => 'حذف';

  @override
  String get info => 'معلومات';

  @override
  String get download => 'تنزيل';

  @override
  String get archive => 'أرشفة';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'السجلات';

  @override
  String get settings => 'الإعدادات';

  @override
  String get trash => 'سلة المحذوفات';

  @override
  String get storage => 'التخزين';

  @override
  String get search => 'بحث';

  @override
  String get database => 'قاعدة البيانات';

  @override
  String get addFolderTitle => 'إضافة مجلد';

  @override
  String get confirm => 'تأكيد';

  @override
  String get tapPlusToAddSyncFolder => 'اضغط + لإضافة مجلد مزامنة.';

  @override
  String get thisFolderIsEmpty => 'هذا المجلد فارغ.';

  @override
  String get fileNotFound => 'الملف غير موجود';

  @override
  String filePartsTitle(int count) {
    return 'أجزاء الملف ($count)';
  }

  @override
  String get fileDetailsTitle => 'تفاصيل الملف';

  @override
  String get encryptedBackup => 'نسخة احتياطية مشفّرة';

  @override
  String get sizeLabel => 'الحجم';

  @override
  String get providerLabel => 'المزوّد';

  @override
  String get uploadedAtLabel => 'تاريخ الرفع';

  @override
  String get statusLabel => 'الحالة';

  @override
  String get uploadedStatus => 'تم الرفع';

  @override
  String errorWithMessage(String message) {
    return 'خطأ: $message';
  }

  @override
  String get noLogsAvailable => 'لا توجد سجلات';

  @override
  String get searchLogsHint => 'ابحث في السجلات..';

  @override
  String get clearLogs => 'مسح السجلات';

  @override
  String get searchWithMinThreeCharacters => 'ابحث باستخدام 3 أحرف على الأقل';

  @override
  String get typeBelowToSearch => 'اكتب في الأسفل للبحث';

  @override
  String get noResults => 'لا توجد نتائج.';

  @override
  String get welcomeTitle => 'مرحبًا';

  @override
  String signInToContinue(String appName) {
    return 'سجّل الدخول للمتابعة إلى $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'يرجى إدخال بريدك الإلكتروني';

  @override
  String get pleaseEnterValidEmailAddress => 'يرجى إدخال بريد إلكتروني صحيح';

  @override
  String get emailAddressLabel => 'البريد الإلكتروني';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'إعادة إرسال رمز التحقق';

  @override
  String get sendOtp => 'إرسال رمز التحقق';

  @override
  String get checkYourEmail => 'تحقق من بريدك الإلكتروني';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'أرسلنا رمزًا مكوّنًا من 6 أرقام إلى\n$email';
  }

  @override
  String get pleaseEnterOtp => 'يرجى إدخال رمز التحقق';

  @override
  String get otpMustBeSixDigits => 'يجب أن يتكون رمز التحقق من 6 أرقام';

  @override
  String get enterOtpLabel => 'أدخل رمز التحقق';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'إعادة التحقق';

  @override
  String get verifyOtp => 'تحقق من الرمز';

  @override
  String get useDifferentEmail => 'استخدم بريدًا إلكترونيًا آخر';

  @override
  String get alreadySignedIn => 'تم تسجيل الدخول بالفعل';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'فشل إرسال رمز التحقق. يرجى المحاولة مرة أخرى!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'فشل التحقق من رمز التحقق. يرجى المحاولة مرة أخرى.';

  @override
  String get dbViewerTitle => 'عارض قاعدة البيانات';

  @override
  String get selectTableToViewData => 'اختر جدولًا لعرض بياناته';

  @override
  String get selectTable => 'اختر جدولًا';

  @override
  String get permissionRequiredTitle => 'إذن مطلوب';

  @override
  String get storagePermissionSettingsDescription =>
      'لإجراء نسخ احتياطي تلقائي وإدارة ملفاتك وحمايتها في الخلفية، نحتاج إلى الوصول إلى تخزين جهازك. يتم تشفير بياناتك محليًا لضمان خصوصية كاملة. يرجى السماح بالوصول للمتابعة.';

  @override
  String get openSettings => 'فتح الإعدادات';

  @override
  String get secureLocalAccessTitle => 'وصول محلي آمن';

  @override
  String get storagePermissionPageDescription =>
      'لاستعراض ملفاتك وتشفيرها والنسخ الاحتياطي لها تلقائيًا، نحتاج إلى الوصول إلى تخزين جهازك.';

  @override
  String get verifying => 'جارٍ التحقق...';

  @override
  String get grantAccess => 'منح الوصول';

  @override
  String get zeroKnowledgeEncryptedStorage => 'تخزين مشفّر دون معرفة';

  @override
  String get notificationPermissionTitle => 'وصول الإشعارات';

  @override
  String get notificationPermissionPageDescription =>
      'للحفاظ على مزامنة ملفاتك وتقديم تحديثات الحالة في الوقت الفعلي في الخلفية، نحتاج إلى إذن لإظهار الإشعارات.';

  @override
  String get notificationPermissionGrantButton => 'السماح بالإشعارات';

  @override
  String get notificationPermissionSettingsDescription =>
      'الإشعارات مطلوبة لمراقبة المزامنة في الخلفية. يرجى تفعيلها في إعدادات النظام لضمان تحديث بياناتك دائمًا.';

  @override
  String requiresAppPro(String appName) {
    return 'يتطلب $appName Pro.';
  }

  @override
  String get noStorageFound => 'لم يتم العثور على مساحة تخزين';

  @override
  String get howToConnect => 'كيفية الربط';

  @override
  String get modify => 'تعديل';

  @override
  String storageUsed(String used, String total) {
    return 'تم استخدام $used من $total';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'حتى $size مجانًا';
  }

  @override
  String get notConnected => 'غير متصل';

  @override
  String get connect => 'ربط';

  @override
  String get modifyStorageCapacityTitle => 'تعديل سعة التخزين';

  @override
  String get enterNewStorageLimitForProvider =>
      'أدخل حد التخزين الجديد لهذا المزوّد.';

  @override
  String get sizePrefix => 'الحجم: ';

  @override
  String get gbSuffix => ' جيجابايت';

  @override
  String get pleaseEnterSize => 'يرجى إدخال الحجم';

  @override
  String get enterValidNumberGreaterThanOne => 'أدخل رقمًا صحيحًا أكبر من 1';

  @override
  String get submit => 'إرسال';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'تم الاشتراك بنجاح في $appName Pro!';
  }

  @override
  String get purchaseCancelledOrFailed => 'تم إلغاء الشراء أو فشل.';

  @override
  String get purchasesRestoredSuccessfully => 'تمت استعادة المشتريات بنجاح!';

  @override
  String get noActiveSubscriptionsFound => 'لم يتم العثور على اشتراكات نشطة.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'يرجى إدارة الاشتراكات من إعدادات جهازك.';

  @override
  String get freePlanTitle => 'مجاني';

  @override
  String get freeForeverPrice => '\$0.00 / دائمًا';

  @override
  String get freeBenefitProviderStorage =>
      'استفد من التخزين المجاني لدى المزوّدين';

  @override
  String get freeBenefitSyncThreeDevices => 'مزامنة آمنة حتى 3 أجهزة';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - سنوي';
  }

  @override
  String get proBenefitModifyStorageLimit => 'تعديل حد التخزين لكل مزوّد';

  @override
  String get proBenefitSyncTenDevices => 'مزامنة حتى 10 أجهزة';

  @override
  String get restorePurchases => 'استعادة المشتريات';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* الاشتراك مرتبط بحساب البريد الإلكتروني، وليس بالجهاز';

  @override
  String get subscriptionExpiredTitle => 'انتهى الاشتراك';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'تم إيقاف مزايا $appName Pro مؤقتًا. جدّد الاشتراك أدناه لاستعادة حدود التخزين ومزامنة الأجهزة.';
  }

  @override
  String appProIsActive(String appName) {
    return 'اشتراك $appName Pro مفعل';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ تعديل حدود التخزين لكل مزوّد\n✓ مزامنة بين الأجهزة حتى 10 أجهزة';

  @override
  String get manageSubscription => 'إدارة الاشتراك';

  @override
  String get currentPlanBadge => 'الحالي';

  @override
  String get subscribeNow => 'اشترك الآن';

  @override
  String get subscribeOnMobileApp => 'اشترك من تطبيق الجوال';

  @override
  String get recover => 'استعادة';

  @override
  String get empty => 'إفراغ';

  @override
  String get noItems => 'لا توجد عناصر.';
}
