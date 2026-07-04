// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Indonesian (`id`).
class AppLocalizationsId extends AppLocalizations {
  AppLocalizationsId([String locale = 'id']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Dengan melanjutkan, Anda menyetujui $terms dan $privacy kami.';
  }

  @override
  String get termsOfService => 'Ketentuan Layanan';

  @override
  String get privacyPolicy => 'Kebijakan Privasi';

  @override
  String get andLabel => ' dan ';

  @override
  String get theme => 'Tema';

  @override
  String get themeTooltip => 'Tema siang/malam';

  @override
  String get logging => 'Log';

  @override
  String get quickSyncNotificationSettingTitle =>
      'Notifikasi sinkronisasi cepat';

  @override
  String get quickSyncNotificationTitle => 'Layanan sinkronisasi file';

  @override
  String get quickSyncNotificationText =>
      'Ketuk tombol di bawah untuk sinkronisasi';

  @override
  String get quickSyncNotificationButton => 'Sinkronkan sekarang';

  @override
  String get quickSyncNotificationInProgress => 'Sedang diproses...';

  @override
  String get reportIssue => 'Laporkan Masalah';

  @override
  String get sourceCode => 'Kode Sumber';

  @override
  String get desktopApp => 'Aplikasi Desktop';

  @override
  String get mobileApp => 'Aplikasi Seluler';

  @override
  String get leaveReview => 'Beri ulasan';

  @override
  String get share => 'Bagikan';

  @override
  String get versionLabel => 'Versi: ';

  @override
  String get loading => 'Memuat...';

  @override
  String get signOut => 'Keluar';

  @override
  String get settingsPageTitle => 'Pengaturan';

  @override
  String get language => 'Bahasa';

  @override
  String get tapToSelect => 'Ketuk untuk memilih';

  @override
  String get appTagline => 'Pengangkut File Pribadi Anda';

  @override
  String get onboardingPurposeDescription =>
      'Layanan penyimpanan cloud open-source yang dibangun dengan arsitektur zero-trust. Data Anda dienkripsi secara lokal sebelum meninggalkan perangkat.';

  @override
  String get failedToFetch => 'Gagal memuat.';

  @override
  String get supportedStorageTitle => 'Penyimpanan yang Didukung';

  @override
  String get supportedStorageDescription =>
      'Hubungkan penyedia favorit Anda. Mulai sekarang dengan 1 GB penyimpanan aman gratis bawaan FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Mulai backup sekarang';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Gratis';

  @override
  String get providerStorageDisclaimer =>
      '* Penyimpanan gratis sesuai yang tercantum di situs penyedia. Bayar sesuai pemakaian untuk penyedia yang kompatibel.';

  @override
  String get whyUseFifeTitle => 'Kenapa Pakai FiFe?';

  @override
  String get claimFreeCloudStorageTitle => 'Dapatkan Penyimpanan Cloud Gratis';

  @override
  String get claimFreeCloudStorageDescription =>
      'Maksimalkan ruang Anda dengan menghubungkan beberapa penyedia cloud. Nikmati paket penyimpanan gratis mereka dengan aman dalam satu aplikasi terpadu.';

  @override
  String get topNotchSecurityTitle => 'Keamanan Terbaik';

  @override
  String get topNotchSecurityDescription =>
      'Didukung kriptografi Sodium tingkat lanjut. Semua proses enkripsi dan dekripsi dilakukan sepenuhnya secara lokal di perangkat Anda.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Pertahankan kendali penuh atas data Anda di semua penyedia penyimpanan cloud. Gunakan penyimpanan terenkripsi dengan akun Anda sendiri.';

  @override
  String get payAsYouGoStorageTitle =>
      'Bayar sesuai pemakaian untuk penyimpanan.';

  @override
  String get payAsYouGoStorageDescription =>
      'Bayar hanya untuk penyimpanan yang digunakan pada penyedia yang kompatibel. Tanpa perantara, tanpa mengunci data Anda.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Privasi Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Data Anda dikunci di perangkat sebelum dikirim. Kami tidak dapat melihat, membaca, atau memindai file Anda.';

  @override
  String get localSelectionTitle => '1. Pilih Secara Lokal';

  @override
  String get localSelectionDescription =>
      'Anda memilih folder. Semua proses dimulai secara aman di perangkat lokal Anda.';

  @override
  String get metadataEncryptionTitle => '2. Enkripsi Metadata';

  @override
  String get metadataEncryptionDescription =>
      'Informasi file (nama, jenis, dan ukuran) dienkripsi sebelum dikirim ke server.';

  @override
  String get contentEncryptionTitle => '3. Enkripsi Konten';

  @override
  String get contentEncryptionDescription =>
      'Isi file akan dipecah dan dienkripsi sebelum diunggah ke penyimpanan cloud.';

  @override
  String get blindServerTitle => '4. Server Buta';

  @override
  String get blindServerDescription =>
      'Server kami tidak memiliki pengetahuan tentang data Anda. Kami hanya melihat data terenkripsi, sehingga privasi Anda tetap terjaga.';

  @override
  String get dontTrustVerifyTitle => 'Jangan hanya percaya, periksa sendiri.';

  @override
  String get openSourceVerificationDescription =>
      '100% open source. Anda bisa memeriksa kode untuk melihat bagaimana file Anda dienkripsi.';

  @override
  String get getStarted => 'Mulai';

  @override
  String get next => 'Berikutnya';

  @override
  String get unauthorized => 'Tidak diizinkan';

  @override
  String get tryAgain => 'Coba Lagi';

  @override
  String get errorTitle => 'Error';

  @override
  String get failureTitle => 'Gagal';

  @override
  String get invalidWordList => 'Daftar kata tidak valid';

  @override
  String get invalidAccessKey => 'Kunci akses tidak valid';

  @override
  String get unexpectedDecryptionError =>
      'Terjadi kesalahan tak terduga saat dekripsi.';

  @override
  String get fileMustContainExactly24Words =>
      'File harus berisi tepat 24 kata.';

  @override
  String get errorReadingFile => 'Gagal membaca file';

  @override
  String get encryptionTitle => 'Enkripsi';

  @override
  String get accessKeyDecodeDescription =>
      'Masukkan frasa pemulihan 24 kata Anda atau muat file .txt untuk mengaktifkan sinkronisasi cloud dengan aman.';

  @override
  String get recoveryPhraseLabel => 'Frasa Pemulihan';

  @override
  String get recoveryPhraseHint => 'kata1 kata2 kata3...';

  @override
  String get paste => 'Tempel';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 kata';
  }

  @override
  String get pleaseEnterRecoveryPhrase =>
      'Silakan masukkan frasa pemulihan Anda';

  @override
  String get mustContainExactly24Words => 'Harus berisi tepat 24 kata';

  @override
  String get verify => 'Verifikasi';

  @override
  String get orLabel => 'ATAU';

  @override
  String get loadFromTxtFile => 'Muat dari File .txt';

  @override
  String get saveAccessKey => 'Simpan Kunci Akses';

  @override
  String get fileSavedSuccessfully => 'File berhasil disimpan.';

  @override
  String get accessKeyShareMessage => 'Berikut kunci akses Anda.';

  @override
  String get pleaseTryAgain => 'Silakan coba lagi.';

  @override
  String get copiedToClipboard => 'Disalin ke clipboard';

  @override
  String get accessKeyTitle => 'Kunci Akses';

  @override
  String get accessKeyDescription =>
      'Simpan kunci ini di tempat yang aman. Hanya kunci ini yang dapat memberi Anda akses ke data terenkripsi.';

  @override
  String get copy => 'Salin';

  @override
  String get downloadAsTextFile => 'Unduh sebagai File Teks';

  @override
  String get continueLabel => 'Lanjutkan';

  @override
  String get importantTitle => 'Penting';

  @override
  String get accessKeyNoticePrimary =>
      'Di halaman berikutnya Anda akan melihat rangkaian 24 kata. Ini adalah kunci enkripsi pribadi dan unik Anda, serta SATU-SATUNYA cara untuk memulihkan data jika Anda logout, kehilangan perangkat, atau perangkat mengalami kerusakan.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Kami tidak menyimpan kunci ini. Menyimpannya di tempat aman di luar aplikasi $appName sepenuhnya menjadi tanggung jawab Anda.';
  }

  @override
  String get showKeyConfirmation => 'Saya mengerti.\nTampilkan kuncinya.';

  @override
  String get storageAddedSuccessfully => 'Penyimpanan berhasil ditambahkan';

  @override
  String get networkErrorDuringValidation =>
      'Terjadi kesalahan jaringan saat validasi.';

  @override
  String get verifyAndConnect => 'Verifikasi & Hubungkan';

  @override
  String get requiredField => 'Wajib diisi';

  @override
  String get providerKeysVerifiedLocally =>
      'Kunci Anda diverifikasi secara lokal dan dienkripsi sebelum dikirim.';

  @override
  String get enterYourCredentials => 'Masukkan kredensial Anda';

  @override
  String connectProvider(String provider) {
    return 'Hubungkan $provider';
  }

  @override
  String get deviceLimitReached => 'Batas perangkat tercapai';

  @override
  String get pleaseTryAgainWithExclamation => 'Silakan coba lagi!';

  @override
  String get notThisDevice => 'Bukan perangkat ini!';

  @override
  String get confirmSignoutDeviceTitle => 'Konfirmasi keluar dari perangkat';

  @override
  String get areYouSure => 'Yakin?';

  @override
  String get cancel => 'Batal';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Tidak ada perangkat';

  @override
  String get backTooltip => 'Kembali';

  @override
  String get devicesTitle => 'Perangkat';

  @override
  String get longPressToDownload => 'Tekan lama untuk mengunduh';

  @override
  String get fewItemsExistLocally => 'Beberapa item masih ada secara lokal.';

  @override
  String selectedItemsCount(int count) {
    return '$count Dipilih';
  }

  @override
  String get delete => 'Hapus';

  @override
  String get info => 'Info';

  @override
  String get download => 'Unduh';

  @override
  String get archive => 'Arsipkan';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Log';

  @override
  String get settings => 'Pengaturan';

  @override
  String get trash => 'Sampah';

  @override
  String get storage => 'Penyimpanan';

  @override
  String get search => 'Cari';

  @override
  String get database => 'Database';

  @override
  String get addFolderTitle => 'Tambah folder';

  @override
  String get confirm => 'Konfirmasi';

  @override
  String get tapPlusToAddSyncFolder =>
      'Ketuk + untuk menambahkan folder sinkronisasi.';

  @override
  String get thisFolderIsEmpty => 'Folder ini kosong.';

  @override
  String get fileNotFound => 'File tidak ditemukan';

  @override
  String filePartsTitle(int count) {
    return 'Bagian File ($count)';
  }

  @override
  String get fileDetailsTitle => 'Detail File';

  @override
  String get encryptedBackup => 'Cadangan Terenkripsi';

  @override
  String get sizeLabel => 'Ukuran';

  @override
  String get providerLabel => 'Penyedia';

  @override
  String get uploadedAtLabel => 'Diunggah Pada';

  @override
  String get statusLabel => 'Status';

  @override
  String get uploadedStatus => 'Diunggah';

  @override
  String errorWithMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get noLogsAvailable => 'Tidak ada log';

  @override
  String get searchLogsHint => 'Cari log...';

  @override
  String get clearLogs => 'Hapus log';

  @override
  String get searchWithMinThreeCharacters => 'Cari dengan minimal 3 karakter';

  @override
  String get typeBelowToSearch => 'Ketik di bawah untuk mencari';

  @override
  String get noResults => 'Tidak ada hasil.';

  @override
  String get welcomeTitle => 'Selamat Datang';

  @override
  String signInToContinue(String appName) {
    return 'Masuk untuk melanjutkan ke $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Silakan masukkan email Anda';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Silakan masukkan alamat email yang valid';

  @override
  String get emailAddressLabel => 'Alamat Email';

  @override
  String get emailAddressHint => 'email.anda@contoh.com';

  @override
  String get retrySendingOtp => 'Kirim Ulang OTP';

  @override
  String get sendOtp => 'Kirim OTP';

  @override
  String get checkYourEmail => 'Periksa email Anda';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Kami telah mengirim kode 6 digit ke\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Silakan masukkan OTP';

  @override
  String get otpMustBeSixDigits => 'OTP harus terdiri dari 6 digit';

  @override
  String get enterOtpLabel => 'Masukkan OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Coba Verifikasi Lagi';

  @override
  String get verifyOtp => 'Verifikasi OTP';

  @override
  String get useDifferentEmail => 'Gunakan email lain';

  @override
  String get alreadySignedIn => 'Sudah Masuk';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Gagal mengirim OTP. Silakan coba lagi!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Verifikasi OTP gagal. Silakan coba lagi.';

  @override
  String get dbViewerTitle => 'Penampil DB';

  @override
  String get selectTableToViewData => 'Pilih tabel untuk melihat datanya';

  @override
  String get selectTable => 'Pilih tabel';

  @override
  String get permissionRequiredTitle => 'Izin Diperlukan';

  @override
  String get storagePermissionSettingsDescription =>
      'Agar dapat mencadangkan, mengelola, dan mengamankan file Anda secara otomatis di latar belakang, kami memerlukan akses ke penyimpanan perangkat. Data Anda dienkripsi secara lokal sehingga privasi tetap terjaga. Silakan izinkan akses untuk melanjutkan.';

  @override
  String get openSettings => 'Buka Pengaturan';

  @override
  String get secureLocalAccessTitle => 'Akses Lokal Aman';

  @override
  String get storagePermissionPageDescription =>
      'Agar dapat menelusuri, mengenkripsi, dan mencadangkan file Anda secara otomatis, kami memerlukan akses ke penyimpanan perangkat.';

  @override
  String get verifying => 'Memverifikasi...';

  @override
  String get grantAccess => 'Berikan Akses';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Penyimpanan terenkripsi zero-knowledge';

  @override
  String get notificationPermissionTitle => 'Akses Notifikasi';

  @override
  String get notificationPermissionPageDescription =>
      'Untuk menjaga file Anda tetap sinkron dan memberikan pembaruan status waktu nyata di latar belakang, kami memerlukan izin untuk menampilkan notifikasi.';

  @override
  String get notificationPermissionGrantButton => 'Izinkan Notifikasi';

  @override
  String get notificationPermissionSettingsDescription =>
      'Notifikasi diperlukan untuk memantau sinkronisasi latar belakang. Silakan aktifkan di pengaturan sistem untuk memastikan data Anda selalu mutakhir.';

  @override
  String requiresAppPro(String appName) {
    return 'Memerlukan $appName Pro.';
  }

  @override
  String get noStorageFound => 'Tidak ada penyimpanan';

  @override
  String get howToConnect => 'Cara menghubungkan';

  @override
  String get modify => 'Ubah';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total Terpakai';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Gratis hingga $size';
  }

  @override
  String get notConnected => 'Belum terhubung';

  @override
  String get connect => 'Hubungkan';

  @override
  String get modifyStorageCapacityTitle => 'Ubah Kapasitas Penyimpanan';

  @override
  String get enterNewStorageLimitForProvider =>
      'Masukkan batas penyimpanan baru untuk penyedia ini.';

  @override
  String get sizePrefix => 'Ukuran: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Silakan masukkan ukuran';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Masukkan angka valid yang lebih besar dari 1';

  @override
  String get submit => 'Kirim';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Berhasil berlangganan $appName Pro!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Pembelian dibatalkan atau gagal.';

  @override
  String get purchasesRestoredSuccessfully => 'Pembelian berhasil dipulihkan!';

  @override
  String get noActiveSubscriptionsFound => 'Tidak ada langganan aktif.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Silakan kelola langganan di pengaturan perangkat Anda.';

  @override
  String get freePlanTitle => 'Gratis';

  @override
  String get freeForeverPrice => '\$0.00 / selamanya';

  @override
  String get freeBenefitProviderStorage =>
      'Nikmati penyimpanan gratis dari penyedia';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Sinkronkan hingga 3 perangkat dengan aman';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Tahunan';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Ubah batas penyimpanan untuk tiap penyedia';

  @override
  String get proBenefitSyncTenDevices => 'Sinkronkan hingga 10 perangkat';

  @override
  String get restorePurchases => 'Pulihkan Pembelian';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Langganan terkait dengan akun email, bukan perangkat';

  @override
  String get subscriptionExpiredTitle => 'Langganan Berakhir';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Manfaat $appName Pro Anda sedang dijeda. Perpanjang di bawah untuk memulihkan batas penyimpanan dan sinkronisasi perangkat.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro Aktif';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Ubah batas penyimpanan untuk tiap penyedia\n✓ Sinkron lintas perangkat hingga 10 perangkat';

  @override
  String get manageSubscription => 'Kelola Langganan';

  @override
  String get currentPlanBadge => 'SAAT INI';

  @override
  String get subscribeNow => 'Langganan Sekarang';

  @override
  String get subscribeOnMobileApp => 'Berlangganan di aplikasi seluler';

  @override
  String get recover => 'Pulihkan';

  @override
  String get empty => 'Kosongkan';

  @override
  String get noItems => 'Tidak ada item.';
}
