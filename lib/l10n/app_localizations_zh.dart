// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return '继续即表示您同意我们的$terms和$privacy。';
  }

  @override
  String get termsOfService => '服务条款';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get andLabel => '和';

  @override
  String get theme => '主题';

  @override
  String get themeTooltip => '日间/夜间主题';

  @override
  String get logging => '日志';

  @override
  String get quickSyncNotificationSettingTitle => 'Quick sync notification';

  @override
  String get quickSyncNotificationTitle => 'File sync service';

  @override
  String get quickSyncNotificationText => 'Tap the button below to sync';

  @override
  String get quickSyncNotificationButton => 'Sync now';

  @override
  String get quickSyncNotificationInProgress => 'In progress...';

  @override
  String get reportIssue => '报告问题';

  @override
  String get sourceCode => '源代码';

  @override
  String get desktopApp => '桌面应用';

  @override
  String get mobileApp => '移动应用';

  @override
  String get leaveReview => '留下评价';

  @override
  String get share => '分享';

  @override
  String get versionLabel => '版本：';

  @override
  String get loading => '加载中...';

  @override
  String get signOut => '退出登录';

  @override
  String get settingsPageTitle => '设置';

  @override
  String get language => '语言';

  @override
  String get tapToSelect => '点击选择';

  @override
  String get appTagline => '您的私人文件摆渡服务';

  @override
  String get onboardingPurposeDescription =>
      '一款基于零信任架构构建的开源云存储服务。您的数据会在离开设备之前先在本地完成加密。';

  @override
  String get failedToFetch => '获取失败。';

  @override
  String get supportedStorageTitle => '支持的存储';

  @override
  String get supportedStorageDescription =>
      '连接您常用的存储服务。立即使用 FiFe 内置的 1 GB 免费安全存储开始体验。';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => '立即开始备份';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => '免费';

  @override
  String get providerStorageDisclaimer => '* 免费存储额度以服务商官网说明为准。兼容的服务商支持按量付费。';

  @override
  String get whyUseFifeTitle => '为什么选择 FiFe？';

  @override
  String get claimFreeCloudStorageTitle => '领取更多免费云存储';

  @override
  String get claimFreeCloudStorageDescription =>
      '连接多个云服务提供商，充分利用可用空间。在一个统一应用中安全使用各家的免费存储额度。';

  @override
  String get topNotchSecurityTitle => '顶级安全性';

  @override
  String get topNotchSecurityDescription =>
      '由先进的 Sodium 密码学提供支持。所有加密和解密都完全在您的设备本地完成。';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      '在所有云存储服务商之间始终掌握对数据的完全控制权。使用您自己的账户保存加密数据。';

  @override
  String get payAsYouGoStorageTitle => '按实际使用量付费。';

  @override
  String get payAsYouGoStorageDescription => '在兼容的服务商中只为实际使用的存储付费。无中间商，无数据锁定。';

  @override
  String get zeroKnowledgePrivacyTitle => '零知识隐私';

  @override
  String get zeroKnowledgePrivacyDescription =>
      '您的数据会在离开设备前先被锁定加密。我们无法查看、读取或扫描您的文件。';

  @override
  String get localSelectionTitle => '1. 本地选择';

  @override
  String get localSelectionDescription => '由您选择文件夹，所有处理都会安全地从您的本地设备开始。';

  @override
  String get metadataEncryptionTitle => '2. 元数据加密';

  @override
  String get metadataEncryptionDescription => '文件信息（名称、类型和大小）会在发送到服务器前完成加密。';

  @override
  String get contentEncryptionTitle => '3. 内容加密';

  @override
  String get contentEncryptionDescription => '实际文件内容会先被分片并加密，然后再上传到云存储。';

  @override
  String get blindServerTitle => '4. 盲服务器';

  @override
  String get blindServerDescription =>
      '我们的服务器对您的数据一无所知。我们只能看到加密后的数据块，从而确保绝对隐私。';

  @override
  String get dontTrustVerifyTitle => '不要盲目信任，请亲自验证。';

  @override
  String get openSourceVerificationDescription =>
      '100% 开源。您可以查看代码，亲自确认文件是如何被加密的。';

  @override
  String get getStarted => '开始使用';

  @override
  String get next => '下一步';

  @override
  String get unauthorized => '未授权';

  @override
  String get tryAgain => '重试';

  @override
  String get errorTitle => '错误';

  @override
  String get failureTitle => '失败';

  @override
  String get invalidWordList => '无效的单词列表';

  @override
  String get invalidAccessKey => '无效的访问密钥';

  @override
  String get unexpectedDecryptionError => '解密过程中发生未知错误。';

  @override
  String get fileMustContainExactly24Words => '文件必须且只能包含 24 个单词。';

  @override
  String get errorReadingFile => '读取文件时出错';

  @override
  String get encryptionTitle => '加密';

  @override
  String get accessKeyDecodeDescription =>
      '请输入您的 24 个单词恢复短语，或加载 .txt 文件，以安全启用云同步。';

  @override
  String get recoveryPhraseLabel => '恢复短语';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => '粘贴';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 个单词';
  }

  @override
  String get pleaseEnterRecoveryPhrase => '请输入恢复短语';

  @override
  String get mustContainExactly24Words => '必须包含且只能包含 24 个单词';

  @override
  String get verify => '验证';

  @override
  String get orLabel => '或';

  @override
  String get loadFromTxtFile => '从 .txt 文件加载';

  @override
  String get saveAccessKey => '保存访问密钥';

  @override
  String get fileSavedSuccessfully => '文件保存成功。';

  @override
  String get accessKeyShareMessage => '这是您的访问密钥。';

  @override
  String get pleaseTryAgain => '请重试。';

  @override
  String get copiedToClipboard => '已复制到剪贴板';

  @override
  String get accessKeyTitle => '访问密钥';

  @override
  String get accessKeyDescription => '请将此密钥保存在安全的地方。只有它才能让您访问已加密的数据。';

  @override
  String get copy => '复制';

  @override
  String get downloadAsTextFile => '下载为文本文件';

  @override
  String get continueLabel => '继续';

  @override
  String get importantTitle => '重要提示';

  @override
  String get accessKeyNoticePrimary =>
      '在下一页，您将看到一组由 24 个单词组成的短语。这是您唯一且私密的加密密钥，也是您在退出登录、设备丢失或设备故障时恢复数据的唯一方式。';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return '我们不会保存此密钥。您必须自行将它保存在 $appName 应用之外的安全位置。';
  }

  @override
  String get showKeyConfirmation => '我已了解。\n显示密钥。';

  @override
  String get storageAddedSuccessfully => '存储添加成功';

  @override
  String get networkErrorDuringValidation => '验证过程中发生网络错误。';

  @override
  String get verifyAndConnect => '验证并连接';

  @override
  String get requiredField => '必填';

  @override
  String get providerKeysVerifiedLocally => '您的密钥会在本地完成验证，并在传输前加密。';

  @override
  String get enterYourCredentials => '请输入您的凭据';

  @override
  String connectProvider(String provider) {
    return '连接 $provider';
  }

  @override
  String get deviceLimitReached => '已达到设备数量上限';

  @override
  String get pleaseTryAgainWithExclamation => '请再试一次！';

  @override
  String get notThisDevice => '不能是当前设备！';

  @override
  String get confirmSignoutDeviceTitle => '确认注销设备';

  @override
  String get areYouSure => '确定要继续吗？';

  @override
  String get cancel => '取消';

  @override
  String get ok => '确定';

  @override
  String get noDeviceFound => '未找到设备';

  @override
  String get backTooltip => '返回';

  @override
  String get devicesTitle => '设备';

  @override
  String get longPressToDownload => '长按即可下载';

  @override
  String get fewItemsExistLocally => '部分项目仍保留在本地。';

  @override
  String selectedItemsCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get delete => '删除';

  @override
  String get info => '信息';

  @override
  String get download => '下载';

  @override
  String get archive => '归档';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => '日志';

  @override
  String get settings => '设置';

  @override
  String get trash => '回收站';

  @override
  String get storage => '存储';

  @override
  String get search => '搜索';

  @override
  String get database => '数据库';

  @override
  String get addFolderTitle => '添加文件夹';

  @override
  String get confirm => '确认';

  @override
  String get tapPlusToAddSyncFolder => '点击 + 添加同步文件夹。';

  @override
  String get thisFolderIsEmpty => '此文件夹为空。';

  @override
  String get fileNotFound => '未找到文件';

  @override
  String filePartsTitle(int count) {
    return '文件分片（$count）';
  }

  @override
  String get fileDetailsTitle => '文件详情';

  @override
  String get encryptedBackup => '加密备份';

  @override
  String get sizeLabel => '大小';

  @override
  String get providerLabel => '服务商';

  @override
  String get uploadedAtLabel => '上传时间';

  @override
  String get statusLabel => '状态';

  @override
  String get uploadedStatus => '已上传';

  @override
  String errorWithMessage(String message) {
    return '错误：$message';
  }

  @override
  String get noLogsAvailable => '暂无日志';

  @override
  String get searchLogsHint => '搜索日志...';

  @override
  String get clearLogs => '清除日志';

  @override
  String get searchWithMinThreeCharacters => '至少输入 3 个字符后再搜索';

  @override
  String get typeBelowToSearch => '请在下方输入以开始搜索';

  @override
  String get noResults => '无结果。';

  @override
  String get welcomeTitle => '欢迎';

  @override
  String signInToContinue(String appName) {
    return '登录以继续使用 $appName';
  }

  @override
  String get pleaseEnterYourEmail => '请输入您的邮箱地址';

  @override
  String get pleaseEnterValidEmailAddress => '请输入有效的邮箱地址';

  @override
  String get emailAddressLabel => '邮箱地址';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => '重新发送 OTP';

  @override
  String get sendOtp => '发送 OTP';

  @override
  String get checkYourEmail => '请查收邮箱';

  @override
  String sentSixDigitCodeTo(String email) {
    return '我们已将 6 位验证码发送至\n$email';
  }

  @override
  String get pleaseEnterOtp => '请输入 OTP';

  @override
  String get otpMustBeSixDigits => 'OTP 必须为 6 位数字';

  @override
  String get enterOtpLabel => '输入 OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => '重新验证';

  @override
  String get verifyOtp => '验证 OTP';

  @override
  String get useDifferentEmail => '使用其他邮箱';

  @override
  String get alreadySignedIn => '已登录';

  @override
  String get sendingOtpFailedPleaseTryAgain => '发送 OTP 失败。请重试！';

  @override
  String get otpVerificationFailedPleaseTryAgain => 'OTP 验证失败。请重试。';

  @override
  String get dbViewerTitle => '数据库查看器';

  @override
  String get selectTableToViewData => '请选择一个表以查看其数据';

  @override
  String get selectTable => '选择表';

  @override
  String get permissionRequiredTitle => '需要权限';

  @override
  String get storagePermissionSettingsDescription =>
      '为了在后台自动备份、管理并保护您的文件，我们需要访问设备存储。您的数据会在本地加密，从而确保完全隐私。请允许访问后继续。';

  @override
  String get openSettings => '打开设置';

  @override
  String get secureLocalAccessTitle => '安全的本地访问';

  @override
  String get storagePermissionPageDescription => '为了浏览、加密并自动备份您的文件，我们需要访问设备存储。';

  @override
  String get verifying => '验证中...';

  @override
  String get grantAccess => '授予访问权限';

  @override
  String get zeroKnowledgeEncryptedStorage => '零知识加密存储';

  @override
  String get notificationPermissionTitle => '通知权限';

  @override
  String get notificationPermissionPageDescription =>
      '为了保持您的文件同步并在后台提供实时状态更新，我们需要您授予显示通知的权限。';

  @override
  String get notificationPermissionGrantButton => '允许通知';

  @override
  String get notificationPermissionSettingsDescription =>
      '通知对于监控后台同步至关重要。请在系统设置中启用通知，以确保您的数据始终是最新的。';

  @override
  String requiresAppPro(String appName) {
    return '需要 $appName Pro。';
  }

  @override
  String get noStorageFound => '未找到存储';

  @override
  String get howToConnect => '如何连接';

  @override
  String get modify => '修改';

  @override
  String storageUsed(String used, String total) {
    return '已用 $used / $total';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return '最高可享 $size 免费空间';
  }

  @override
  String get notConnected => '未连接';

  @override
  String get connect => '连接';

  @override
  String get modifyStorageCapacityTitle => '修改存储容量';

  @override
  String get enterNewStorageLimitForProvider => '请输入该服务商的新存储上限。';

  @override
  String get sizePrefix => '大小：';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => '请输入容量大小';

  @override
  String get enterValidNumberGreaterThanOne => '请输入大于 1 的有效数字';

  @override
  String get submit => '提交';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return '已成功订阅 $appName Pro！';
  }

  @override
  String get purchaseCancelledOrFailed => '购买已取消或失败。';

  @override
  String get purchasesRestoredSuccessfully => '购买已成功恢复！';

  @override
  String get noActiveSubscriptionsFound => '未找到有效订阅。';

  @override
  String get manageSubscriptionsInDeviceSettings => '请在设备设置中管理您的订阅。';

  @override
  String get freePlanTitle => '免费';

  @override
  String get freeForeverPrice => '\$0.00 / 永久';

  @override
  String get freeBenefitProviderStorage => '享受各服务商提供的免费存储';

  @override
  String get freeBenefitSyncThreeDevices => '最多安全同步 3 台设备';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - 年费版';
  }

  @override
  String get proBenefitModifyStorageLimit => '可为每个服务商调整存储上限';

  @override
  String get proBenefitSyncTenDevices => '最多可同步 10 台设备';

  @override
  String get restorePurchases => '恢复购买';

  @override
  String get subscriptionAssociatedWithEmailNotDevice => '* 订阅与邮箱账户关联，而不是与设备关联';

  @override
  String get subscriptionExpiredTitle => '订阅已过期';

  @override
  String subscriptionExpiredDescription(String appName) {
    return '您的 $appName Pro 权益已暂停。请在下方续订，以恢复存储上限和设备同步功能。';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro 已启用';
  }

  @override
  String get activePlanBenefitsSummary => '✓ 可为每个服务商调整存储上限\n✓ 最多支持 10 台设备跨设备同步';

  @override
  String get manageSubscription => '管理订阅';

  @override
  String get currentPlanBadge => '当前方案';

  @override
  String get subscribeNow => '立即订阅';

  @override
  String get subscribeOnMobileApp => '请在移动应用中订阅';

  @override
  String get recover => '恢复';

  @override
  String get empty => '清空';

  @override
  String get noItems => '暂无项目。';
}
