// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Продовжуючи, ви погоджуєтеся з нашими $terms та $privacy.';
  }

  @override
  String get termsOfService => 'Умови користування';

  @override
  String get privacyPolicy => 'Політика конфіденційності';

  @override
  String get andLabel => ' та ';

  @override
  String get theme => 'Тема';

  @override
  String get themeTooltip => 'Денна/нічна тема';

  @override
  String get logging => 'Журналювання';

  @override
  String get quickSyncNotificationSettingTitle =>
      'Сповіщення про швидку синхронізацію';

  @override
  String get quickSyncNotificationTitle => 'Сервіс синхронізації файлів';

  @override
  String get quickSyncNotificationText =>
      'Натисніть кнопку нижче, щоб синхронізувати';

  @override
  String get quickSyncNotificationButton => 'Синхронізувати зараз';

  @override
  String get quickSyncNotificationInProgress => 'Триває...';

  @override
  String get reportIssue => 'Повідомити про проблему';

  @override
  String get sourceCode => 'Вихідний код';

  @override
  String get desktopApp => 'Десктопний застосунок';

  @override
  String get mobileApp => 'Мобільний застосунок';

  @override
  String get leaveReview => 'Залишити відгук';

  @override
  String get share => 'Поділитися';

  @override
  String get versionLabel => 'Версія: ';

  @override
  String get loading => 'Завантаження...';

  @override
  String get signOut => 'Вийти';

  @override
  String get settingsPageTitle => 'Налаштування';

  @override
  String get language => 'Мова';

  @override
  String get tapToSelect => 'Натисніть, щоб вибрати';

  @override
  String get appTagline => 'Ваш приватний пором для файлів';

  @override
  String get onboardingPurposeDescription =>
      'Відкритий хмарний сервіс з архітектурою zero-trust. Ваші дані шифруються локально ще до того, як залишать ваш пристрій.';

  @override
  String get failedToFetch => 'Не вдалося завантажити.';

  @override
  String get supportedStorageTitle => 'Підтримувані сховища';

  @override
  String get supportedStorageDescription =>
      'Підключайте улюблені сервіси. Почніть одразу з вбудованим безпечним сховищем FiFe на 1 ГБ безкоштовно.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Почніть резервне копіювання миттєво';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Безкоштовно';

  @override
  String get providerStorageDisclaimer =>
      '* Обсяг безкоштовного сховища вказано на сайті провайдера. Для сумісних провайдерів діє модель оплати за фактичне використання.';

  @override
  String get whyUseFifeTitle => 'Чому саме FiFe?';

  @override
  String get claimFreeCloudStorageTitle =>
      'Отримайте безкоштовне хмарне сховище';

  @override
  String get claimFreeCloudStorageDescription =>
      'Підключайте кілька хмарних провайдерів, щоб максимально використати доступний простір. Безпечно користуйтеся їхніми безкоштовними тарифами в одному застосунку.';

  @override
  String get topNotchSecurityTitle => 'Найвищий рівень безпеки';

  @override
  String get topNotchSecurityDescription =>
      'Працює на основі сучасної криптографії Sodium. Усе шифрування та розшифрування відбувається повністю на вашому пристрої.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Зберігайте повний контроль над своїми даними в усіх хмарних сервісах. Користуйтеся зашифрованим сховищем через власні облікові записи.';

  @override
  String get payAsYouGoStorageTitle => 'Платіть лише за використане сховище.';

  @override
  String get payAsYouGoStorageDescription =>
      'Платіть тільки за фактично використане сховище в сумісних провайдерів. Без посередників і без прив\'язки до сервісу.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Конфіденційність Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Ваші дані блокуються на пристрої ще до відправлення. Ми не можемо бачити, читати чи сканувати ваші файли.';

  @override
  String get localSelectionTitle => '1. Локальний вибір';

  @override
  String get localSelectionDescription =>
      'Ви обираєте папку. Уся обробка безпечно починається на вашому пристрої.';

  @override
  String get metadataEncryptionTitle => '2. Шифрування метаданих';

  @override
  String get metadataEncryptionDescription =>
      'Інформація про файли (назви, типи та розміри) шифрується ще до відправлення на сервер.';

  @override
  String get contentEncryptionTitle => '3. Шифрування вмісту';

  @override
  String get contentEncryptionDescription =>
      'Вміст файлу ділиться на фрагменти та шифрується перед завантаженням у хмарне сховище.';

  @override
  String get blindServerTitle => '4. Сліпий сервер';

  @override
  String get blindServerDescription =>
      'Наші сервери нічого не знають про ваші дані. Ми бачимо лише зашифровані блоки, що гарантує повну конфіденційність.';

  @override
  String get dontTrustVerifyTitle => 'Не довіряйте наосліп — перевіряйте.';

  @override
  String get openSourceVerificationDescription =>
      '100% відкритий код. Ви можете переглянути його й побачити, як саме шифруються ваші файли.';

  @override
  String get getStarted => 'Почати';

  @override
  String get next => 'Далі';

  @override
  String get unauthorized => 'Немає доступу';

  @override
  String get tryAgain => 'Спробувати ще раз';

  @override
  String get errorTitle => 'Помилка';

  @override
  String get failureTitle => 'Невдача';

  @override
  String get invalidWordList => 'Недійсний список слів';

  @override
  String get invalidAccessKey => 'Недійсний ключ доступу';

  @override
  String get unexpectedDecryptionError =>
      'Під час розшифрування сталася неочікувана помилка.';

  @override
  String get fileMustContainExactly24Words =>
      'Файл має містити рівно 24 слова.';

  @override
  String get errorReadingFile => 'Помилка читання файлу';

  @override
  String get encryptionTitle => 'Шифрування';

  @override
  String get accessKeyDecodeDescription =>
      'Введіть свою 24-слівну фразу відновлення або завантажте файл .txt, щоб безпечно увімкнути хмарну синхронізацію.';

  @override
  String get recoveryPhraseLabel => 'Фраза відновлення';

  @override
  String get recoveryPhraseHint => 'слово1 слово2 слово3...';

  @override
  String get paste => 'Вставити';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 слів';
  }

  @override
  String get pleaseEnterRecoveryPhrase =>
      'Будь ласка, введіть фразу відновлення';

  @override
  String get mustContainExactly24Words => 'Має містити рівно 24 слова';

  @override
  String get verify => 'Перевірити';

  @override
  String get orLabel => 'АБО';

  @override
  String get loadFromTxtFile => 'Завантажити з .txt файлу';

  @override
  String get saveAccessKey => 'Зберегти ключ доступу';

  @override
  String get fileSavedSuccessfully => 'Файл успішно збережено.';

  @override
  String get accessKeyShareMessage => 'Ось ваш ключ доступу.';

  @override
  String get pleaseTryAgain => 'Будь ласка, спробуйте ще раз.';

  @override
  String get copiedToClipboard => 'Скопійовано в буфер обміну';

  @override
  String get accessKeyTitle => 'Ключ доступу';

  @override
  String get accessKeyDescription =>
      'Збережіть цей ключ у безпечному місці. Лише він дасть вам доступ до ваших зашифрованих даних.';

  @override
  String get copy => 'Копіювати';

  @override
  String get downloadAsTextFile => 'Завантажити як текстовий файл';

  @override
  String get continueLabel => 'Продовжити';

  @override
  String get importantTitle => 'Важливо';

  @override
  String get accessKeyNoticePrimary =>
      'На наступній сторінці ви побачите набір із 24 слів. Це ваш унікальний і приватний ключ шифрування, і це ЄДИНИЙ спосіб відновити дані у разі виходу з акаунта, втрати пристрою або його несправності.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Ми не зберігаємо цей ключ. Ви несете відповідальність за те, щоб зберегти його в безпечному місці поза застосунком $appName.';
  }

  @override
  String get showKeyConfirmation => 'Я розумію.\nПоказати ключ.';

  @override
  String get storageAddedSuccessfully => 'Сховище успішно додано';

  @override
  String get networkErrorDuringValidation =>
      'Під час перевірки сталася мережева помилка.';

  @override
  String get verifyAndConnect => 'Перевірити й підключити';

  @override
  String get requiredField => 'Обов\'язково';

  @override
  String get providerKeysVerifiedLocally =>
      'Ваші ключі перевіряються локально та шифруються перед передаванням.';

  @override
  String get enterYourCredentials => 'Введіть свої дані';

  @override
  String connectProvider(String provider) {
    return 'Підключити $provider';
  }

  @override
  String get deviceLimitReached => 'Досягнуто ліміту пристроїв';

  @override
  String get pleaseTryAgainWithExclamation => 'Будь ласка, спробуйте ще раз!';

  @override
  String get notThisDevice => 'Не цей пристрій!';

  @override
  String get confirmSignoutDeviceTitle => 'Підтвердити вихід із пристрою';

  @override
  String get areYouSure => 'Ви впевнені?';

  @override
  String get cancel => 'Скасувати';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Пристроїв не знайдено';

  @override
  String get backTooltip => 'Назад';

  @override
  String get devicesTitle => 'Пристрої';

  @override
  String get longPressToDownload => 'Натисніть і утримуйте, щоб завантажити';

  @override
  String get fewItemsExistLocally => 'Деякі елементи все ще є локально.';

  @override
  String selectedItemsCount(int count) {
    return 'Вибрано: $count';
  }

  @override
  String get delete => 'Видалити';

  @override
  String get info => 'Інформація';

  @override
  String get download => 'Завантажити';

  @override
  String get archive => 'Архівувати';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Журнали';

  @override
  String get settings => 'Налаштування';

  @override
  String get trash => 'Кошик';

  @override
  String get storage => 'Сховище';

  @override
  String get search => 'Пошук';

  @override
  String get database => 'База даних';

  @override
  String get addFolderTitle => 'Додати папку';

  @override
  String get confirm => 'Підтвердити';

  @override
  String get tapPlusToAddSyncFolder =>
      'Натисніть +, щоб додати папку синхронізації.';

  @override
  String get thisFolderIsEmpty => 'Ця папка порожня.';

  @override
  String get fileNotFound => 'Файл не знайдено';

  @override
  String filePartsTitle(int count) {
    return 'Частини файлу ($count)';
  }

  @override
  String get fileDetailsTitle => 'Дані про файл';

  @override
  String get encryptedBackup => 'Зашифрована резервна копія';

  @override
  String get sizeLabel => 'Розмір';

  @override
  String get providerLabel => 'Провайдер';

  @override
  String get uploadedAtLabel => 'Завантажено';

  @override
  String get statusLabel => 'Стан';

  @override
  String get uploadedStatus => 'Завантажено';

  @override
  String errorWithMessage(String message) {
    return 'Помилка: $message';
  }

  @override
  String get noLogsAvailable => 'Журнали відсутні';

  @override
  String get searchLogsHint => 'Пошук у журналах...';

  @override
  String get clearLogs => 'Очистити журнали';

  @override
  String get searchWithMinThreeCharacters => 'Пошук доступний від 3 символів';

  @override
  String get typeBelowToSearch => 'Почніть вводити для пошуку';

  @override
  String get noResults => 'Нічого не знайдено.';

  @override
  String get welcomeTitle => 'Ласкаво просимо';

  @override
  String signInToContinue(String appName) {
    return 'Увійдіть, щоб продовжити в $appName';
  }

  @override
  String get pleaseEnterYourEmail =>
      'Будь ласка, введіть свою електронну адресу';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Будь ласка, введіть коректну електронну адресу';

  @override
  String get emailAddressLabel => 'Електронна адреса';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'Надіслати OTP ще раз';

  @override
  String get sendOtp => 'Надіслати OTP';

  @override
  String get checkYourEmail => 'Перевірте електронну пошту';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Ми надіслали 6-значний код на\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Будь ласка, введіть OTP';

  @override
  String get otpMustBeSixDigits => 'OTP має складатися з 6 цифр';

  @override
  String get enterOtpLabel => 'Введіть OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Повторити перевірку';

  @override
  String get verifyOtp => 'Підтвердити OTP';

  @override
  String get useDifferentEmail => 'Використати іншу електронну адресу';

  @override
  String get alreadySignedIn => 'Ви вже ввійшли';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Не вдалося надіслати OTP. Будь ласка, спробуйте ще раз!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Не вдалося підтвердити OTP. Будь ласка, спробуйте ще раз.';

  @override
  String get dbViewerTitle => 'Перегляд БД';

  @override
  String get selectTableToViewData =>
      'Виберіть таблицю, щоб переглянути її дані';

  @override
  String get selectTable => 'Виберіть таблицю';

  @override
  String get permissionRequiredTitle => 'Потрібен дозвіл';

  @override
  String get storagePermissionSettingsDescription =>
      'Щоб автоматично створювати резервні копії, керувати та захищати ваші файли у фоновому режимі, нам потрібен доступ до сховища пристрою. Ваші дані шифруються локально, що забезпечує повну конфіденційність. Будь ласка, надайте доступ, щоб продовжити.';

  @override
  String get openSettings => 'Відкрити налаштування';

  @override
  String get secureLocalAccessTitle => 'Безпечний локальний доступ';

  @override
  String get storagePermissionPageDescription =>
      'Щоб переглядати, шифрувати й автоматично створювати резервні копії файлів, нам потрібен доступ до сховища вашого пристрою.';

  @override
  String get verifying => 'Перевірка...';

  @override
  String get grantAccess => 'Надати доступ';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Zero-knowledge зашифроване сховище';

  @override
  String get notificationPermissionTitle => 'Доступ до сповіщень';

  @override
  String get notificationPermissionPageDescription =>
      'Щоб швидко синхронізувати й завантажувати файли у фоновому режимі через панель сповіщень, нам потрібен дозвіл на показ сповіщень. Ви можете будь-коли вимкнути його в налаштуваннях.';

  @override
  String get notificationPermissionGrantButton => 'Дозволити сповіщення';

  @override
  String get notificationPermissionSettingsDescription =>
      'Сповіщення потрібні для роботи функції швидкої синхронізації через панель сповіщень. Увімкніть їх у системних налаштуваннях, щоб усі ваші дані були успішно завантажені.';

  @override
  String requiresAppPro(String appName) {
    return 'Потрібен $appName Pro.';
  }

  @override
  String get noStorageFound => 'Сховище не знайдено';

  @override
  String get howToConnect => 'Як підключити';

  @override
  String get modify => 'Змінити';

  @override
  String storageUsed(String used, String total) {
    return 'Використано: $used / $total';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'До $size безкоштовно';
  }

  @override
  String get notConnected => 'Не підключено';

  @override
  String get connect => 'Підключити';

  @override
  String get modifyStorageCapacityTitle => 'Змінити обсяг сховища';

  @override
  String get enterNewStorageLimitForProvider =>
      'Введіть новий ліміт сховища для цього провайдера.';

  @override
  String get sizePrefix => 'Розмір: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Будь ласка, введіть розмір';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Введіть коректне число більше за 1';

  @override
  String get submit => 'Надіслати';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Ви успішно оформили підписку на $appName Pro!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Покупку скасовано або не завершено.';

  @override
  String get purchasesRestoredSuccessfully => 'Покупки успішно відновлено!';

  @override
  String get noActiveSubscriptionsFound => 'Активних підписок не знайдено.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Будь ласка, керуйте підписками в налаштуваннях пристрою.';

  @override
  String get freePlanTitle => 'Безкоштовно';

  @override
  String get freeForeverPrice => '\$0.00 / назавжди';

  @override
  String get freeBenefitProviderStorage =>
      'Користуйтеся безкоштовним сховищем від провайдерів';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Безпечно синхронізуйте до 3 пристроїв';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Річна підписка';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Змінюйте ліміт сховища для кожного провайдера';

  @override
  String get proBenefitSyncTenDevices => 'Синхронізуйте до 10 пристроїв';

  @override
  String get restorePurchases => 'Відновити покупки';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Підписка пов\'язана з електронною адресою, а не з пристроєм';

  @override
  String get subscriptionExpiredTitle => 'Термін підписки завершився';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Переваги $appName Pro призупинено. Оновіть підписку нижче, щоб повернути ліміти сховища та синхронізацію пристроїв.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro активний';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Змінюйте ліміти сховища для кожного провайдера\n✓ Крос-синхронізація до 10 пристроїв';

  @override
  String get manageSubscription => 'Керувати підпискою';

  @override
  String get currentPlanBadge => 'ПОТОЧНИЙ';

  @override
  String get subscribeNow => 'Оформити підписку';

  @override
  String get subscribeOnMobileApp =>
      'Оформіть підписку в мобільному застосунку';

  @override
  String get recover => 'Відновити';

  @override
  String get empty => 'Очистити';

  @override
  String get noItems => 'Немає елементів.';
}
