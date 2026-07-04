// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'जारी रखने पर, आप हमारी $terms और $privacy से सहमत होते हैं।';
  }

  @override
  String get termsOfService => 'सेवा की शर्तें';

  @override
  String get privacyPolicy => 'गोपनीयता नीति';

  @override
  String get andLabel => ' और ';

  @override
  String get theme => 'थीम';

  @override
  String get themeTooltip => 'दिन/रात का मोड';

  @override
  String get logging => 'लॉगिंग';

  @override
  String get quickSyncNotificationSettingTitle => 'क्विक सिंक नोटिफिकेशन';

  @override
  String get quickSyncNotificationTitle => 'फ़ाइल सिंक सेवा';

  @override
  String get quickSyncNotificationText =>
      'सिंक करने के लिए नीचे दिए गए बटन पर टैप करें';

  @override
  String get quickSyncNotificationButton => 'अभी सिंक करें';

  @override
  String get quickSyncNotificationInProgress => 'प्रक्रिया जारी है...';

  @override
  String get reportIssue => 'समस्या की रिपोर्ट करें';

  @override
  String get sourceCode => 'सोर्स कोड';

  @override
  String get desktopApp => 'डेस्कटॉप ऐप';

  @override
  String get mobileApp => 'मोबाइल ऐप';

  @override
  String get leaveReview => 'अपनी राय दें';

  @override
  String get share => 'साझा करें';

  @override
  String get versionLabel => 'वर्जन: ';

  @override
  String get loading => 'लोड हो रहा है...';

  @override
  String get signOut => 'साइन आउट करें';

  @override
  String get settingsPageTitle => 'सेटिंग्स';

  @override
  String get language => 'भाषा';

  @override
  String get tapToSelect => 'चुनने के लिए टैप करें';

  @override
  String get appTagline => 'आपकी निजी फ़ाइलों की फेरी';

  @override
  String get onboardingPurposeDescription =>
      'एक ओपन-सोर्स क्लाउड स्टोरेज सेवा, जो ज़ीरो-ट्रस्ट आर्किटेक्चर पर बनी है। आपका डेटा आपके डिवाइस से बाहर जाने से पहले ही स्थानीय रूप से एन्क्रिप्ट हो जाता है।';

  @override
  String get failedToFetch => 'प्राप्त करने में विफल।';

  @override
  String get supportedStorageTitle => 'समर्थित स्टोरेज';

  @override
  String get supportedStorageDescription =>
      'अपने पसंदीदा प्रदाताओं को कनेक्ट करें। FiFe की अंतर्निहित 1 GB मुफ्त सुरक्षित स्टोरेज के साथ तुरंत शुरू करें।';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'तुरंत बैकअप शुरू करें';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'मुफ्त';

  @override
  String get providerStorageDisclaimer =>
      '* मुफ्त स्टोरेज जैसा प्रदाता की वेबसाइट पर बताया गया है। संगत प्रदाताओं के साथ जितना उपयोग करें उतना भुगतान करें।';

  @override
  String get whyUseFifeTitle => 'FiFe का उपयोग क्यों करें?';

  @override
  String get claimFreeCloudStorageTitle => 'मुफ्त क्लाउड स्टोरेज पाएं';

  @override
  String get claimFreeCloudStorageDescription =>
      'एक से अधिक क्लाउड प्रदाताओं को जोड़कर अपनी जगह अधिकतम करें। एक ही ऐप में उनकी मुफ्त स्टोरेज योजनाओं का सुरक्षित लाभ उठाएँ।';

  @override
  String get topNotchSecurityTitle => 'उच्च स्तरीय सुरक्षा';

  @override
  String get topNotchSecurityDescription =>
      'उन्नत Sodium क्रिप्टोग्राफी द्वारा संचालित। सारा एन्क्रिप्शन और डिक्रिप्शन पूरी तरह आपके डिवाइस पर स्थानीय रूप से होता है।';

  @override
  String get bringYourOwnKeyTitle => 'अपनी कुंजी स्वयं लाएँ (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'सभी क्लाउड स्टोरेज प्रदाताओं पर अपने डेटा पर पूर्ण नियंत्रण बनाए रखें। अपने खातों का उपयोग करके एन्क्रिप्टेड स्टोरेज रखें।';

  @override
  String get payAsYouGoStorageTitle =>
      'स्टोरेज के लिए जितना उपयोग करें उतना भुगतान।';

  @override
  String get payAsYouGoStorageDescription =>
      'संगत प्रदाताओं के साथ केवल उपयोग किए गए स्टोरेज के लिए भुगतान करें। कोई बिचौलिया नहीं, कोई डेटा लॉक-इन नहीं।';

  @override
  String get zeroKnowledgePrivacyTitle => 'ज़ीरो-नॉलेज गोपनीयता';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'आपका डेटा डिवाइस से बाहर जाने से पहले ही आपके डिवाइस पर सुरक्षित कर दिया जाता है। हम आपकी फ़ाइलें देख, पढ़ या स्कैन नहीं सकते।';

  @override
  String get localSelectionTitle => '1. स्थानीय चयन';

  @override
  String get localSelectionDescription =>
      'आप एक डायरेक्टरी चुनते हैं। सारी प्रक्रिया आपके स्थानीय डिवाइस पर सुरक्षित रूप से शुरू होती है।';

  @override
  String get metadataEncryptionTitle => '2. मेटाडेटा एन्क्रिप्शन';

  @override
  String get metadataEncryptionDescription =>
      'फ़ाइल की जानकारी (शीर्षक, प्रकार और आकार) सर्वर पर भेजे जाने से पहले एन्क्रिप्ट की जाती है।';

  @override
  String get contentEncryptionTitle => '3. सामग्री एन्क्रिप्शन';

  @override
  String get contentEncryptionDescription =>
      'वास्तविक फ़ाइल सामग्री को क्लाउड स्टोरेज पर अपलोड करने से पहले टुकड़ों में बाँटकर एन्क्रिप्ट किया जाता है।';

  @override
  String get blindServerTitle => '4. ब्लाइंड सर्वर';

  @override
  String get blindServerDescription =>
      'हमारे सर्वरों को कुछ भी ज्ञात नहीं होता। हमें केवल एन्क्रिप्टेड ब्लॉब्स दिखाई देते हैं, जिससे पूर्ण गोपनीयता सुनिश्चित होती है।';

  @override
  String get dontTrustVerifyTitle => 'भरोसा न करें, सत्यापित करें।';

  @override
  String get openSourceVerificationDescription =>
      '100% ओपन सोर्स। आप कोड की जाँच करके देख सकते हैं कि आपकी फ़ाइलें कैसे एन्क्रिप्ट होती हैं।';

  @override
  String get getStarted => 'शुरू करें';

  @override
  String get next => 'अगला';

  @override
  String get unauthorized => 'अनधिकृत';

  @override
  String get tryAgain => 'फिर से प्रयास करें';

  @override
  String get errorTitle => 'त्रुटि';

  @override
  String get failureTitle => 'विफलता';

  @override
  String get invalidWordList => 'अमान्य शब्द सूची';

  @override
  String get invalidAccessKey => 'अमान्य एक्सेस कुंजी';

  @override
  String get unexpectedDecryptionError =>
      'डिक्रिप्शन के दौरान एक अप्रत्याशित त्रुटि हुई।';

  @override
  String get fileMustContainExactly24Words =>
      'फ़ाइल में ठीक 24 शब्द होने चाहिए।';

  @override
  String get errorReadingFile => 'फ़ाइल पढ़ने में त्रुटि';

  @override
  String get encryptionTitle => 'एन्क्रिप्शन';

  @override
  String get accessKeyDecodeDescription =>
      'क्लाउड सिंक को सुरक्षित रूप से सक्षम करने के लिए अपना 24-शब्द रिकवरी फ़्रेज़ दर्ज करें या .txt फ़ाइल लोड करें।';

  @override
  String get recoveryPhraseLabel => 'रिकवरी फ़्रेज़';

  @override
  String get recoveryPhraseHint => 'शब्द1 शब्द2 शब्द3...';

  @override
  String get paste => 'पेस्ट करें';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 शब्द';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'कृपया अपना रिकवरी फ़्रेज़ दर्ज करें';

  @override
  String get mustContainExactly24Words => 'ठीक 24 शब्द होने चाहिए';

  @override
  String get verify => 'सत्यापित करें';

  @override
  String get orLabel => 'या';

  @override
  String get loadFromTxtFile => '.txt फ़ाइल से लोड करें';

  @override
  String get saveAccessKey => 'एक्सेस कुंजी सहेजें';

  @override
  String get fileSavedSuccessfully => 'फ़ाइल सफलतापूर्वक सहेजी गई।';

  @override
  String get accessKeyShareMessage => 'यह आपकी एक्सेस कुंजी है।';

  @override
  String get pleaseTryAgain => 'कृपया फिर से प्रयास करें।';

  @override
  String get copiedToClipboard => 'क्लिपबोर्ड में कॉपी किया गया';

  @override
  String get accessKeyTitle => 'एक्सेस कुंजी';

  @override
  String get accessKeyDescription =>
      'कृपया इस कुंजी को किसी सुरक्षित स्थान पर सहेजें। केवल यही आपको आपके एन्क्रिप्टेड डेटा तक पहुँचने देगा।';

  @override
  String get copy => 'कॉपी करें';

  @override
  String get downloadAsTextFile => 'टेक्स्ट फ़ाइल के रूप में डाउनलोड करें';

  @override
  String get continueLabel => 'जारी रखें';

  @override
  String get importantTitle => 'महत्वपूर्ण';

  @override
  String get accessKeyNoticePrimary =>
      'अगले पेज पर आपको 24 शब्दों की एक श्रृंखला दिखाई देगी। यह आपकी विशिष्ट और निजी एन्क्रिप्शन कुंजी है और लॉगआउट, डिवाइस खो जाने या खराब होने की स्थिति में आपके डेटा को पुनर्प्राप्त करने का यही एकमात्र तरीका है।';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'हम यह कुंजी संग्रहीत नहीं करते। इसे $appName ऐप के बाहर किसी सुरक्षित स्थान पर रखना आपकी जिम्मेदारी है।';
  }

  @override
  String get showKeyConfirmation => 'मैं समझता/समझती हूँ।\nमुझे कुंजी दिखाएँ।';

  @override
  String get storageAddedSuccessfully => 'स्टोरेज सफलतापूर्वक जोड़ा गया';

  @override
  String get networkErrorDuringValidation =>
      'सत्यापन के दौरान नेटवर्क त्रुटि हुई।';

  @override
  String get verifyAndConnect => 'सत्यापित करें और कनेक्ट करें';

  @override
  String get requiredField => 'आवश्यक';

  @override
  String get providerKeysVerifiedLocally =>
      'आपकी कुंजियों का सत्यापन स्थानीय रूप से किया जाता है और भेजने से पहले उन्हें एन्क्रिप्ट किया जाता है।';

  @override
  String get enterYourCredentials => 'अपने क्रेडेंशियल दर्ज करें';

  @override
  String connectProvider(String provider) {
    return '$provider कनेक्ट करें';
  }

  @override
  String get deviceLimitReached => 'डिवाइस सीमा पूरी हो गई';

  @override
  String get pleaseTryAgainWithExclamation => 'कृपया फिर से प्रयास करें!';

  @override
  String get notThisDevice => 'यह डिवाइस नहीं!';

  @override
  String get confirmSignoutDeviceTitle => 'डिवाइस साइनआउट की पुष्टि करें';

  @override
  String get areYouSure => 'क्या आप सुनिश्चित हैं?';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get ok => 'ठीक है';

  @override
  String get noDeviceFound => 'कोई डिवाइस नहीं मिला';

  @override
  String get backTooltip => 'वापस';

  @override
  String get devicesTitle => 'डिवाइस';

  @override
  String get longPressToDownload => 'डाउनलोड करने के लिए लंबा दबाएँ';

  @override
  String get fewItemsExistLocally => 'कुछ आइटम स्थानीय रूप से मौजूद हैं।';

  @override
  String selectedItemsCount(int count) {
    return '$count चयनित';
  }

  @override
  String get delete => 'हटाएँ';

  @override
  String get info => 'जानकारी';

  @override
  String get download => 'डाउनलोड';

  @override
  String get archive => 'संग्रहित करें';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'लॉग्स';

  @override
  String get settings => 'सेटिंग्स';

  @override
  String get trash => 'ट्रैश';

  @override
  String get storage => 'स्टोरेज';

  @override
  String get search => 'खोजें';

  @override
  String get database => 'डेटाबेस';

  @override
  String get addFolderTitle => 'फ़ोल्डर जोड़ें';

  @override
  String get confirm => 'पुष्टि करें';

  @override
  String get tapPlusToAddSyncFolder =>
      'सिंक फ़ोल्डर जोड़ने के लिए + पर टैप करें।';

  @override
  String get thisFolderIsEmpty => 'यह फ़ोल्डर खाली है।';

  @override
  String get fileNotFound => 'फ़ाइल नहीं मिली';

  @override
  String filePartsTitle(int count) {
    return 'फ़ाइल भाग ($count)';
  }

  @override
  String get fileDetailsTitle => 'फ़ाइल विवरण';

  @override
  String get encryptedBackup => 'एन्क्रिप्टेड बैकअप';

  @override
  String get sizeLabel => 'आकार';

  @override
  String get providerLabel => 'प्रदाता';

  @override
  String get uploadedAtLabel => 'अपलोड किया गया';

  @override
  String get statusLabel => 'स्थिति';

  @override
  String get uploadedStatus => 'अपलोड किया गया';

  @override
  String errorWithMessage(String message) {
    return 'त्रुटि: $message';
  }

  @override
  String get noLogsAvailable => 'कोई लॉग उपलब्ध नहीं है';

  @override
  String get searchLogsHint => 'लॉग खोजें..';

  @override
  String get clearLogs => 'लॉग साफ़ करें';

  @override
  String get searchWithMinThreeCharacters => 'कम से कम 3 अक्षरों से खोजें';

  @override
  String get typeBelowToSearch => 'खोजने के लिए नीचे टाइप करें';

  @override
  String get noResults => 'कोई परिणाम नहीं।';

  @override
  String get welcomeTitle => 'स्वागत है';

  @override
  String signInToContinue(String appName) {
    return '$appName में जारी रखने के लिए साइन इन करें';
  }

  @override
  String get pleaseEnterYourEmail => 'कृपया अपना ईमेल दर्ज करें';

  @override
  String get pleaseEnterValidEmailAddress =>
      'कृपया एक मान्य ईमेल पता दर्ज करें';

  @override
  String get emailAddressLabel => 'ईमेल पता';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'OTP फिर से भेजें';

  @override
  String get sendOtp => 'OTP भेजें';

  @override
  String get checkYourEmail => 'अपना ईमेल जाँचें';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'हमने 6-अंकों का कोड इस पते पर भेजा है\n$email';
  }

  @override
  String get pleaseEnterOtp => 'कृपया OTP दर्ज करें';

  @override
  String get otpMustBeSixDigits => 'OTP 6 अंकों का होना चाहिए';

  @override
  String get enterOtpLabel => 'OTP दर्ज करें';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'सत्यापन फिर से करें';

  @override
  String get verifyOtp => 'OTP सत्यापित करें';

  @override
  String get useDifferentEmail => 'अलग ईमेल का उपयोग करें';

  @override
  String get alreadySignedIn => 'पहले से साइन इन है';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'OTP भेजना विफल रहा। कृपया फिर से प्रयास करें!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'OTP सत्यापन विफल रहा। कृपया फिर से प्रयास करें।';

  @override
  String get dbViewerTitle => 'DB व्यूअर';

  @override
  String get selectTableToViewData => 'उसका डेटा देखने के लिए एक तालिका चुनें';

  @override
  String get selectTable => 'एक तालिका चुनें';

  @override
  String get permissionRequiredTitle => 'अनुमति आवश्यक है';

  @override
  String get storagePermissionSettingsDescription =>
      'पृष्ठभूमि में आपकी फ़ाइलों का स्वचालित बैकअप, प्रबंधन और सुरक्षा करने के लिए हमें आपके डिवाइस स्टोरेज तक पहुँच चाहिए। आपका डेटा स्थानीय रूप से एन्क्रिप्ट होता है, जिससे पूर्ण गोपनीयता सुनिश्चित होती है। जारी रखने के लिए कृपया पहुँच प्रदान करें।';

  @override
  String get openSettings => 'सेटिंग्स खोलें';

  @override
  String get secureLocalAccessTitle => 'सुरक्षित स्थानीय पहुँच';

  @override
  String get storagePermissionPageDescription =>
      'आपकी फ़ाइलों को एक्सप्लोर, एन्क्रिप्ट और स्वचालित रूप से बैकअप करने के लिए हमें आपके डिवाइस स्टोरेज तक पहुँच चाहिए।';

  @override
  String get verifying => 'सत्यापित किया जा रहा है...';

  @override
  String get grantAccess => 'पहुँच दें';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'ज़ीरो-नॉलेज एन्क्रिप्टेड स्टोरेज';

  @override
  String get notificationPermissionTitle => 'नोटिफिकेशन एक्सेस';

  @override
  String get notificationPermissionPageDescription =>
      'आपकी फ़ाइलों को सिंक रखने और बैकग्राउंड में रीयल-टाइम स्टेटस अपडेट देने के लिए, हमें नोटिफिकेशन दिखाने की अनुमति चाहिए।';

  @override
  String get notificationPermissionGrantButton => 'नोटिफिकेशन की अनुमति दें';

  @override
  String get notificationPermissionSettingsDescription =>
      'बैकग्राउंड सिंक्रोनाइज़ेशन की निगरानी के लिए नोटिफिकेशन आवश्यक हैं। कृपया सिस्टम सेटिंग्स में इन्हें सक्षम करें ताकि आपका डेटा हमेशा अपडेट रहे।';

  @override
  String requiresAppPro(String appName) {
    return '$appName Pro आवश्यक है।';
  }

  @override
  String get noStorageFound => 'कोई स्टोरेज नहीं मिला';

  @override
  String get howToConnect => 'कनेक्ट कैसे करें';

  @override
  String get modify => 'संशोधित करें';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total उपयोग किया गया';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return '$size तक मुफ्त';
  }

  @override
  String get notConnected => 'कनेक्ट नहीं है';

  @override
  String get connect => 'कनेक्ट करें';

  @override
  String get modifyStorageCapacityTitle => 'स्टोरेज क्षमता संशोधित करें';

  @override
  String get enterNewStorageLimitForProvider =>
      'इस प्रदाता के लिए नई स्टोरेज सीमा दर्ज करें।';

  @override
  String get sizePrefix => 'आकार: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'कृपया एक आकार दर्ज करें';

  @override
  String get enterValidNumberGreaterThanOne =>
      '1 से बड़ा एक मान्य संख्या दर्ज करें';

  @override
  String get submit => 'सबमिट करें';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return '$appName Pro की सदस्यता सफलतापूर्वक ली गई!';
  }

  @override
  String get purchaseCancelledOrFailed => 'खरीद रद्द हो गई या विफल रही।';

  @override
  String get purchasesRestoredSuccessfully => 'खरीदारी सफलतापूर्वक बहाल की गई!';

  @override
  String get noActiveSubscriptionsFound => 'कोई सक्रिय सदस्यता नहीं मिली।';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'कृपया अपनी सदस्यताओं का प्रबंधन डिवाइस सेटिंग्स में करें।';

  @override
  String get freePlanTitle => 'मुफ्त';

  @override
  String get freeForeverPrice => '\$0.00 / हमेशा के लिए';

  @override
  String get freeBenefitProviderStorage =>
      'प्रदाताओं से मुफ्त स्टोरेज का आनंद लें';

  @override
  String get freeBenefitSyncThreeDevices =>
      '3 डिवाइस तक सुरक्षित रूप से सिंक करें';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - वार्षिक';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'हर प्रदाता के लिए स्टोरेज सीमा संशोधित करें';

  @override
  String get proBenefitSyncTenDevices => '10 डिवाइस तक सिंक करें';

  @override
  String get restorePurchases => 'खरीदारी बहाल करें';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* सदस्यता डिवाइस से नहीं, ईमेल खाते से जुड़ी है';

  @override
  String get subscriptionExpiredTitle => 'सदस्यता समाप्त हो गई';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'आपके $appName Pro लाभ रोक दिए गए हैं। अपनी स्टोरेज सीमाएँ और डिवाइस सिंक बहाल करने के लिए नीचे नवीनीकरण करें।';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro सक्रिय है';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ हर प्रदाता के लिए स्टोरेज सीमाएँ संशोधित करें\n✓ 10 डिवाइस तक क्रॉस-सिंक करें';

  @override
  String get manageSubscription => 'सदस्यता प्रबंधित करें';

  @override
  String get currentPlanBadge => 'वर्तमान';

  @override
  String get subscribeNow => 'अभी सदस्यता लें';

  @override
  String get subscribeOnMobileApp => 'मोबाइल ऐप पर सदस्यता लें';

  @override
  String get recover => 'पुनर्प्राप्त करें';

  @override
  String get empty => 'खाली करें';

  @override
  String get noItems => 'कोई आइटम नहीं।';
}
