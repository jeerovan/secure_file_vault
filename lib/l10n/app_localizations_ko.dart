// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get localSessionCleanupTitle => '로컬 데이터 삭제';

  @override
  String get localSessionCleanupDescription =>
      '세션이 종료되었습니다. 다시 로그인하려면 FiFe에서 로컬 계정 데이터 삭제를 완료해야 합니다. 원본 파일은 유지됩니다. 완료하려면 다시 시도하세요.';

  @override
  String get localSessionCleanupInProgress => '이 기기에서 FiFe 데이터를 삭제하는 중…';

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
  String get appLockTitle => '앱 잠금';

  @override
  String get appLockDescription => '기기의 지문, 얼굴 또는 PIN으로 FiFe를 보호하세요.';

  @override
  String get appLockTimeout => '잠금 대기 시간';

  @override
  String get appLockTimeoutDescription =>
      'FiFe를 떠난 후 이 시간이 지나면 인증을 요청합니다. 앱을 다시 시작할 때는 항상 인증이 필요합니다.';

  @override
  String get appLockAuthenticate => 'FiFe 잠금을 해제하려면 인증하세요.';

  @override
  String get appLockChangeSettings => '앱 잠금 설정을 변경하려면 인증하세요.';

  @override
  String get appLockAuthHint => '본인 확인';

  @override
  String get appLocked => 'FiFe가 잠겨 있습니다';

  @override
  String get appLockUnlock => '잠금 해제';

  @override
  String get appLockUnavailable =>
      '기기 인증을 사용할 수 없습니다. 기기 설정에서 PIN, 암호 또는 생체 인증을 설정한 후 다시 시도하세요.';

  @override
  String get appLockAuthenticationFailed => '인증이 완료되지 않았습니다. 다시 시도하세요.';

  @override
  String get appLockStorageError =>
      '앱 잠금 설정을 읽거나 저장하지 못했습니다. 보관함을 보호하려면 다시 시도하세요.';

  @override
  String get quickSyncNotificationSettingTitle => '자동 동기화 알림';

  @override
  String get autoSyncInterval => '자동 동기화 간격';

  @override
  String get autoSyncIntervalDescription => '자동 동기화 알림이 켜져 있는 동안 자동으로 동기화합니다.';

  @override
  String syncIntervalMinutes(int minutes) {
    return '$minutes분';
  }

  @override
  String get autoSyncIntervalSaveError => '간격을 저장하지 못했습니다. 다시 시도하세요.';

  @override
  String get autoSyncIntervalApplyError =>
      '간격이 저장되었습니다. 적용하려면 자동 동기화 알림을 껐다가 다시 켜세요.';

  @override
  String get sync => '동기화';

  @override
  String get quickSyncNotificationTitle => '파일 동기화 서비스';

  @override
  String quickSyncNotificationText(int minutes) {
    return '$minutes분마다 실행';
  }

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
      '알림 패널에서 백그라운드로 파일을 빠르게 동기화하고 업로드하려면 알림 표시 권한이 필요합니다. 이 권한은 설정에서 언제든지 끌 수 있습니다.';

  @override
  String get notificationPermissionGrantButton => '알림 허용';

  @override
  String get notificationPermissionSettingsDescription =>
      '알림 패널의 빠른 동기화 기능을 사용하려면 알림이 필요합니다. 모든 데이터가 정상적으로 업로드되도록 시스템 설정에서 알림을 허용해 주세요.';

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

  @override
  String get lostRecoveryPhrase => '복구 문구를 잃어버렸어요';

  @override
  String get lostRecoveryIntro =>
      '다른 기기에 아직 로그인되어 있다면 처음부터 다시 시작하기 전에 해당 기기에서 복구 문구를 내보내세요.';

  @override
  String get lostRecoveryDeleteConsequence =>
      '현재 FiFe 보관함, 백업된 파일 및 이전 암호화 키가 영구적으로 삭제됩니다.';

  @override
  String get lostRecoveryDevicesConsequence => '기존 기기 등록이 모두 삭제됩니다.';

  @override
  String get lostRecoveryLogoutConsequence =>
      '다른 기기는 온라인 상태에서 등록 삭제를 감지하면 로그아웃하고 FiFe 로컬 데이터를 지웁니다.';

  @override
  String get lostRecoveryKeepConsequence =>
      '이메일 계정, 구독, 클라우드 저장소 연결 및 공급자 인증 정보는 유지됩니다. FiFe 외부의 개인 폴더에 있는 파일도 유지됩니다.';

  @override
  String get lostRecoveryWaitConsequence =>
      '클라우드 삭제가 확인될 때까지 새 보관함은 잠겨 있습니다. 15분 이상 걸릴 수 있습니다. FiFe를 닫고 나중에 계속할 수 있습니다.';

  @override
  String get lostRecoveryNewPhraseConsequence =>
      '이 기기에서는 로그인 상태가 유지됩니다. 삭제가 확인되면 새로운 24단어 복구 문구를 생성하고 저장하세요.';

  @override
  String get recoveryResetUnavailable => '현재 보관함을 초기화할 수 없습니다. 나중에 다시 시도해 주세요.';

  @override
  String get recoveryResetSigninRequired => '보관함을 초기화하기 전에 다시 로그인하여 세션을 확인하세요.';

  @override
  String get recoveryResetContinue => '재설정 계속하기';

  @override
  String get recoveryResetConfirmTitle => 'FiFe 보관함을 영구적으로 삭제할까요?';

  @override
  String get recoveryResetConfirmBody =>
      '이 작업은 되돌릴 수 없습니다. 기존 복구 문구는 더 이상 작동하지 않으며 모든 기기가 삭제됩니다.';

  @override
  String get recoveryResetDelete => '보관함 삭제 후 새로 시작';

  @override
  String get recoveryResetPendingTitle => '이전 보관함 삭제 중';

  @override
  String get recoveryResetPendingBody =>
      'FiFe가 클라우드 삭제를 확인하고 있습니다. 앱을 닫고 나중에 돌아올 수 있습니다.';

  @override
  String recoveryResetWaitUntil(String when) {
    return '$when 이전에는 확인이 완료될 수 없습니다.';
  }

  @override
  String get recoveryResetStorageBlocked =>
      '클라우드 삭제에 조치가 필요합니다. 연결된 저장소의 접근 및 삭제 권한을 복구한 다음 다시 시도하세요.';

  @override
  String get recoveryResetSignin => '이 재설정을 계속하려면 다시 로그인하세요.';

  @override
  String recoveryResetSigninAs(String email) {
    return '이 재설정을 계속하려면 $email 계정으로 로그인하세요.';
  }

  @override
  String get recoveryResetNeedsConfirmation =>
      '계속하려면 재설정을 확인하세요. FiFe가 이미 시작되었는지 확인합니다.';

  @override
  String get recoveryResetConfirmationWait =>
      '이전 확인이 아직 유효합니다. 만료된 후 다시 확인하고 새 확인을 시작하세요.';

  @override
  String recoveryResetConfirmationUntil(String when) {
    return '$when 이후에 다시 확인하세요.';
  }

  @override
  String get recoveryResetMissingKeys =>
      '이 기기에서 새 복구 키를 사용할 수 없습니다. 재설정을 시작한 기기에서 계속하세요. 키를 잃어버렸다면 삭제가 끝날 때까지 기다린 후 로그인하여 다시 ‘복구 문구를 잃어버렸어요’를 선택하세요.';

  @override
  String get recoveryResetDiscard => '로그인으로 돌아가기';

  @override
  String get recoveryResetDiscardBody =>
      '이 기기의 미완료 복구 설정을 지웁니다. 로그인 후 새 복구 문구를 입력하거나 보관함을 다시 재설정해야 합니다.';

  @override
  String get recoveryPhraseSaved => '새 복구 문구를 저장했습니다.';

  @override
  String get recoveryResetStarting => '재설정 시작 중…';

  @override
  String get sessionExpiredRetained =>
      '로그인 세션이 만료되었습니다. 보관함을 잠금 해제하려면 다시 로그인하세요. 로컬 데이터는 유지됩니다.';

  @override
  String get signinVerifiedContinue => '이메일이 확인되었습니다. 계속하여 로그인을 완료하세요.';

  @override
  String get noSupportedApplication => '이 파일을 볼 수 있는 지원 앱이 없습니다.';

  @override
  String get fileAccessUnavailable => '이 파일에 접근할 수 없습니다. 폴더 권한을 확인하고 다시 시도하세요.';

  @override
  String get unableToOpenFile => '이 파일을 열 수 없습니다. 다시 시도하세요.';

  @override
  String get fileNotAvailable => '이 파일은 이 기기나 완료된 백업에 없습니다.';

  @override
  String get downloadRecoveryPhrase => '복구 구문 다운로드';

  @override
  String get recoveryPhraseExportHint => '복구 구문을 보거나 복사하거나 저장하려면 인증하세요.';

  @override
  String get recoveryPhraseExportAuth => '복구 구문을 보려면 인증하세요';

  @override
  String get recoveryPhraseExportWarning =>
      '이 단어를 가진 사람은 누구나 보관함의 잠금을 해제할 수 있습니다. 사본은 FiFe 외부의 안전한 곳에 보관하세요.';

  @override
  String get recoveryPhraseUnavailable =>
      '복구 구문을 불러올 수 없습니다. 다시 시도하거나 저장한 백업 또는 로그인된 다른 기기를 사용하세요.';

  @override
  String get reconnect => '다시 연결';

  @override
  String get archiveBackup => '백업 보관';

  @override
  String get archiveFolderBackupMessage =>
      '선택한 폴더의 백업을 휴지통으로 옮기고 다운로드한 사본을 FiFe에서 삭제할까요? 원본 파일과 다른 폴더는 유지됩니다. 이 폴더 경로는 휴지통에서 복원할 때까지 동기화에서 제외됩니다.';

  @override
  String get menuBarOpen => '열기';

  @override
  String get menuBarQuit => '종료';

  @override
  String get appLockMacDescription => 'Touch ID 또는 Mac 로그인 암호로 FiFe를 보호하세요.';

  @override
  String get appLockMacUnavailable =>
      'Mac 인증을 사용할 수 없습니다. 시스템 설정에서 로그인 암호 또는 Touch ID를 설정한 후 다시 시도하세요.';
}
