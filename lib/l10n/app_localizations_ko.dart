// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return '계속하면 $terms 및 $privacy에 동의하는 것으로 간주됩니다.';
  }

  @override
  String get termsOfService => '서비스 이용약관';

  @override
  String get privacyPolicy => '개인정보 처리방침';

  @override
  String get andLabel => ' 및 ';

  @override
  String get theme => '테마';

  @override
  String get themeTooltip => '라이트/다크 테마';

  @override
  String get logging => '로그';

  @override
  String get quickSyncNotificationSettingTitle => '빠른 동기화 알림';

  @override
  String get quickSyncNotificationTitle => '파일 동기화 서비스';

  @override
  String get quickSyncNotificationText => '아래 버튼을 탭하여 동기화하세요';

  @override
  String get quickSyncNotificationButton => '지금 동기화';

  @override
  String get quickSyncNotificationInProgress => '진행 중...';

  @override
  String get reportIssue => '문제 신고';

  @override
  String get sourceCode => '소스 코드';

  @override
  String get desktopApp => '데스크톱 앱';

  @override
  String get mobileApp => '모바일 앱';

  @override
  String get leaveReview => '리뷰 남기기';

  @override
  String get share => '공유';

  @override
  String get versionLabel => '버전: ';

  @override
  String get loading => '불러오는 중...';

  @override
  String get signOut => '로그아웃';

  @override
  String get settingsPageTitle => '설정';

  @override
  String get language => '언어';

  @override
  String get tapToSelect => '탭하여 선택';

  @override
  String get appTagline => '당신만의 프라이빗 파일 페리';

  @override
  String get onboardingPurposeDescription =>
      '제로 트러스트 아키텍처로 구축된 오픈소스 클라우드 스토리지 서비스입니다. 데이터는 기기를 떠나기 전에 로컬에서 암호화됩니다.';

  @override
  String get failedToFetch => '불러오지 못했습니다.';

  @override
  String get supportedStorageTitle => '지원 스토리지';

  @override
  String get supportedStorageDescription =>
      '자주 쓰는 스토리지 제공업체를 연결하세요. FiFe에 기본 제공되는 안전한 무료 저장공간 1 GB로 바로 시작할 수 있습니다.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => '즉시 백업 시작';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => '무료';

  @override
  String get providerStorageDisclaimer =>
      '* 무료 저장공간은 각 제공업체 웹사이트 기준입니다. 호환되는 제공업체에서는 사용한 만큼만 결제할 수 있습니다.';

  @override
  String get whyUseFifeTitle => '왜 FiFe를 써야 할까요?';

  @override
  String get claimFreeCloudStorageTitle => '무료 클라우드 저장공간 활용';

  @override
  String get claimFreeCloudStorageDescription =>
      '여러 클라우드 제공업체를 연결해 저장공간을 더 넉넉하게 활용하세요. 각 업체의 무료 요금제를 하나의 앱에서 안전하게 이용할 수 있습니다.';

  @override
  String get topNotchSecurityTitle => '강력한 보안';

  @override
  String get topNotchSecurityDescription =>
      '고급 Sodium 암호 기술을 기반으로 합니다. 모든 암호화와 복호화는 전부 기기 내 로컬에서 이루어집니다.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      '모든 클라우드 스토리지 제공업체에서 내 데이터의 주도권을 직접 유지하세요. 내 계정으로 암호화된 저장공간을 사용할 수 있습니다.';

  @override
  String get payAsYouGoStorageTitle => '스토리지는 사용한 만큼만 결제.';

  @override
  String get payAsYouGoStorageDescription =>
      '호환되는 제공업체에서는 실제 사용한 저장공간에 대해서만 비용을 지불합니다. 중간 수수료도, 데이터 종속도 없습니다.';

  @override
  String get zeroKnowledgePrivacyTitle => '제로 지식 프라이버시';

  @override
  String get zeroKnowledgePrivacyDescription =>
      '데이터는 전송되기 전에 기기에서 먼저 잠깁니다. 우리는 파일을 보거나 읽거나 검사할 수 없습니다.';

  @override
  String get localSelectionTitle => '1. 로컬에서 선택';

  @override
  String get localSelectionDescription =>
      '폴더를 선택하면 모든 처리가 사용자의 기기에서 안전하게 시작됩니다.';

  @override
  String get metadataEncryptionTitle => '2. 메타데이터 암호화';

  @override
  String get metadataEncryptionDescription =>
      '파일 이름, 형식, 크기 같은 정보는 서버로 전송되기 전에 먼저 암호화됩니다.';

  @override
  String get contentEncryptionTitle => '3. 콘텐츠 암호화';

  @override
  String get contentEncryptionDescription =>
      '실제 파일 내용은 분할되고 암호화된 뒤 클라우드 스토리지로 업로드됩니다.';

  @override
  String get blindServerTitle => '4. 내용을 모르는 서버';

  @override
  String get blindServerDescription =>
      '우리 서버는 데이터 내용을 알지 못합니다. 보이는 것은 암호화된 데이터 조각뿐이므로 프라이버시가 철저히 보호됩니다.';

  @override
  String get dontTrustVerifyTitle => '믿기만 하지 말고, 직접 확인하세요.';

  @override
  String get openSourceVerificationDescription =>
      '100% 오픈소스입니다. 파일이 어떤 방식으로 암호화되는지 코드를 직접 확인할 수 있습니다.';

  @override
  String get getStarted => '시작하기';

  @override
  String get next => '다음';

  @override
  String get unauthorized => '권한이 없습니다';

  @override
  String get tryAgain => '다시 시도';

  @override
  String get errorTitle => '오류';

  @override
  String get failureTitle => '실패';

  @override
  String get invalidWordList => '유효하지 않은 단어 목록입니다';

  @override
  String get invalidAccessKey => '유효하지 않은 접근 키입니다';

  @override
  String get unexpectedDecryptionError => '복호화 중 예상치 못한 오류가 발생했습니다.';

  @override
  String get fileMustContainExactly24Words => '파일에는 정확히 24개의 단어가 있어야 합니다.';

  @override
  String get errorReadingFile => '파일을 읽는 중 오류가 발생했습니다';

  @override
  String get encryptionTitle => '암호화';

  @override
  String get accessKeyDecodeDescription =>
      '24단어 복구 문구를 입력하거나 .txt 파일을 불러와 안전하게 클라우드 동기화를 활성화하세요.';

  @override
  String get recoveryPhraseLabel => '복구 문구';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => '붙여넣기';

  @override
  String wordCountLabel(int count) {
    return '$count / 24단어';
  }

  @override
  String get pleaseEnterRecoveryPhrase => '복구 문구를 입력해 주세요';

  @override
  String get mustContainExactly24Words => '정확히 24개의 단어가 포함되어야 합니다';

  @override
  String get verify => '확인';

  @override
  String get orLabel => '또는';

  @override
  String get loadFromTxtFile => '.txt 파일에서 불러오기';

  @override
  String get saveAccessKey => '접근 키 저장';

  @override
  String get fileSavedSuccessfully => '파일이 저장되었습니다.';

  @override
  String get accessKeyShareMessage => '접근 키를 보냅니다.';

  @override
  String get pleaseTryAgain => '다시 시도해 주세요.';

  @override
  String get copiedToClipboard => '클립보드에 복사되었습니다';

  @override
  String get accessKeyTitle => '접근 키';

  @override
  String get accessKeyDescription =>
      '이 키는 안전한 곳에 보관해 주세요. 암호화된 데이터에 접근할 수 있는 유일한 수단입니다.';

  @override
  String get copy => '복사';

  @override
  String get downloadAsTextFile => '텍스트 파일로 저장';

  @override
  String get continueLabel => '계속';

  @override
  String get importantTitle => '중요';

  @override
  String get accessKeyNoticePrimary =>
      '다음 페이지에는 24개의 단어가 표시됩니다. 이것은 사용자의 고유한 개인 암호화 키이며, 로그아웃하거나 기기를 분실하거나 기기에 문제가 생겼을 때 데이터를 복구할 수 있는 유일한 방법입니다.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return '이 키는 저희가 보관하지 않습니다. $appName 앱 외부의 안전한 장소에 보관하는 책임은 전적으로 사용자에게 있습니다.';
  }

  @override
  String get showKeyConfirmation => '이해했습니다.\n키를 보여주세요.';

  @override
  String get storageAddedSuccessfully => '스토리지가 추가되었습니다';

  @override
  String get networkErrorDuringValidation => '검증 중 네트워크 오류가 발생했습니다.';

  @override
  String get verifyAndConnect => '확인 후 연결';

  @override
  String get requiredField => '필수 입력';

  @override
  String get providerKeysVerifiedLocally => '키는 로컬에서 검증되며 전송 전에 암호화됩니다.';

  @override
  String get enterYourCredentials => '인증 정보를 입력하세요';

  @override
  String connectProvider(String provider) {
    return '$provider 연결';
  }

  @override
  String get deviceLimitReached => '기기 한도에 도달했습니다';

  @override
  String get pleaseTryAgainWithExclamation => '다시 시도해 주세요!';

  @override
  String get notThisDevice => '이 기기는 제외됩니다!';

  @override
  String get confirmSignoutDeviceTitle => '기기 로그아웃 확인';

  @override
  String get areYouSure => '계속하시겠습니까?';

  @override
  String get cancel => '취소';

  @override
  String get ok => '확인';

  @override
  String get noDeviceFound => '기기를 찾을 수 없습니다';

  @override
  String get backTooltip => '뒤로';

  @override
  String get devicesTitle => '기기';

  @override
  String get longPressToDownload => '길게 눌러 다운로드';

  @override
  String get fewItemsExistLocally => '일부 항목이 로컬에 남아 있습니다.';

  @override
  String selectedItemsCount(int count) {
    return '$count개 선택됨';
  }

  @override
  String get delete => '삭제';

  @override
  String get info => '정보';

  @override
  String get download => '다운로드';

  @override
  String get archive => '보관';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => '로그';

  @override
  String get settings => '설정';

  @override
  String get trash => '휴지통';

  @override
  String get storage => '스토리지';

  @override
  String get search => '검색';

  @override
  String get database => '데이터베이스';

  @override
  String get addFolderTitle => '폴더 추가';

  @override
  String get confirm => '확인';

  @override
  String get tapPlusToAddSyncFolder => '+ 버튼을 눌러 동기화 폴더를 추가하세요.';

  @override
  String get thisFolderIsEmpty => '이 폴더는 비어 있습니다.';

  @override
  String get fileNotFound => '파일을 찾을 수 없습니다';

  @override
  String filePartsTitle(int count) {
    return '파일 조각 ($count)';
  }

  @override
  String get fileDetailsTitle => '파일 세부정보';

  @override
  String get encryptedBackup => '암호화된 백업';

  @override
  String get sizeLabel => '크기';

  @override
  String get providerLabel => '제공업체';

  @override
  String get uploadedAtLabel => '업로드 시각';

  @override
  String get statusLabel => '상태';

  @override
  String get uploadedStatus => '업로드 완료';

  @override
  String errorWithMessage(String message) {
    return '오류: $message';
  }

  @override
  String get noLogsAvailable => '표시할 로그가 없습니다';

  @override
  String get searchLogsHint => '로그 검색...';

  @override
  String get clearLogs => '로그 지우기';

  @override
  String get searchWithMinThreeCharacters => '3자 이상 입력해 검색하세요';

  @override
  String get typeBelowToSearch => '아래에 입력해 검색하세요';

  @override
  String get noResults => '검색 결과가 없습니다.';

  @override
  String get welcomeTitle => '환영합니다';

  @override
  String signInToContinue(String appName) {
    return '$appName을(를) 계속 사용하려면 로그인하세요';
  }

  @override
  String get pleaseEnterYourEmail => '이메일을 입력해 주세요';

  @override
  String get pleaseEnterValidEmailAddress => '유효한 이메일 주소를 입력해 주세요';

  @override
  String get emailAddressLabel => '이메일 주소';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'OTP 다시 보내기';

  @override
  String get sendOtp => 'OTP 보내기';

  @override
  String get checkYourEmail => '이메일을 확인하세요';

  @override
  String sentSixDigitCodeTo(String email) {
    return '6자리 코드를 다음 주소로 보냈습니다\n$email';
  }

  @override
  String get pleaseEnterOtp => 'OTP를 입력해 주세요';

  @override
  String get otpMustBeSixDigits => 'OTP는 6자리여야 합니다';

  @override
  String get enterOtpLabel => 'OTP 입력';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => '인증 다시 시도';

  @override
  String get verifyOtp => 'OTP 확인';

  @override
  String get useDifferentEmail => '다른 이메일 사용';

  @override
  String get alreadySignedIn => '이미 로그인되어 있습니다';

  @override
  String get sendingOtpFailedPleaseTryAgain => 'OTP 전송에 실패했습니다. 다시 시도해 주세요!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'OTP 확인에 실패했습니다. 다시 시도해 주세요.';

  @override
  String get dbViewerTitle => 'DB 뷰어';

  @override
  String get selectTableToViewData => '데이터를 볼 테이블을 선택하세요';

  @override
  String get selectTable => '테이블 선택';

  @override
  String get permissionRequiredTitle => '권한이 필요합니다';

  @override
  String get storagePermissionSettingsDescription =>
      '파일을 자동으로 백업하고 관리하며 안전하게 보호하려면 기기 저장공간 접근 권한이 필요합니다. 데이터는 로컬에서 암호화되므로 프라이버시는 안전하게 보호됩니다. 계속하려면 접근을 허용해 주세요.';

  @override
  String get openSettings => '설정 열기';

  @override
  String get secureLocalAccessTitle => '안전한 로컬 접근';

  @override
  String get storagePermissionPageDescription =>
      '파일을 탐색하고 암호화하며 자동으로 백업하려면 기기 저장공간 접근 권한이 필요합니다.';

  @override
  String get verifying => '확인 중...';

  @override
  String get grantAccess => '접근 허용';

  @override
  String get zeroKnowledgeEncryptedStorage => '제로 지식 암호화 스토리지';

  @override
  String get notificationPermissionTitle => '알림 권한';

  @override
  String get notificationPermissionPageDescription =>
      '파일을 계속 동기화하고 백그라운드에서 실시간 상태 업데이트를 제공하려면 알림 권한이 필요합니다.';

  @override
  String get notificationPermissionGrantButton => '알림 허용';

  @override
  String get notificationPermissionSettingsDescription =>
      '백그라운드 동기화를 모니터링하려면 알림이 필요합니다. 데이터가 항상 최신 상태로 유지되도록 시스템 설정에서 알림을 활성화해 주세요.';

  @override
  String requiresAppPro(String appName) {
    return '$appName Pro가 필요합니다.';
  }

  @override
  String get noStorageFound => '스토리지를 찾을 수 없습니다';

  @override
  String get howToConnect => '연결 방법';

  @override
  String get modify => '수정';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total 사용 중';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return '최대 $size 무료';
  }

  @override
  String get notConnected => '연결되지 않음';

  @override
  String get connect => '연결';

  @override
  String get modifyStorageCapacityTitle => '스토리지 용량 수정';

  @override
  String get enterNewStorageLimitForProvider => '이 제공업체의 새 저장공간 한도를 입력하세요.';

  @override
  String get sizePrefix => '크기: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => '크기를 입력해 주세요';

  @override
  String get enterValidNumberGreaterThanOne => '1보다 큰 올바른 숫자를 입력해 주세요';

  @override
  String get submit => '제출';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return '$appName Pro 구독이 완료되었습니다!';
  }

  @override
  String get purchaseCancelledOrFailed => '구매가 취소되었거나 실패했습니다.';

  @override
  String get purchasesRestoredSuccessfully => '구매 내역이 복원되었습니다!';

  @override
  String get noActiveSubscriptionsFound => '활성 구독을 찾을 수 없습니다.';

  @override
  String get manageSubscriptionsInDeviceSettings => '구독은 기기 설정에서 관리해 주세요.';

  @override
  String get freePlanTitle => '무료';

  @override
  String get freeForeverPrice => '\$0.00 / 평생 무료';

  @override
  String get freeBenefitProviderStorage => '제공업체의 무료 저장공간 사용';

  @override
  String get freeBenefitSyncThreeDevices => '최대 3대의 기기를 안전하게 동기화';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - 연간';
  }

  @override
  String get proBenefitModifyStorageLimit => '각 제공업체별 저장공간 한도 변경';

  @override
  String get proBenefitSyncTenDevices => '최대 10대 기기 동기화';

  @override
  String get restorePurchases => '구매 복원';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* 구독은 기기가 아니라 이메일 계정에 연결됩니다';

  @override
  String get subscriptionExpiredTitle => '구독이 만료됨';

  @override
  String subscriptionExpiredDescription(String appName) {
    return '$appName Pro 혜택이 일시 중지되었습니다. 아래에서 갱신하면 저장공간 한도와 기기 동기화를 다시 사용할 수 있습니다.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro 사용 중';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ 각 제공업체별 저장공간 한도 변경\n✓ 최대 10대 기기 간 교차 동기화';

  @override
  String get manageSubscription => '구독 관리';

  @override
  String get currentPlanBadge => '현재 플랜';

  @override
  String get subscribeNow => '지금 구독';

  @override
  String get subscribeOnMobileApp => '모바일 앱에서 구독';

  @override
  String get recover => '복구';

  @override
  String get empty => '비우기';

  @override
  String get noItems => '항목이 없습니다.';
}
