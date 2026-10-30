// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Thai (`th`).
class AppLocalizationsTh extends AppLocalizations {
  AppLocalizationsTh([String locale = 'th']) : super(locale);

  @override
  String get localSessionCleanupTitle => 'กำลังล้างข้อมูลในเครื่อง';

  @override
  String get localSessionCleanupDescription =>
      'เซสชันของคุณสิ้นสุดแล้ว FiFe ต้องล้างข้อมูลบัญชีในเครื่องให้เสร็จก่อนที่คุณจะลงชื่อเข้าใช้อีกครั้ง ไฟล์ต้นฉบับของคุณจะยังคงอยู่ ลองอีกครั้งเพื่อดำเนินการให้เสร็จ';

  @override
  String get localSessionCleanupInProgress =>
      'กำลังล้างข้อมูล FiFe จากอุปกรณ์นี้…';

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'เมื่อดำเนินการต่อ แสดงว่าคุณยอมรับ$termsและ$privacyของเรา';
  }

  @override
  String get termsOfService => 'ข้อกำหนดการให้บริการ';

  @override
  String get privacyPolicy => 'นโยบายความเป็นส่วนตัว';

  @override
  String get andLabel => ' และ ';

  @override
  String get theme => 'ธีม';

  @override
  String get themeTooltip => 'ธีมสว่าง/มืด';

  @override
  String get logging => 'บันทึกระบบ';

  @override
  String get appLockTitle => 'ล็อกแอป';

  @override
  String get appLockDescription =>
      'ปกป้อง FiFe ด้วยลายนิ้วมือ ใบหน้า หรือ PIN ของอุปกรณ์';

  @override
  String get appLockTimeout => 'ระยะเวลาก่อนล็อก';

  @override
  String get appLockTimeoutDescription =>
      'ขอให้ยืนยันตัวตนเมื่อออกจาก FiFe ครบระยะเวลานี้ การเริ่มแอปใหม่ต้องยืนยันตัวตนเสมอ';

  @override
  String get appLockAuthenticate => 'ยืนยันตัวตนเพื่อปลดล็อก FiFe';

  @override
  String get appLockChangeSettings =>
      'ยืนยันตัวตนเพื่อเปลี่ยนการตั้งค่าล็อกแอป';

  @override
  String get appLockAuthHint => 'ยืนยันตัวตนของคุณ';

  @override
  String get appLocked => 'FiFe ถูกล็อก';

  @override
  String get appLockUnlock => 'ปลดล็อก';

  @override
  String get appLockUnavailable =>
      'ไม่สามารถใช้การยืนยันตัวตนของอุปกรณ์ได้ ตั้งค่า PIN รหัสผ่าน หรือข้อมูลชีวมิติในการตั้งค่าอุปกรณ์ แล้วลองอีกครั้ง';

  @override
  String get appLockAuthenticationFailed =>
      'การยืนยันตัวตนยังไม่เสร็จสมบูรณ์ โปรดลองอีกครั้ง';

  @override
  String get appLockStorageError =>
      'ไม่สามารถอ่านหรือบันทึกการตั้งค่าล็อกแอปได้ ลองอีกครั้งเพื่อปกป้องคลังส่วนตัวของคุณ';

  @override
  String get quickSyncNotificationSettingTitle =>
      'การแจ้งเตือนการซิงก์อัตโนมัติ';

  @override
  String get autoSyncInterval => 'ช่วงเวลาซิงค์อัตโนมัติ';

  @override
  String get autoSyncIntervalDescription =>
      'ซิงค์อัตโนมัติขณะเปิดใช้การแจ้งเตือนการซิงก์อัตโนมัติ';

  @override
  String syncIntervalMinutes(int minutes) {
    return '$minutes นาที';
  }

  @override
  String get autoSyncIntervalSaveError =>
      'บันทึกช่วงเวลาไม่ได้ โปรดลองอีกครั้ง';

  @override
  String get autoSyncIntervalApplyError =>
      'บันทึกช่วงเวลาแล้ว ปิดแล้วเปิดการแจ้งเตือนการซิงก์อัตโนมัติอีกครั้งเพื่อใช้ค่าใหม่';

  @override
  String get sync => 'ซิงค์';

  @override
  String get quickSyncNotificationTitle => 'บริการซิงก์ไฟล์';

  @override
  String quickSyncNotificationText(int minutes) {
    return 'ทำงานทุก $minutes นาที';
  }

  @override
  String get quickSyncNotificationInProgress => 'กำลังดำเนินการ...';

  @override
  String get reportIssue => 'รายงานปัญหา';

  @override
  String get sourceCode => 'ซอร์สโค้ด';

  @override
  String get desktopApp => 'แอปเดสก์ท็อป';

  @override
  String get mobileApp => 'แอปมือถือ';

  @override
  String get leaveReview => 'เขียนรีวิว';

  @override
  String get share => 'แชร์';

  @override
  String get versionLabel => 'เวอร์ชัน: ';

  @override
  String get loading => 'กำลังโหลด...';

  @override
  String get signOut => 'ออกจากระบบ';

  @override
  String get settingsPageTitle => 'การตั้งค่า';

  @override
  String get language => 'ภาษา';

  @override
  String get tapToSelect => 'แตะเพื่อเลือก';

  @override
  String get appTagline => 'เรือขนไฟล์ส่วนตัวของคุณ';

  @override
  String get onboardingPurposeDescription =>
      'บริการจัดเก็บข้อมูลบนคลาวด์แบบโอเพนซอร์สที่สร้างบนสถาปัตยกรรม zero-trust ข้อมูลของคุณจะถูกเข้ารหัสในอุปกรณ์ก่อนออกจากเครื่องเสมอ';

  @override
  String get failedToFetch => 'ไม่สามารถดึงข้อมูลได้';

  @override
  String get supportedStorageTitle => 'พื้นที่จัดเก็บที่รองรับ';

  @override
  String get supportedStorageDescription =>
      'เชื่อมต่อผู้ให้บริการที่คุณชื่นชอบได้ทันที และเริ่มต้นด้วยพื้นที่จัดเก็บปลอดภัยฟรี 1 GB จาก FiFe';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'เริ่มสำรองข้อมูลได้ทันที';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'ฟรี';

  @override
  String get providerStorageDisclaimer =>
      '* พื้นที่ฟรีเป็นไปตามที่ระบุไว้บนเว็บไซต์ของผู้ให้บริการ และผู้ให้บริการที่รองรับจะคิดค่าบริการตามการใช้งานจริง';

  @override
  String get whyUseFifeTitle => 'ทำไมต้องใช้ FiFe?';

  @override
  String get claimFreeCloudStorageTitle => 'รวมพื้นที่คลาวด์ฟรีไว้ในที่เดียว';

  @override
  String get claimFreeCloudStorageDescription =>
      'เพิ่มพื้นที่ใช้งานของคุณด้วยการเชื่อมต่อผู้ให้บริการคลาวด์หลายราย และใช้สิทธิ์พื้นที่ฟรีของแต่ละเจ้าผ่านแอปเดียวอย่างปลอดภัย';

  @override
  String get topNotchSecurityTitle => 'ความปลอดภัยระดับสูง';

  @override
  String get topNotchSecurityDescription =>
      'ขับเคลื่อนด้วยการเข้ารหัส Sodium ขั้นสูง การเข้ารหัสและถอดรหัสทั้งหมดเกิดขึ้นภายในอุปกรณ์ของคุณเท่านั้น';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'ควบคุมข้อมูลของคุณได้อย่างเต็มที่กับผู้ให้บริการคลาวด์ทุกเจ้า โดยใช้บัญชีของคุณเองกับพื้นที่จัดเก็บที่เข้ารหัสไว้';

  @override
  String get payAsYouGoStorageTitle => 'จ่ายเฉพาะพื้นที่ที่ใช้งาน';

  @override
  String get payAsYouGoStorageDescription =>
      'จ่ายเฉพาะพื้นที่ที่ใช้จริงกับผู้ให้บริการที่รองรับ ไม่มีคนกลาง และไม่ถูกผูกกับแพลตฟอร์มใดแพลตฟอร์มหนึ่ง';

  @override
  String get zeroKnowledgePrivacyTitle => 'ความเป็นส่วนตัวแบบ Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'ข้อมูลของคุณถูกล็อกไว้ในอุปกรณ์ก่อนส่งออก เราไม่สามารถเห็น อ่าน หรือสแกนไฟล์ของคุณได้';

  @override
  String get localSelectionTitle => '1. เลือกจากอุปกรณ์';

  @override
  String get localSelectionDescription =>
      'คุณเลือกโฟลเดอร์ได้เอง และทุกขั้นตอนจะเริ่มต้นอย่างปลอดภัยบนอุปกรณ์ของคุณ';

  @override
  String get metadataEncryptionTitle => '2. เข้ารหัสเมทาดาทา';

  @override
  String get metadataEncryptionDescription =>
      'ข้อมูลของไฟล์ เช่น ชื่อ ประเภท และขนาด จะถูกเข้ารหัสก่อนส่งไปยังเซิร์ฟเวอร์';

  @override
  String get contentEncryptionTitle => '3. เข้ารหัสเนื้อหาไฟล์';

  @override
  String get contentEncryptionDescription =>
      'เนื้อหาไฟล์จริงจะถูกแบ่งและเข้ารหัสก่อนอัปโหลดไปยังคลาวด์สตอเรจ';

  @override
  String get blindServerTitle => '4. เซิร์ฟเวอร์ที่ไม่เห็นข้อมูล';

  @override
  String get blindServerDescription =>
      'เซิร์ฟเวอร์ของเราไม่มีความรู้เกี่ยวกับข้อมูลของคุณ โดยจะเห็นเพียงข้อมูลที่ถูกเข้ารหัสเท่านั้น เพื่อความเป็นส่วนตัวสูงสุด';

  @override
  String get dontTrustVerifyTitle => 'อย่าแค่เชื่อ ตรวจสอบได้ด้วยตัวเอง';

  @override
  String get openSourceVerificationDescription =>
      'โอเพนซอร์ส 100% คุณสามารถตรวจสอบโค้ดได้ด้วยตัวเองว่าไฟล์ของคุณถูกเข้ารหัสอย่างไร';

  @override
  String get getStarted => 'เริ่มต้น';

  @override
  String get next => 'ถัดไป';

  @override
  String get unauthorized => 'ไม่ได้รับอนุญาต';

  @override
  String get tryAgain => 'ลองอีกครั้ง';

  @override
  String get errorTitle => 'ข้อผิดพลาด';

  @override
  String get failureTitle => 'ไม่สำเร็จ';

  @override
  String get invalidWordList => 'รายการคำไม่ถูกต้อง';

  @override
  String get invalidAccessKey => 'คีย์เข้าถึงไม่ถูกต้อง';

  @override
  String get unexpectedDecryptionError =>
      'เกิดข้อผิดพลาดที่ไม่คาดคิดระหว่างการถอดรหัส';

  @override
  String get fileMustContainExactly24Words => 'ไฟล์ต้องมีคำทั้งหมด 24 คำพอดี';

  @override
  String get errorReadingFile => 'เกิดข้อผิดพลาดในการอ่านไฟล์';

  @override
  String get encryptionTitle => 'การเข้ารหัส';

  @override
  String get accessKeyDecodeDescription =>
      'ป้อนวลีกู้คืน 24 คำของคุณ หรือโหลดไฟล์ .txt เพื่อเปิดใช้งานการซิงก์กับคลาวด์อย่างปลอดภัย';

  @override
  String get recoveryPhraseLabel => 'วลีกู้คืน';

  @override
  String get recoveryPhraseHint => 'คำ1 คำ2 คำ3...';

  @override
  String get paste => 'วาง';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 คำ';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'โปรดป้อนวลีกู้คืนของคุณ';

  @override
  String get mustContainExactly24Words => 'ต้องมีครบ 24 คำพอดี';

  @override
  String get verify => 'ยืนยัน';

  @override
  String get orLabel => 'หรือ';

  @override
  String get loadFromTxtFile => 'โหลดจากไฟล์ .txt';

  @override
  String get saveAccessKey => 'บันทึกคีย์เข้าถึง';

  @override
  String get fileSavedSuccessfully => 'บันทึกไฟล์สำเร็จ';

  @override
  String get accessKeyShareMessage => 'นี่คือคีย์เข้าถึงของคุณ';

  @override
  String get pleaseTryAgain => 'โปรดลองอีกครั้ง';

  @override
  String get copiedToClipboard => 'คัดลอกไปยังคลิปบอร์ดแล้ว';

  @override
  String get accessKeyTitle => 'คีย์เข้าถึง';

  @override
  String get accessKeyDescription =>
      'โปรดเก็บคีย์นี้ไว้ในที่ปลอดภัย เพราะนี่คือสิ่งเดียวที่จะช่วยให้คุณเข้าถึงข้อมูลที่เข้ารหัสไว้ได้';

  @override
  String get copy => 'คัดลอก';

  @override
  String get downloadAsTextFile => 'ดาวน์โหลดเป็นไฟล์ข้อความ';

  @override
  String get continueLabel => 'ดำเนินการต่อ';

  @override
  String get importantTitle => 'สำคัญ';

  @override
  String get accessKeyNoticePrimary =>
      'ในหน้าถัดไป คุณจะเห็นชุดคำทั้งหมด 24 คำ ซึ่งเป็นคีย์เข้ารหัสส่วนตัวเฉพาะของคุณ และเป็นวิธีเดียวเท่านั้นในการกู้คืนข้อมูล หากคุณออกจากระบบ ทำอุปกรณ์หาย หรืออุปกรณ์เกิดปัญหา';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'เราไม่ได้เก็บคีย์นี้ไว้ คุณต้องรับผิดชอบในการเก็บรักษาไว้ในที่ปลอดภัยนอกแอป $appName';
  }

  @override
  String get showKeyConfirmation => 'ฉันเข้าใจแล้ว\nแสดงคีย์ให้ฉัน';

  @override
  String get storageAddedSuccessfully => 'เพิ่มพื้นที่จัดเก็บสำเร็จ';

  @override
  String get networkErrorDuringValidation =>
      'เกิดข้อผิดพลาดเครือข่ายระหว่างการตรวจสอบ';

  @override
  String get verifyAndConnect => 'ยืนยันและเชื่อมต่อ';

  @override
  String get requiredField => 'จำเป็นต้องกรอก';

  @override
  String get providerKeysVerifiedLocally =>
      'คีย์ของคุณจะถูกตรวจสอบในเครื่องและเข้ารหัสก่อนส่งออก';

  @override
  String get enterYourCredentials => 'ป้อนข้อมูลรับรองของคุณ';

  @override
  String connectProvider(String provider) {
    return 'เชื่อมต่อ $provider';
  }

  @override
  String get deviceLimitReached => 'ถึงขีดจำกัดจำนวนอุปกรณ์แล้ว';

  @override
  String get pleaseTryAgainWithExclamation => 'โปรดลองอีกครั้ง!';

  @override
  String get notThisDevice => 'ไม่ใช่อุปกรณ์นี้!';

  @override
  String get confirmSignoutDeviceTitle => 'ยืนยันการออกจากระบบของอุปกรณ์';

  @override
  String get areYouSure => 'คุณแน่ใจหรือไม่';

  @override
  String get cancel => 'ยกเลิก';

  @override
  String get ok => 'ตกลง';

  @override
  String get noDeviceFound => 'ไม่พบอุปกรณ์';

  @override
  String get backTooltip => 'ย้อนกลับ';

  @override
  String get devicesTitle => 'อุปกรณ์';

  @override
  String get longPressToDownload => 'กดค้างเพื่อดาวน์โหลด';

  @override
  String get fewItemsExistLocally => 'ยังมีบางรายการอยู่ในอุปกรณ์';

  @override
  String selectedItemsCount(int count) {
    return 'เลือกแล้ว $count รายการ';
  }

  @override
  String get delete => 'ลบ';

  @override
  String get info => 'ข้อมูล';

  @override
  String get download => 'ดาวน์โหลด';

  @override
  String get archive => 'เก็บถาวร';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'บันทึก';

  @override
  String get settings => 'การตั้งค่า';

  @override
  String get trash => 'ถังขยะ';

  @override
  String get storage => 'พื้นที่จัดเก็บ';

  @override
  String get search => 'ค้นหา';

  @override
  String get database => 'ฐานข้อมูล';

  @override
  String get addFolderTitle => 'เพิ่มโฟลเดอร์';

  @override
  String get confirm => 'ยืนยัน';

  @override
  String get tapPlusToAddSyncFolder => 'แตะ + เพื่อเพิ่มโฟลเดอร์ซิงก์';

  @override
  String get thisFolderIsEmpty => 'โฟลเดอร์นี้ว่างเปล่า';

  @override
  String get fileNotFound => 'ไม่พบไฟล์';

  @override
  String filePartsTitle(int count) {
    return 'ชิ้นส่วนไฟล์ ($count)';
  }

  @override
  String get fileDetailsTitle => 'รายละเอียดไฟล์';

  @override
  String get encryptedBackup => 'ข้อมูลสำรองที่เข้ารหัส';

  @override
  String get sizeLabel => 'ขนาด';

  @override
  String get providerLabel => 'ผู้ให้บริการ';

  @override
  String get uploadedAtLabel => 'อัปโหลดเมื่อ';

  @override
  String get statusLabel => 'สถานะ';

  @override
  String get uploadedStatus => 'อัปโหลดแล้ว';

  @override
  String errorWithMessage(String message) {
    return 'ข้อผิดพลาด: $message';
  }

  @override
  String get noLogsAvailable => 'ไม่มีบันทึก';

  @override
  String get searchLogsHint => 'ค้นหาในบันทึก...';

  @override
  String get clearLogs => 'ล้างบันทึก';

  @override
  String get searchWithMinThreeCharacters => 'ค้นหาด้วยอย่างน้อย 3 ตัวอักษร';

  @override
  String get typeBelowToSearch => 'พิมพ์ด้านล่างเพื่อค้นหา';

  @override
  String get noResults => 'ไม่พบผลลัพธ์';

  @override
  String get welcomeTitle => 'ยินดีต้อนรับ';

  @override
  String signInToContinue(String appName) {
    return 'ลงชื่อเข้าใช้เพื่อใช้งาน $appName ต่อ';
  }

  @override
  String get pleaseEnterYourEmail => 'โปรดป้อนอีเมลของคุณ';

  @override
  String get pleaseEnterValidEmailAddress => 'โปรดป้อนอีเมลที่ถูกต้อง';

  @override
  String get emailAddressLabel => 'อีเมล';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'ส่ง OTP อีกครั้ง';

  @override
  String get sendOtp => 'ส่ง OTP';

  @override
  String get checkYourEmail => 'ตรวจสอบอีเมลของคุณ';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'เราได้ส่งรหัส 6 หลักไปที่\n$email';
  }

  @override
  String get pleaseEnterOtp => 'โปรดป้อน OTP';

  @override
  String get otpMustBeSixDigits => 'OTP ต้องมี 6 หลัก';

  @override
  String get enterOtpLabel => 'ป้อน OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'ยืนยันอีกครั้ง';

  @override
  String get verifyOtp => 'ยืนยัน OTP';

  @override
  String get useDifferentEmail => 'ใช้อีเมลอื่น';

  @override
  String get alreadySignedIn => 'ลงชื่อเข้าใช้แล้ว';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'ส่ง OTP ไม่สำเร็จ โปรดลองอีกครั้ง!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'ยืนยัน OTP ไม่สำเร็จ โปรดลองอีกครั้ง';

  @override
  String get dbViewerTitle => 'ตัวดูฐานข้อมูล';

  @override
  String get selectTableToViewData => 'เลือกตารางเพื่อดูข้อมูล';

  @override
  String get selectTable => 'เลือกตาราง';

  @override
  String get permissionRequiredTitle => 'ต้องการสิทธิ์การเข้าถึง';

  @override
  String get storagePermissionSettingsDescription =>
      'เพื่อสำรองข้อมูล จัดการ และปกป้องไฟล์ของคุณในเบื้องหลังโดยอัตโนมัติ เราจำเป็นต้องเข้าถึงพื้นที่จัดเก็บในอุปกรณ์ของคุณ ข้อมูลของคุณจะถูกเข้ารหัสภายในเครื่องเพื่อให้เป็นส่วนตัวอย่างสมบูรณ์ โปรดอนุญาตการเข้าถึงเพื่อดำเนินการต่อ';

  @override
  String get openSettings => 'เปิดการตั้งค่า';

  @override
  String get secureLocalAccessTitle => 'การเข้าถึงในเครื่องอย่างปลอดภัย';

  @override
  String get storagePermissionPageDescription =>
      'เพื่อสำรวจ เข้ารหัส และสำรองข้อมูลไฟล์ของคุณโดยอัตโนมัติ เราจำเป็นต้องเข้าถึงพื้นที่จัดเก็บในอุปกรณ์ของคุณ';

  @override
  String get verifying => 'กำลังตรวจสอบ...';

  @override
  String get grantAccess => 'อนุญาตการเข้าถึง';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'พื้นที่จัดเก็บเข้ารหัสแบบ Zero-Knowledge';

  @override
  String get notificationPermissionTitle => 'การเข้าถึงการแจ้งเตือน';

  @override
  String get notificationPermissionPageDescription =>
      'เพื่อซิงค์และอัปโหลดไฟล์ของคุณอย่างรวดเร็วในเบื้องหลังผ่านแผงการแจ้งเตือน เราจำเป็นต้องได้รับสิทธิ์ในการแสดงการแจ้งเตือน คุณสามารถปิดได้ทุกเมื่อจากการตั้งค่า';

  @override
  String get notificationPermissionGrantButton => 'อนุญาตการแจ้งเตือน';

  @override
  String get notificationPermissionSettingsDescription =>
      'จำเป็นต้องเปิดการแจ้งเตือนเพื่อใช้งานการซิงค์ด่วนผ่านแผงการแจ้งเตือน โปรดเปิดใช้งานในการตั้งค่าระบบเพื่อให้แน่ใจว่าข้อมูลทั้งหมดของคุณได้รับการอัปโหลด';

  @override
  String requiresAppPro(String appName) {
    return 'ต้องใช้ $appName Pro';
  }

  @override
  String get noStorageFound => 'ไม่พบพื้นที่จัดเก็บ';

  @override
  String get howToConnect => 'วิธีเชื่อมต่อ';

  @override
  String get modify => 'แก้ไข';

  @override
  String storageUsed(String used, String total) {
    return 'ใช้ไป $used / $total';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'ฟรีสูงสุด $size';
  }

  @override
  String get notConnected => 'ยังไม่ได้เชื่อมต่อ';

  @override
  String get connect => 'เชื่อมต่อ';

  @override
  String get modifyStorageCapacityTitle => 'แก้ไขขนาดพื้นที่จัดเก็บ';

  @override
  String get enterNewStorageLimitForProvider =>
      'ป้อนขีดจำกัดพื้นที่จัดเก็บใหม่สำหรับผู้ให้บริการนี้';

  @override
  String get sizePrefix => 'ขนาด: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'โปรดป้อนขนาด';

  @override
  String get enterValidNumberGreaterThanOne =>
      'ป้อนตัวเลขที่ถูกต้องและมากกว่า 1';

  @override
  String get submit => 'ส่ง';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'สมัคร $appName Pro สำเร็จแล้ว!';
  }

  @override
  String get purchaseCancelledOrFailed => 'ยกเลิกการซื้อหรือการซื้อไม่สำเร็จ';

  @override
  String get purchasesRestoredSuccessfully => 'กู้คืนการซื้อสำเร็จ!';

  @override
  String get noActiveSubscriptionsFound =>
      'ไม่พบการสมัครใช้งานที่ยังใช้งานอยู่';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'โปรดจัดการการสมัครใช้งานในการตั้งค่าของอุปกรณ์';

  @override
  String get freePlanTitle => 'ฟรี';

  @override
  String get freeForeverPrice => '\$0.00 / ตลอดไป';

  @override
  String get freeBenefitProviderStorage =>
      'ใช้งานพื้นที่ฟรีจากผู้ให้บริการต่าง ๆ';

  @override
  String get freeBenefitSyncThreeDevices =>
      'ซิงก์ได้อย่างปลอดภัยสูงสุด 3 อุปกรณ์';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - รายปี';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'ปรับขีดจำกัดพื้นที่จัดเก็บของแต่ละผู้ให้บริการได้';

  @override
  String get proBenefitSyncTenDevices => 'ซิงก์ได้สูงสุด 10 อุปกรณ์';

  @override
  String get restorePurchases => 'กู้คืนการซื้อ';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* การสมัครใช้งานผูกกับบัญชีอีเมล ไม่ได้ผูกกับอุปกรณ์';

  @override
  String get subscriptionExpiredTitle => 'การสมัครใช้งานหมดอายุ';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'สิทธิประโยชน์ของ $appName Pro ของคุณถูกระงับชั่วคราว ต่ออายุด้านล่างเพื่อกู้คืนขีดจำกัดพื้นที่จัดเก็บและการซิงก์ระหว่างอุปกรณ์';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro เปิดใช้งานอยู่';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ ปรับขีดจำกัดพื้นที่จัดเก็บของแต่ละผู้ให้บริการได้\n✓ ซิงก์ข้ามอุปกรณ์ได้สูงสุด 10 เครื่อง';

  @override
  String get manageSubscription => 'จัดการการสมัครใช้งาน';

  @override
  String get currentPlanBadge => 'แผนปัจจุบัน';

  @override
  String get subscribeNow => 'สมัครตอนนี้';

  @override
  String get subscribeOnMobileApp => 'สมัครผ่านแอปมือถือ';

  @override
  String get recover => 'กู้คืน';

  @override
  String get empty => 'ล้าง';

  @override
  String get noItems => 'ไม่มีรายการ';

  @override
  String get lostRecoveryPhrase => 'ทำวลีการกู้คืนหาย';

  @override
  String get lostRecoveryIntro =>
      'หากอุปกรณ์อื่นยังลงชื่อเข้าใช้อยู่ ให้ส่งออกวลีการกู้คืนจากอุปกรณ์นั้นก่อนเริ่มต้นใหม่';

  @override
  String get lostRecoveryDeleteConsequence =>
      'คลัง FiFe ปัจจุบัน ไฟล์ที่สำรองไว้ และคีย์เข้ารหัสเดิมของคุณจะถูกลบอย่างถาวร';

  @override
  String get lostRecoveryDevicesConsequence =>
      'การลงทะเบียนอุปกรณ์ที่มีอยู่ทั้งหมดจะถูกลบ';

  @override
  String get lostRecoveryLogoutConsequence =>
      'อุปกรณ์อื่นจะออกจากระบบและล้างข้อมูล FiFe ในเครื่อง เมื่อเชื่อมต่ออินเทอร์เน็ตและตรวจพบว่าถูกนำออกแล้ว';

  @override
  String get lostRecoveryKeepConsequence =>
      'บัญชีอีเมล การสมัครสมาชิก การเชื่อมต่อที่เก็บข้อมูลบนคลาวด์ และข้อมูลรับรองของผู้ให้บริการจะยังคงอยู่ ไฟล์ในโฟลเดอร์ส่วนตัวของคุณนอก FiFe จะยังคงอยู่ด้วย';

  @override
  String get lostRecoveryWaitConsequence =>
      'ห้องนิรภัยใหม่จะยังถูกล็อกจนกว่าจะยืนยันการลบบนคลาวด์ได้ ซึ่งอาจใช้เวลา 15 นาทีขึ้นไป คุณสามารถปิด FiFe แล้วกลับมาทำต่อภายหลังได้';

  @override
  String get lostRecoveryNewPhraseConsequence =>
      'คุณจะยังคงลงชื่อเข้าใช้บนอุปกรณ์นี้ หลังจากยืนยันการลบแล้ว ให้สร้างและบันทึกวลีกู้คืนใหม่ 24 คำ';

  @override
  String get recoveryResetUnavailable =>
      'ไม่สามารถรีเซ็ตห้องนิรภัยได้ชั่วคราว โปรดลองอีกครั้งในภายหลัง';

  @override
  String get recoveryResetSigninRequired =>
      'ลงชื่อเข้าใช้อีกครั้งเพื่อยืนยันเซสชันของคุณก่อนรีเซ็ตคลังข้อมูล';

  @override
  String get recoveryResetContinue => 'ดำเนินการรีเซ็ตต่อ';

  @override
  String get recoveryResetConfirmTitle => 'ลบห้องนิรภัย FiFe อย่างถาวรหรือไม่';

  @override
  String get recoveryResetConfirmBody =>
      'การดำเนินการนี้ไม่สามารถย้อนกลับได้ วลีการกู้คืนปัจจุบันจะใช้งานไม่ได้ และอุปกรณ์ทั้งหมดของคุณจะถูกนำออก';

  @override
  String get recoveryResetDelete => 'ลบห้องนิรภัยและเริ่มใหม่';

  @override
  String get recoveryResetPendingTitle => 'กำลังลบห้องนิรภัยเดิม';

  @override
  String get recoveryResetPendingBody =>
      'FiFe กำลังตรวจสอบการลบบนคลาวด์ คุณสามารถปิดแอปแล้วกลับมาภายหลังได้';

  @override
  String recoveryResetWaitUntil(String when) {
    return 'การตรวจสอบจะเสร็จก่อน $when ไม่ได้';
  }

  @override
  String get recoveryResetStorageBlocked =>
      'การลบบนคลาวด์ต้องได้รับการแก้ไข โปรดคืนสิทธิ์เข้าถึงและสิทธิ์ลบสำหรับที่เก็บข้อมูลที่เชื่อมโยง แล้วลองอีกครั้ง';

  @override
  String get recoveryResetSignin =>
      'ลงชื่อเข้าใช้อีกครั้งเพื่อดำเนินการรีเซ็ตต่อ';

  @override
  String recoveryResetSigninAs(String email) {
    return 'ลงชื่อเข้าใช้ด้วย $email เพื่อดำเนินการรีเซ็ตต่อ';
  }

  @override
  String get recoveryResetNeedsConfirmation =>
      'ยืนยันการรีเซ็ตเพื่อดำเนินการต่อ FiFe จะตรวจสอบว่าเริ่มไปแล้วหรือยัง';

  @override
  String get recoveryResetConfirmationWait =>
      'การยืนยันก่อนหน้ายังมีผล โปรดตรวจสอบอีกครั้งหลังหมดอายุก่อนเริ่มการยืนยันใหม่';

  @override
  String recoveryResetConfirmationUntil(String when) {
    return 'ตรวจสอบอีกครั้งหลัง $when';
  }

  @override
  String get recoveryResetMissingKeys =>
      'คีย์กู้คืนใหม่ไม่พร้อมใช้งานบนอุปกรณ์นี้ ให้ดำเนินการต่อบนอุปกรณ์ที่เริ่มรีเซ็ต หากคีย์สูญหาย ให้รอจนการลบเสร็จสิ้น จากนั้นลงชื่อเข้าใช้แล้วเลือก “ทำวลีการกู้คืนหาย” อีกครั้ง';

  @override
  String get recoveryResetDiscard => 'กลับไปลงชื่อเข้าใช้';

  @override
  String get recoveryResetDiscardBody =>
      'การดำเนินการนี้จะล้างการตั้งค่าการกู้คืนที่ยังไม่เสร็จบนอุปกรณ์นี้ หลังลงชื่อเข้าใช้ คุณจะต้องใช้วลีการกู้คืนใหม่หรือรีเซ็ตห้องนิรภัยอีกครั้ง';

  @override
  String get recoveryPhraseSaved => 'ฉันบันทึกวลีการกู้คืนใหม่แล้ว';

  @override
  String get recoveryResetStarting => 'กำลังเริ่มรีเซ็ต…';

  @override
  String get sessionExpiredRetained =>
      'เซสชันการเข้าสู่ระบบหมดอายุแล้ว โปรดเข้าสู่ระบบอีกครั้งเพื่อปลดล็อกคลังข้อมูล ข้อมูลในเครื่องของคุณยังคงอยู่';

  @override
  String get signinVerifiedContinue =>
      'ยืนยันอีเมลของคุณแล้ว ดำเนินการต่อเพื่อเข้าสู่ระบบให้เสร็จสมบูรณ์';

  @override
  String get noSupportedApplication => 'ไม่มีแอปที่รองรับการดูไฟล์นี้';

  @override
  String get fileAccessUnavailable =>
      'ไม่สามารถเข้าถึงไฟล์นี้ได้ โปรดตรวจสอบสิทธิ์ของโฟลเดอร์แล้วลองอีกครั้ง';

  @override
  String get unableToOpenFile => 'ไม่สามารถเปิดไฟล์นี้ได้ โปรดลองอีกครั้ง';

  @override
  String get fileNotAvailable =>
      'ไม่มีไฟล์นี้ในอุปกรณ์นี้หรือในข้อมูลสำรองที่เสร็จสมบูรณ์';

  @override
  String get downloadRecoveryPhrase => 'ดาวน์โหลดวลีกู้คืน';

  @override
  String get recoveryPhraseExportHint =>
      'ยืนยันตัวตนเพื่อดู คัดลอก หรือบันทึกวลีกู้คืนของคุณ';

  @override
  String get recoveryPhraseExportAuth => 'ยืนยันตัวตนเพื่อดูวลีกู้คืนของคุณ';

  @override
  String get recoveryPhraseExportWarning =>
      'ทุกคนที่มีคำเหล่านี้สามารถปลดล็อกห้องนิรภัยของคุณได้ เก็บสำเนาไว้เป็นส่วนตัวนอก FiFe';

  @override
  String get recoveryPhraseUnavailable =>
      'ไม่สามารถโหลดวลีกู้คืนได้ ลองอีกครั้ง หรือใช้ข้อมูลสำรองที่บันทึกไว้หรืออุปกรณ์อื่นที่เข้าสู่ระบบแล้ว';

  @override
  String get reconnect => 'เชื่อมต่ออีกครั้ง';

  @override
  String get archiveBackup => 'เก็บข้อมูลสำรองเข้าคลัง';

  @override
  String get archiveFolderBackupMessage =>
      'ย้ายข้อมูลสำรองของโฟลเดอร์ที่เลือกไปยังถังขยะ และลบสำเนาที่ดาวน์โหลดออกจาก FiFe หรือไม่? ไฟล์ต้นฉบับและโฟลเดอร์อื่นจะยังอยู่ เส้นทางโฟลเดอร์เหล่านี้จะไม่ถูกซิงค์จนกว่าคุณจะกู้คืนจากถังขยะ';

  @override
  String get menuBarOpen => 'เปิด';

  @override
  String get menuBarQuit => 'ออก';

  @override
  String get appLockMacDescription =>
      'ปกป้อง FiFe ด้วย Touch ID หรือรหัสผ่านเข้าสู่ระบบ Mac ของคุณ';

  @override
  String get appLockMacUnavailable =>
      'ไม่สามารถใช้การยืนยันตัวตนของ Mac ได้ ตั้งค่ารหัสผ่านเข้าสู่ระบบหรือ Touch ID ในการตั้งค่าระบบ แล้วลองอีกครั้ง';

  @override
  String get appLockLinuxDescription =>
      'ใช้รหัสผ่านเข้าสู่ระบบ Linux เพื่อปกป้อง FiFe';

  @override
  String get appLockLinuxUnavailable =>
      'ไม่สามารถใช้การยืนยันตัวตนของระบบได้ โปรดติดตั้งการรองรับการยืนยันตัวตนของ FiFe แล้วลองอีกครั้ง';

  @override
  String get appLockLinuxAuthentication =>
      'ยืนยันตัวตนเพื่อดำเนินการต่อใน FiFe';
}
