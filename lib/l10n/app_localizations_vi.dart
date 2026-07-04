// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Bằng việc tiếp tục, bạn đồng ý với $terms và $privacy của chúng tôi.';
  }

  @override
  String get termsOfService => 'Điều khoản dịch vụ';

  @override
  String get privacyPolicy => 'Chính sách quyền riêng tư';

  @override
  String get andLabel => ' và ';

  @override
  String get theme => 'Giao diện';

  @override
  String get themeTooltip => 'Giao diện sáng/tối';

  @override
  String get logging => 'Nhật ký';

  @override
  String get quickSyncNotificationSettingTitle => 'Thông báo đồng bộ nhanh';

  @override
  String get quickSyncNotificationTitle => 'Dịch vụ đồng bộ tập tin';

  @override
  String get quickSyncNotificationText => 'Chạm vào nút bên dưới để đồng bộ';

  @override
  String get quickSyncNotificationButton => 'Đồng bộ ngay';

  @override
  String get quickSyncNotificationInProgress => 'Đang thực hiện...';

  @override
  String get reportIssue => 'Báo cáo sự cố';

  @override
  String get sourceCode => 'Mã nguồn';

  @override
  String get desktopApp => 'Ứng dụng máy tính';

  @override
  String get mobileApp => 'Ứng dụng di động';

  @override
  String get leaveReview => 'Để lại đánh giá';

  @override
  String get share => 'Chia sẻ';

  @override
  String get versionLabel => 'Phiên bản: ';

  @override
  String get loading => 'Đang tải...';

  @override
  String get signOut => 'Đăng xuất';

  @override
  String get settingsPageTitle => 'Cài đặt';

  @override
  String get language => 'Ngôn ngữ';

  @override
  String get tapToSelect => 'Chạm để chọn';

  @override
  String get appTagline => 'Người vận chuyển riêng tư cho tập tin của bạn';

  @override
  String get onboardingPurposeDescription =>
      'Dịch vụ lưu trữ đám mây mã nguồn mở được xây dựng trên kiến trúc zero-trust. Dữ liệu của bạn được mã hóa ngay trên thiết bị trước khi rời khỏi máy.';

  @override
  String get failedToFetch => 'Không thể tải dữ liệu.';

  @override
  String get supportedStorageTitle => 'Lưu trữ được hỗ trợ';

  @override
  String get supportedStorageDescription =>
      'Kết nối các nhà cung cấp bạn yêu thích. Bắt đầu ngay với 1 GB lưu trữ bảo mật miễn phí tích hợp sẵn của FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Bắt đầu sao lưu ngay';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Miễn phí';

  @override
  String get providerStorageDisclaimer =>
      '* Dung lượng miễn phí theo thông tin trên website của nhà cung cấp. Các nhà cung cấp tương thích hỗ trợ hình thức trả theo mức sử dụng.';

  @override
  String get whyUseFifeTitle => 'Vì sao nên dùng FiFe?';

  @override
  String get claimFreeCloudStorageTitle =>
      'Nhận thêm dung lượng đám mây miễn phí';

  @override
  String get claimFreeCloudStorageDescription =>
      'Tận dụng tối đa dung lượng bằng cách kết nối nhiều nhà cung cấp đám mây. Khai thác an toàn các gói lưu trữ miễn phí của họ trong một ứng dụng duy nhất.';

  @override
  String get topNotchSecurityTitle => 'Bảo mật hàng đầu';

  @override
  String get topNotchSecurityDescription =>
      'Được hỗ trợ bởi công nghệ mật mã Sodium tiên tiến. Mọi thao tác mã hóa và giải mã đều diễn ra hoàn toàn trên thiết bị của bạn.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Toàn quyền kiểm soát dữ liệu của bạn trên mọi nhà cung cấp lưu trữ đám mây. Lưu trữ dữ liệu đã mã hóa bằng chính các tài khoản của bạn.';

  @override
  String get payAsYouGoStorageTitle => 'Chỉ trả tiền cho dung lượng bạn dùng.';

  @override
  String get payAsYouGoStorageDescription =>
      'Chỉ thanh toán cho dung lượng đã sử dụng với các nhà cung cấp tương thích. Không qua trung gian, không bị khóa dữ liệu.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Quyền riêng tư Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Dữ liệu của bạn được khóa trên thiết bị trước khi được gửi đi. Chúng tôi không thể xem, đọc hay quét các tập tin của bạn.';

  @override
  String get localSelectionTitle => '1. Chọn cục bộ';

  @override
  String get localSelectionDescription =>
      'Bạn chọn một thư mục. Mọi xử lý đều bắt đầu an toàn ngay trên thiết bị của bạn.';

  @override
  String get metadataEncryptionTitle => '2. Mã hóa siêu dữ liệu';

  @override
  String get metadataEncryptionDescription =>
      'Thông tin tập tin (tên, loại và kích thước) được mã hóa trước khi gửi lên máy chủ.';

  @override
  String get contentEncryptionTitle => '3. Mã hóa nội dung';

  @override
  String get contentEncryptionDescription =>
      'Nội dung tập tin thực tế được chia nhỏ và mã hóa trước khi tải lên lưu trữ đám mây.';

  @override
  String get blindServerTitle => '4. Máy chủ mù';

  @override
  String get blindServerDescription =>
      'Máy chủ của chúng tôi không có kiến thức về dữ liệu của bạn. Chúng tôi chỉ nhìn thấy các khối dữ liệu đã mã hóa, đảm bảo quyền riêng tư tuyệt đối.';

  @override
  String get dontTrustVerifyTitle => 'Đừng chỉ tin, hãy tự kiểm chứng.';

  @override
  String get openSourceVerificationDescription =>
      'Mã nguồn mở 100%. Bạn có thể kiểm tra mã để biết chính xác cách các tập tin của mình được mã hóa.';

  @override
  String get getStarted => 'Bắt đầu';

  @override
  String get next => 'Tiếp theo';

  @override
  String get unauthorized => 'Không được phép';

  @override
  String get tryAgain => 'Thử lại';

  @override
  String get errorTitle => 'Lỗi';

  @override
  String get failureTitle => 'Thất bại';

  @override
  String get invalidWordList => 'Danh sách từ không hợp lệ';

  @override
  String get invalidAccessKey => 'Khóa truy cập không hợp lệ';

  @override
  String get unexpectedDecryptionError =>
      'Đã xảy ra lỗi không mong muốn trong quá trình giải mã.';

  @override
  String get fileMustContainExactly24Words => 'Tập tin phải chứa đúng 24 từ.';

  @override
  String get errorReadingFile => 'Lỗi khi đọc tập tin';

  @override
  String get encryptionTitle => 'Mã hóa';

  @override
  String get accessKeyDecodeDescription =>
      'Nhập cụm từ khôi phục gồm 24 từ hoặc tải tệp .txt để bật đồng bộ đám mây một cách an toàn.';

  @override
  String get recoveryPhraseLabel => 'Cụm từ khôi phục';

  @override
  String get recoveryPhraseHint => 'từ1 từ2 từ3...';

  @override
  String get paste => 'Dán';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 từ';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'Vui lòng nhập cụm từ khôi phục';

  @override
  String get mustContainExactly24Words => 'Phải chứa đúng 24 từ';

  @override
  String get verify => 'Xác minh';

  @override
  String get orLabel => 'HOẶC';

  @override
  String get loadFromTxtFile => 'Tải từ tệp .txt';

  @override
  String get saveAccessKey => 'Lưu khóa truy cập';

  @override
  String get fileSavedSuccessfully => 'Đã lưu tập tin thành công.';

  @override
  String get accessKeyShareMessage => 'Đây là khóa truy cập của bạn.';

  @override
  String get pleaseTryAgain => 'Vui lòng thử lại.';

  @override
  String get copiedToClipboard => 'Đã sao chép vào bảng tạm';

  @override
  String get accessKeyTitle => 'Khóa truy cập';

  @override
  String get accessKeyDescription =>
      'Vui lòng lưu khóa này ở nơi an toàn. Chỉ khóa này mới cho phép bạn truy cập dữ liệu đã mã hóa của mình.';

  @override
  String get copy => 'Sao chép';

  @override
  String get downloadAsTextFile => 'Tải xuống dưới dạng tệp văn bản';

  @override
  String get continueLabel => 'Tiếp tục';

  @override
  String get importantTitle => 'Quan trọng';

  @override
  String get accessKeyNoticePrimary =>
      'Ở trang tiếp theo, bạn sẽ thấy một chuỗi gồm 24 từ. Đây là khóa mã hóa riêng tư và duy nhất của bạn, đồng thời là CÁCH DUY NHẤT để khôi phục dữ liệu nếu bạn đăng xuất, mất thiết bị hoặc thiết bị gặp sự cố.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Chúng tôi không lưu trữ khóa này. Bạn có trách nhiệm lưu nó ở nơi an toàn bên ngoài ứng dụng $appName.';
  }

  @override
  String get showKeyConfirmation => 'Tôi đã hiểu.\nHiển thị khóa.';

  @override
  String get storageAddedSuccessfully => 'Đã thêm lưu trữ thành công';

  @override
  String get networkErrorDuringValidation =>
      'Đã xảy ra lỗi mạng trong quá trình xác thực.';

  @override
  String get verifyAndConnect => 'Xác minh & Kết nối';

  @override
  String get requiredField => 'Bắt buộc';

  @override
  String get providerKeysVerifiedLocally =>
      'Khóa của bạn được xác minh cục bộ và mã hóa trước khi truyền đi.';

  @override
  String get enterYourCredentials => 'Nhập thông tin đăng nhập của bạn';

  @override
  String connectProvider(String provider) {
    return 'Kết nối $provider';
  }

  @override
  String get deviceLimitReached => 'Đã đạt giới hạn thiết bị';

  @override
  String get pleaseTryAgainWithExclamation => 'Vui lòng thử lại!';

  @override
  String get notThisDevice => 'Không phải thiết bị này!';

  @override
  String get confirmSignoutDeviceTitle => 'Xác nhận đăng xuất thiết bị';

  @override
  String get areYouSure => 'Bạn có chắc không?';

  @override
  String get cancel => 'Hủy';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Không tìm thấy thiết bị nào';

  @override
  String get backTooltip => 'Quay lại';

  @override
  String get devicesTitle => 'Thiết bị';

  @override
  String get longPressToDownload => 'Nhấn giữ để tải xuống';

  @override
  String get fewItemsExistLocally =>
      'Một số mục vẫn còn tồn tại trên thiết bị.';

  @override
  String selectedItemsCount(int count) {
    return 'Đã chọn $count';
  }

  @override
  String get delete => 'Xóa';

  @override
  String get info => 'Thông tin';

  @override
  String get download => 'Tải xuống';

  @override
  String get archive => 'Lưu trữ';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Nhật ký';

  @override
  String get settings => 'Cài đặt';

  @override
  String get trash => 'Thùng rác';

  @override
  String get storage => 'Lưu trữ';

  @override
  String get search => 'Tìm kiếm';

  @override
  String get database => 'Cơ sở dữ liệu';

  @override
  String get addFolderTitle => 'Thêm thư mục';

  @override
  String get confirm => 'Xác nhận';

  @override
  String get tapPlusToAddSyncFolder => 'Chạm vào + để thêm thư mục đồng bộ.';

  @override
  String get thisFolderIsEmpty => 'Thư mục này đang trống.';

  @override
  String get fileNotFound => 'Không tìm thấy tập tin';

  @override
  String filePartsTitle(int count) {
    return 'Các phần của tập tin ($count)';
  }

  @override
  String get fileDetailsTitle => 'Chi tiết tập tin';

  @override
  String get encryptedBackup => 'Bản sao lưu đã mã hóa';

  @override
  String get sizeLabel => 'Kích thước';

  @override
  String get providerLabel => 'Nhà cung cấp';

  @override
  String get uploadedAtLabel => 'Thời gian tải lên';

  @override
  String get statusLabel => 'Trạng thái';

  @override
  String get uploadedStatus => 'Đã tải lên';

  @override
  String errorWithMessage(String message) {
    return 'Lỗi: $message';
  }

  @override
  String get noLogsAvailable => 'Không có nhật ký';

  @override
  String get searchLogsHint => 'Tìm kiếm nhật ký...';

  @override
  String get clearLogs => 'Xóa nhật ký';

  @override
  String get searchWithMinThreeCharacters => 'Tìm kiếm với tối thiểu 3 ký tự';

  @override
  String get typeBelowToSearch => 'Nhập bên dưới để tìm kiếm';

  @override
  String get noResults => 'Không có kết quả.';

  @override
  String get welcomeTitle => 'Chào mừng';

  @override
  String signInToContinue(String appName) {
    return 'Đăng nhập để tiếp tục đến $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Vui lòng nhập email của bạn';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Vui lòng nhập địa chỉ email hợp lệ';

  @override
  String get emailAddressLabel => 'Địa chỉ email';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'Gửi lại OTP';

  @override
  String get sendOtp => 'Gửi OTP';

  @override
  String get checkYourEmail => 'Kiểm tra email của bạn';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Chúng tôi đã gửi mã 6 chữ số đến\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Vui lòng nhập OTP';

  @override
  String get otpMustBeSixDigits => 'OTP phải gồm 6 chữ số';

  @override
  String get enterOtpLabel => 'Nhập OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Thử xác minh lại';

  @override
  String get verifyOtp => 'Xác minh OTP';

  @override
  String get useDifferentEmail => 'Dùng email khác';

  @override
  String get alreadySignedIn => 'Đã đăng nhập';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Gửi OTP thất bại. Vui lòng thử lại!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Xác minh OTP thất bại. Vui lòng thử lại.';

  @override
  String get dbViewerTitle => 'Trình xem CSDL';

  @override
  String get selectTableToViewData =>
      'Chọn một bảng để xem dữ liệu của bảng đó';

  @override
  String get selectTable => 'Chọn bảng';

  @override
  String get permissionRequiredTitle => 'Yêu cầu quyền truy cập';

  @override
  String get storagePermissionSettingsDescription =>
      'Để tự động sao lưu, quản lý và bảo vệ tập tin của bạn trong nền, chúng tôi cần quyền truy cập vào bộ nhớ thiết bị. Dữ liệu của bạn được mã hóa cục bộ để đảm bảo quyền riêng tư tuyệt đối. Vui lòng cho phép truy cập để tiếp tục.';

  @override
  String get openSettings => 'Mở cài đặt';

  @override
  String get secureLocalAccessTitle => 'Truy cập cục bộ an toàn';

  @override
  String get storagePermissionPageDescription =>
      'Để duyệt, mã hóa và tự động sao lưu tập tin, chúng tôi cần quyền truy cập vào bộ nhớ thiết bị của bạn.';

  @override
  String get verifying => 'Đang xác minh...';

  @override
  String get grantAccess => 'Cấp quyền truy cập';

  @override
  String get zeroKnowledgeEncryptedStorage => 'Lưu trữ mã hóa zero-knowledge';

  @override
  String get notificationPermissionTitle => 'Truy cập Thông báo';

  @override
  String get notificationPermissionPageDescription =>
      'Để giữ cho các tập tin của bạn luôn được đồng bộ và cung cấp cập nhật trạng thái theo thời gian thực trong nền, chúng tôi cần quyền hiển thị thông báo.';

  @override
  String get notificationPermissionGrantButton => 'Cho phép Thông báo';

  @override
  String get notificationPermissionSettingsDescription =>
      'Thông báo là cần thiết để theo dõi quá trình đồng bộ hóa trong nền. Vui lòng bật chúng trong cài đặt hệ thống để đảm bảo dữ liệu của bạn luôn được cập nhật.';

  @override
  String requiresAppPro(String appName) {
    return 'Yêu cầu $appName Pro.';
  }

  @override
  String get noStorageFound => 'Không tìm thấy bộ nhớ lưu trữ';

  @override
  String get howToConnect => 'Cách kết nối';

  @override
  String get modify => 'Chỉnh sửa';

  @override
  String storageUsed(String used, String total) {
    return 'Đã dùng $used / $total';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Miễn phí tối đa $size';
  }

  @override
  String get notConnected => 'Chưa kết nối';

  @override
  String get connect => 'Kết nối';

  @override
  String get modifyStorageCapacityTitle => 'Thay đổi dung lượng lưu trữ';

  @override
  String get enterNewStorageLimitForProvider =>
      'Nhập giới hạn dung lượng mới cho nhà cung cấp này.';

  @override
  String get sizePrefix => 'Kích thước: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Vui lòng nhập kích thước';

  @override
  String get enterValidNumberGreaterThanOne => 'Nhập số hợp lệ lớn hơn 1';

  @override
  String get submit => 'Gửi';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Đã đăng ký $appName Pro thành công!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Giao dịch đã bị hủy hoặc thất bại.';

  @override
  String get purchasesRestoredSuccessfully =>
      'Đã khôi phục giao dịch thành công!';

  @override
  String get noActiveSubscriptionsFound =>
      'Không tìm thấy gói đăng ký đang hoạt động.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Vui lòng quản lý gói đăng ký trong phần cài đặt thiết bị.';

  @override
  String get freePlanTitle => 'Miễn phí';

  @override
  String get freeForeverPrice => '\$0.00 / mãi mãi';

  @override
  String get freeBenefitProviderStorage =>
      'Sử dụng dung lượng miễn phí từ các nhà cung cấp';

  @override
  String get freeBenefitSyncThreeDevices => 'Đồng bộ bảo mật tối đa 3 thiết bị';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Hàng năm';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Thay đổi giới hạn dung lượng cho từng nhà cung cấp';

  @override
  String get proBenefitSyncTenDevices => 'Đồng bộ tối đa 10 thiết bị';

  @override
  String get restorePurchases => 'Khôi phục giao dịch';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Gói đăng ký được liên kết với tài khoản email, không phải thiết bị';

  @override
  String get subscriptionExpiredTitle => 'Gói đăng ký đã hết hạn';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Các quyền lợi $appName Pro của bạn đã tạm dừng. Hãy gia hạn bên dưới để khôi phục giới hạn lưu trữ và đồng bộ thiết bị.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro đang hoạt động';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Thay đổi giới hạn dung lượng cho từng nhà cung cấp\n✓ Đồng bộ chéo tối đa 10 thiết bị';

  @override
  String get manageSubscription => 'Quản lý gói đăng ký';

  @override
  String get currentPlanBadge => 'HIỆN TẠI';

  @override
  String get subscribeNow => 'Đăng ký ngay';

  @override
  String get subscribeOnMobileApp => 'Đăng ký trên ứng dụng di động';

  @override
  String get recover => 'Khôi phục';

  @override
  String get empty => 'Làm trống';

  @override
  String get noItems => 'Không có mục nào.';
}
