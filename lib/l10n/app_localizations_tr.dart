// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Devam ederek $terms ve $privacy koşullarımızı kabul etmiş olursunuz.';
  }

  @override
  String get termsOfService => 'Hizmet Şartları';

  @override
  String get privacyPolicy => 'Gizlilik Politikası';

  @override
  String get andLabel => ' ve ';

  @override
  String get theme => 'Tema';

  @override
  String get themeTooltip => 'Aydınlık/karanlık tema';

  @override
  String get logging => 'Günlükleme';

  @override
  String get reportIssue => 'Sorun bildir';

  @override
  String get sourceCode => 'Kaynak kod';

  @override
  String get desktopApp => 'Masaüstü uygulaması';

  @override
  String get mobileApp => 'Mobil uygulama';

  @override
  String get leaveReview => 'Yorum bırak';

  @override
  String get share => 'Paylaş';

  @override
  String get versionLabel => 'Sürüm: ';

  @override
  String get loading => 'Yükleniyor...';

  @override
  String get signOut => 'Çıkış yap';

  @override
  String get settingsPageTitle => 'Ayarlar';

  @override
  String get language => 'Dil';

  @override
  String get tapToSelect => 'Seçmek için dokunun';

  @override
  String get appTagline => 'Özel Dosya Taşıyıcınız';

  @override
  String get onboardingPurposeDescription =>
      'Zero-trust mimarisiyle oluşturulmuş açık kaynaklı bir bulut depolama hizmeti. Verileriniz cihazınızdan çıkmadan önce yerel olarak şifrelenir.';

  @override
  String get failedToFetch => 'Alınamadı.';

  @override
  String get supportedStorageTitle => 'Desteklenen Depolama';

  @override
  String get supportedStorageDescription =>
      'Sevdiğiniz sağlayıcıları bağlayın. FiFe\'in yerleşik 1 GB ücretsiz güvenli depolamasıyla hemen başlayın.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Anında yedeklemeye başlayın';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Ücretsiz';

  @override
  String get providerStorageDisclaimer =>
      '* Ücretsiz depolama miktarı sağlayıcının web sitesinde belirtilene göredir. Uyumlu sağlayıcılarda kullandıkça öde modeli geçerlidir.';

  @override
  String get whyUseFifeTitle => 'Neden FiFe?';

  @override
  String get claimFreeCloudStorageTitle =>
      'Ücretsiz Bulut Depolamadan Yararlanın';

  @override
  String get claimFreeCloudStorageDescription =>
      'Birden fazla bulut sağlayıcısını bağlayarak alanınızı en verimli şekilde kullanın. Ücretsiz depolama kotalarından tek bir uygulamada güvenle yararlanın.';

  @override
  String get topNotchSecurityTitle => 'Üst Düzey Güvenlik';

  @override
  String get topNotchSecurityDescription =>
      'Gelişmiş Sodium kriptografisiyle güçlendirilmiştir. Tüm şifreleme ve çözme işlemleri tamamen cihazınızda gerçekleşir.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Tüm bulut depolama sağlayıcılarında verileriniz üzerinde tam kontrol sahibi olun. Kendi hesaplarınızla şifreli depolamayı kullanın.';

  @override
  String get payAsYouGoStorageTitle =>
      'Yalnızca kullandığınız depolama için ödeme yapın.';

  @override
  String get payAsYouGoStorageDescription =>
      'Uyumlu sağlayıcılarda yalnızca kullandığınız kadar ödeme yapın. Aracı yok, veri kilidi yok.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Zero-Knowledge Gizliliği';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Verileriniz cihazınızdan çıkmadan önce kilitlenir. Dosyalarınızı göremeyiz, okuyamayız veya tarayamayız.';

  @override
  String get localSelectionTitle => '1. Yerel Seçim';

  @override
  String get localSelectionDescription =>
      'Bir klasör seçersiniz. Tüm işlemler güvenli şekilde cihazınızda başlar.';

  @override
  String get metadataEncryptionTitle => '2. Meta Verilerin Şifrelenmesi';

  @override
  String get metadataEncryptionDescription =>
      'Dosya bilgileri (adlar, türler ve boyutlar) sunucuya gönderilmeden önce şifrelenir.';

  @override
  String get contentEncryptionTitle => '3. İçeriğin Şifrelenmesi';

  @override
  String get contentEncryptionDescription =>
      'Gerçek dosya içeriği, bulut depolamaya yüklenmeden önce parçalara ayrılır ve şifrelenir.';

  @override
  String get blindServerTitle => '4. Görmeyen Sunucu';

  @override
  String get blindServerDescription =>
      'Sunucularımız verileriniz hakkında hiçbir bilgiye sahip değildir. Yalnızca şifrelenmiş veri bloklarını görür, böylece tam gizlilik sağlanır.';

  @override
  String get dontTrustVerifyTitle => 'Körü körüne güvenmeyin, doğrulayın.';

  @override
  String get openSourceVerificationDescription =>
      '%100 açık kaynak. Dosyalarınızın nasıl şifrelendiğini görmek için kodu inceleyebilirsiniz.';

  @override
  String get getStarted => 'Başlayın';

  @override
  String get next => 'İleri';

  @override
  String get unauthorized => 'Yetkisiz';

  @override
  String get tryAgain => 'Tekrar dene';

  @override
  String get errorTitle => 'Hata';

  @override
  String get failureTitle => 'Başarısız';

  @override
  String get invalidWordList => 'Geçersiz kelime listesi';

  @override
  String get invalidAccessKey => 'Geçersiz erişim anahtarı';

  @override
  String get unexpectedDecryptionError =>
      'Şifre çözme sırasında beklenmeyen bir hata oluştu.';

  @override
  String get fileMustContainExactly24Words =>
      'Dosya tam olarak 24 kelime içermelidir.';

  @override
  String get errorReadingFile => 'Dosya okunurken hata oluştu';

  @override
  String get encryptionTitle => 'Şifreleme';

  @override
  String get accessKeyDecodeDescription =>
      'Bulut eşitlemesini güvenli şekilde etkinleştirmek için 24 kelimelik kurtarma ifadenizi girin veya bir .txt dosyası yükleyin.';

  @override
  String get recoveryPhraseLabel => 'Kurtarma ifadesi';

  @override
  String get recoveryPhraseHint => 'kelime1 kelime2 kelime3...';

  @override
  String get paste => 'Yapıştır';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 kelime';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'Lütfen kurtarma ifadenizi girin';

  @override
  String get mustContainExactly24Words => 'Tam olarak 24 kelime içermelidir';

  @override
  String get verify => 'Doğrula';

  @override
  String get orLabel => 'VEYA';

  @override
  String get loadFromTxtFile => '.txt dosyasından yükle';

  @override
  String get saveAccessKey => 'Erişim anahtarını kaydet';

  @override
  String get fileSavedSuccessfully => 'Dosya başarıyla kaydedildi.';

  @override
  String get accessKeyShareMessage => 'Erişim anahtarınız burada.';

  @override
  String get pleaseTryAgain => 'Lütfen tekrar deneyin.';

  @override
  String get copiedToClipboard => 'Panoya kopyalandı';

  @override
  String get accessKeyTitle => 'Erişim Anahtarı';

  @override
  String get accessKeyDescription =>
      'Lütfen bu anahtarı güvenli bir yerde saklayın. Şifrelenmiş verilerinize yalnızca bununla erişebilirsiniz.';

  @override
  String get copy => 'Kopyala';

  @override
  String get downloadAsTextFile => 'Metin dosyası olarak indir';

  @override
  String get continueLabel => 'Devam et';

  @override
  String get importantTitle => 'Önemli';

  @override
  String get accessKeyNoticePrimary =>
      'Sonraki sayfada 24 kelimeden oluşan bir dizi göreceksiniz. Bu, size özel ve gizli şifreleme anahtarınızdır ve çıkış yapmanız, cihazınızı kaybetmeniz veya arıza yaşanması durumunda verilerinizi kurtarmanın TEK yoludur.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Bu anahtarı biz saklamıyoruz. Onu $appName uygulaması dışında güvenli bir yerde saklamak sizin sorumluluğunuzdadır.';
  }

  @override
  String get showKeyConfirmation => 'Anladım.\nAnahtarı göster.';

  @override
  String get storageAddedSuccessfully => 'Depolama başarıyla eklendi';

  @override
  String get networkErrorDuringValidation =>
      'Doğrulama sırasında ağ hatası oluştu.';

  @override
  String get verifyAndConnect => 'Doğrula ve bağlan';

  @override
  String get requiredField => 'Zorunlu';

  @override
  String get providerKeysVerifiedLocally =>
      'Anahtarlarınız yerel olarak doğrulanır ve gönderilmeden önce şifrelenir.';

  @override
  String get enterYourCredentials => 'Bilgilerinizi girin';

  @override
  String connectProvider(String provider) {
    return '$provider bağla';
  }

  @override
  String get deviceLimitReached => 'Cihaz sınırına ulaşıldı';

  @override
  String get pleaseTryAgainWithExclamation => 'Lütfen tekrar deneyin!';

  @override
  String get notThisDevice => 'Bu cihaz değil!';

  @override
  String get confirmSignoutDeviceTitle => 'Cihazdan çıkışı onayla';

  @override
  String get areYouSure => 'Emin misiniz?';

  @override
  String get cancel => 'İptal';

  @override
  String get ok => 'Tamam';

  @override
  String get noDeviceFound => 'Cihaz bulunamadı';

  @override
  String get backTooltip => 'Geri';

  @override
  String get devicesTitle => 'Cihazlar';

  @override
  String get longPressToDownload => 'İndirmek için uzun basın';

  @override
  String get fewItemsExistLocally => 'Bazı öğeler hâlâ yerel olarak mevcut.';

  @override
  String selectedItemsCount(int count) {
    return '$count seçildi';
  }

  @override
  String get delete => 'Sil';

  @override
  String get info => 'Bilgi';

  @override
  String get download => 'İndir';

  @override
  String get archive => 'Arşivle';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Günlükler';

  @override
  String get settings => 'Ayarlar';

  @override
  String get trash => 'Çöp Kutusu';

  @override
  String get storage => 'Depolama';

  @override
  String get search => 'Ara';

  @override
  String get database => 'Veritabanı';

  @override
  String get addFolderTitle => 'Klasör ekle';

  @override
  String get confirm => 'Onayla';

  @override
  String get tapPlusToAddSyncFolder =>
      'Eşitleme klasörü eklemek için + simgesine dokunun.';

  @override
  String get thisFolderIsEmpty => 'Bu klasör boş.';

  @override
  String get fileNotFound => 'Dosya bulunamadı';

  @override
  String filePartsTitle(int count) {
    return 'Dosya Parçaları ($count)';
  }

  @override
  String get fileDetailsTitle => 'Dosya Ayrıntıları';

  @override
  String get encryptedBackup => 'Şifreli Yedek';

  @override
  String get sizeLabel => 'Boyut';

  @override
  String get providerLabel => 'Sağlayıcı';

  @override
  String get uploadedAtLabel => 'Yüklenme Tarihi';

  @override
  String get statusLabel => 'Durum';

  @override
  String get uploadedStatus => 'Yüklendi';

  @override
  String errorWithMessage(String message) {
    return 'Hata: $message';
  }

  @override
  String get noLogsAvailable => 'Günlük yok';

  @override
  String get searchLogsHint => 'Günlüklerde ara...';

  @override
  String get clearLogs => 'Günlükleri temizle';

  @override
  String get searchWithMinThreeCharacters => 'En az 3 karakterle arama yapın';

  @override
  String get typeBelowToSearch => 'Aramak için aşağıya yazın';

  @override
  String get noResults => 'Sonuç yok.';

  @override
  String get welcomeTitle => 'Hoş geldiniz';

  @override
  String signInToContinue(String appName) {
    return '$appName uygulamasına devam etmek için giriş yapın';
  }

  @override
  String get pleaseEnterYourEmail => 'Lütfen e-posta adresinizi girin';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Lütfen geçerli bir e-posta adresi girin';

  @override
  String get emailAddressLabel => 'E-posta Adresi';

  @override
  String get emailAddressHint => 'eposta@ornek.com';

  @override
  String get retrySendingOtp => 'OTP\'yi Tekrar Gönder';

  @override
  String get sendOtp => 'OTP Gönder';

  @override
  String get checkYourEmail => 'E-postanızı kontrol edin';

  @override
  String sentSixDigitCodeTo(String email) {
    return '6 haneli kodu şu adrese gönderdik:\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Lütfen OTP\'yi girin';

  @override
  String get otpMustBeSixDigits => 'OTP 6 haneli olmalıdır';

  @override
  String get enterOtpLabel => 'OTP girin';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Doğrulamayı Tekrar Dene';

  @override
  String get verifyOtp => 'OTP\'yi Doğrula';

  @override
  String get useDifferentEmail => 'Farklı bir e-posta kullan';

  @override
  String get alreadySignedIn => 'Zaten Giriş Yapıldı';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'OTP gönderilemedi. Lütfen tekrar deneyin!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'OTP doğrulaması başarısız oldu. Lütfen tekrar deneyin.';

  @override
  String get dbViewerTitle => 'Veritabanı Görüntüleyici';

  @override
  String get selectTableToViewData =>
      'Verileri görüntülemek için bir tablo seçin';

  @override
  String get selectTable => 'Tablo seçin';

  @override
  String get permissionRequiredTitle => 'İzin Gerekli';

  @override
  String get storagePermissionSettingsDescription =>
      'Dosyalarınızı arka planda otomatik olarak yedeklemek, yönetmek ve korumak için cihaz depolamasına erişmemiz gerekiyor. Verileriniz yerel olarak şifrelenir ve tam gizlilik sağlanır. Devam etmek için lütfen erişim izni verin.';

  @override
  String get openSettings => 'Ayarları Aç';

  @override
  String get storagePermissionRequiredToContinue =>
      'Devam etmek için depolama izni gereklidir';

  @override
  String get secureLocalAccessTitle => 'Güvenli Yerel Erişim';

  @override
  String get storagePermissionPageDescription =>
      'Dosyalarınızı görüntülemek, şifrelemek ve otomatik olarak yedeklemek için cihaz depolamasına erişmemiz gerekiyor.';

  @override
  String get verifying => 'Doğrulanıyor...';

  @override
  String get grantAccess => 'Erişim Ver';

  @override
  String get zeroKnowledgeEncryptedStorage => 'Zero-knowledge şifreli depolama';

  @override
  String get notificationPermissionTitle => 'Bildirim Erişimi';

  @override
  String get notificationPermissionPageDescription =>
      'Dosyalarınızın senkronize kalmasını sağlamak ve arka planda gerçek zamanlı durum güncellemeleri sunmak için bildirimleri gösterme iznine ihtiyacımız var.';

  @override
  String get notificationPermissionGrantButton => 'Bildirimlere İzin Ver';

  @override
  String get notificationPermissionSettingsDescription =>
      'Arka plan senkronizasyonunu izlemek için bildirimler gereklidir. Verilerinizin her zaman güncel olduğundan emin olmak için lütfen sistem ayarlarından bildirimleri etkinleştirin.';

  @override
  String get notificationPermissionRequiredToContinue =>
      'Arka plan senkronizasyonu için bildirim izni gereklidir';

  @override
  String requiresAppPro(String appName) {
    return '$appName Pro gerektirir.';
  }

  @override
  String get noStorageFound => 'Depolama bulunamadı';

  @override
  String get howToConnect => 'Nasıl bağlanır';

  @override
  String get modify => 'Düzenle';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total kullanıldı';
  }

  @override
  String percentageLabel(String value) {
    return '%$value';
  }

  @override
  String upToFree(String size) {
    return '$size değerine kadar ücretsiz';
  }

  @override
  String get notConnected => 'Bağlı değil';

  @override
  String get connect => 'Bağlan';

  @override
  String get modifyStorageCapacityTitle => 'Depolama Kapasitesini Düzenle';

  @override
  String get enterNewStorageLimitForProvider =>
      'Bu sağlayıcı için yeni depolama sınırını girin.';

  @override
  String get sizePrefix => 'Boyut: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Lütfen bir boyut girin';

  @override
  String get enterValidNumberGreaterThanOne =>
      '1\'den büyük geçerli bir sayı girin';

  @override
  String get submit => 'Gönder';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return '$appName Pro aboneliği başarıyla başlatıldı!';
  }

  @override
  String get purchaseCancelledOrFailed =>
      'Satın alma iptal edildi veya başarısız oldu.';

  @override
  String get purchasesRestoredSuccessfully =>
      'Satın alımlar başarıyla geri yüklendi!';

  @override
  String get noActiveSubscriptionsFound => 'Etkin abonelik bulunamadı.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Lütfen aboneliklerinizi cihaz ayarlarından yönetin.';

  @override
  String get freePlanTitle => 'Ücretsiz';

  @override
  String get freeForeverPrice => '\$0.00 / sonsuza kadar';

  @override
  String get freeBenefitProviderStorage =>
      'Sağlayıcıların ücretsiz depolamasından yararlanın';

  @override
  String get freeBenefitSyncThreeDevices =>
      'En fazla 3 cihazı güvenli şekilde eşitleyin';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Yıllık';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Her sağlayıcı için depolama sınırını değiştirin';

  @override
  String get proBenefitSyncTenDevices => 'En fazla 10 cihazı eşitleyin';

  @override
  String get restorePurchases => 'Satın Alımları Geri Yükle';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Abonelik cihazla değil, e-posta hesabıyla ilişkilidir';

  @override
  String get subscriptionExpiredTitle => 'Abonelik Süresi Doldu';

  @override
  String subscriptionExpiredDescription(String appName) {
    return '$appName Pro avantajlarınız duraklatıldı. Depolama sınırlarınızı ve cihaz eşitlemelerinizi geri yüklemek için aşağıdan yenileyin.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro Etkin';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Her sağlayıcı için depolama sınırlarını değiştirin\n✓ En fazla 10 cihaz arasında çapraz eşitleme';

  @override
  String get manageSubscription => 'Aboneliği Yönet';

  @override
  String get currentPlanBadge => 'MEVCUT';

  @override
  String get subscribeNow => 'Hemen abone olun';

  @override
  String get subscribeOnMobileApp => 'Mobil uygulamada abone olun';

  @override
  String get recover => 'Geri yükle';

  @override
  String get empty => 'Boşalt';

  @override
  String get noItems => 'Öğe yok.';
}
