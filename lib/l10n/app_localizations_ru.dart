// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Продолжая, вы соглашаетесь с нашими $terms и $privacy.';
  }

  @override
  String get termsOfService => 'Условия использования';

  @override
  String get privacyPolicy => 'Политика конфиденциальности';

  @override
  String get andLabel => ' и ';

  @override
  String get theme => 'Тема';

  @override
  String get themeTooltip => 'Светлая/тёмная тема';

  @override
  String get logging => 'Журналирование';

  @override
  String get quickSyncNotificationSettingTitle =>
      'Уведомление о быстрой синхронизации';

  @override
  String get quickSyncNotificationTitle => 'Служба синхронизации файлов';

  @override
  String get quickSyncNotificationText =>
      'Нажмите кнопку ниже, чтобы синхронизировать';

  @override
  String get quickSyncNotificationButton => 'Синхронизировать сейчас';

  @override
  String get quickSyncNotificationInProgress => 'В процессе...';

  @override
  String get reportIssue => 'Сообщить о проблеме';

  @override
  String get sourceCode => 'Исходный код';

  @override
  String get desktopApp => 'Приложение для компьютера';

  @override
  String get mobileApp => 'Мобильное приложение';

  @override
  String get leaveReview => 'Оставить отзыв';

  @override
  String get share => 'Поделиться';

  @override
  String get versionLabel => 'Версия: ';

  @override
  String get loading => 'Загрузка...';

  @override
  String get signOut => 'Выйти';

  @override
  String get settingsPageTitle => 'Настройки';

  @override
  String get language => 'Язык';

  @override
  String get tapToSelect => 'Нажмите, чтобы выбрать';

  @override
  String get appTagline => 'Ваш личный паром для файлов';

  @override
  String get onboardingPurposeDescription =>
      'Open-source сервис облачного хранения, построенный на архитектуре zero-trust. Ваши данные шифруются локально ещё до того, как покинут устройство.';

  @override
  String get failedToFetch => 'Не удалось загрузить данные.';

  @override
  String get supportedStorageTitle => 'Поддерживаемые хранилища';

  @override
  String get supportedStorageDescription =>
      'Подключайте любимые сервисы. Начните сразу с 1 ГБ бесплатного защищённого хранилища от FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Начните резервное копирование сразу';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Бесплатно';

  @override
  String get providerStorageDisclaimer =>
      '* Бесплатный объём указан на сайте провайдера. У совместимых провайдеров действует оплата по факту использования.';

  @override
  String get whyUseFifeTitle => 'Почему FiFe?';

  @override
  String get claimFreeCloudStorageTitle =>
      'Используйте бесплатное облачное хранилище';

  @override
  String get claimFreeCloudStorageDescription =>
      'Увеличивайте доступное пространство, подключая несколько облачных провайдеров. Безопасно используйте их бесплатные тарифы в одном приложении.';

  @override
  String get topNotchSecurityTitle => 'Надёжная защита';

  @override
  String get topNotchSecurityDescription =>
      'Работает на продвинутой криптографии Sodium. Всё шифрование и расшифровка происходят только локально на вашем устройстве.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Сохраняйте полный контроль над своими данными у любых облачных провайдеров. Используйте зашифрованное хранилище со своими собственными аккаунтами.';

  @override
  String get payAsYouGoStorageTitle =>
      'Платите только за используемое хранилище.';

  @override
  String get payAsYouGoStorageDescription =>
      'Платите только за фактически используемый объём у совместимых провайдеров. Без посредников и без привязки к одной платформе.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Конфиденциальность Zero-Knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Ваши данные блокируются на устройстве ещё до отправки. Мы не можем видеть, читать или сканировать ваши файлы.';

  @override
  String get localSelectionTitle => '1. Локальный выбор';

  @override
  String get localSelectionDescription =>
      'Вы выбираете папку. Вся обработка безопасно начинается на вашем устройстве.';

  @override
  String get metadataEncryptionTitle => '2. Шифрование метаданных';

  @override
  String get metadataEncryptionDescription =>
      'Информация о файлах, включая названия, типы и размеры, шифруется до отправки на сервер.';

  @override
  String get contentEncryptionTitle => '3. Шифрование содержимого';

  @override
  String get contentEncryptionDescription =>
      'Содержимое файла разбивается на части и шифруется перед загрузкой в облачное хранилище.';

  @override
  String get blindServerTitle => '4. Слепой сервер';

  @override
  String get blindServerDescription =>
      'Наши серверы ничего не знают о ваших данных. Они видят только зашифрованные блоки, что обеспечивает полную конфиденциальность.';

  @override
  String get dontTrustVerifyTitle => 'Не доверяйте на слово — проверьте сами.';

  @override
  String get openSourceVerificationDescription =>
      '100% open source. Вы можете изучить код и сами увидеть, как именно шифруются ваши файлы.';

  @override
  String get getStarted => 'Начать';

  @override
  String get next => 'Далее';

  @override
  String get unauthorized => 'Нет доступа';

  @override
  String get tryAgain => 'Попробовать снова';

  @override
  String get errorTitle => 'Ошибка';

  @override
  String get failureTitle => 'Сбой';

  @override
  String get invalidWordList => 'Недопустимый список слов';

  @override
  String get invalidAccessKey => 'Неверный ключ доступа';

  @override
  String get unexpectedDecryptionError =>
      'Произошла непредвиденная ошибка при расшифровке.';

  @override
  String get fileMustContainExactly24Words =>
      'Файл должен содержать ровно 24 слова.';

  @override
  String get errorReadingFile => 'Ошибка чтения файла';

  @override
  String get encryptionTitle => 'Шифрование';

  @override
  String get accessKeyDecodeDescription =>
      'Введите вашу фразу восстановления из 24 слов или загрузите файл .txt, чтобы безопасно включить синхронизацию с облаком.';

  @override
  String get recoveryPhraseLabel => 'Фраза восстановления';

  @override
  String get recoveryPhraseHint => 'слово1 слово2 слово3...';

  @override
  String get paste => 'Вставить';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 слов';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'Введите фразу восстановления';

  @override
  String get mustContainExactly24Words => 'Должно быть ровно 24 слова';

  @override
  String get verify => 'Проверить';

  @override
  String get orLabel => 'ИЛИ';

  @override
  String get loadFromTxtFile => 'Загрузить из .txt файла';

  @override
  String get saveAccessKey => 'Сохранить ключ доступа';

  @override
  String get fileSavedSuccessfully => 'Файл успешно сохранён.';

  @override
  String get accessKeyShareMessage => 'Вот ваш ключ доступа.';

  @override
  String get pleaseTryAgain => 'Пожалуйста, попробуйте снова.';

  @override
  String get copiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get accessKeyTitle => 'Ключ доступа';

  @override
  String get accessKeyDescription =>
      'Сохраните этот ключ в безопасном месте. Только с его помощью вы сможете получить доступ к зашифрованным данным.';

  @override
  String get copy => 'Копировать';

  @override
  String get downloadAsTextFile => 'Скачать как текстовый файл';

  @override
  String get continueLabel => 'Продолжить';

  @override
  String get importantTitle => 'Важно';

  @override
  String get accessKeyNoticePrimary =>
      'На следующей странице вы увидите последовательность из 24 слов. Это ваш уникальный и приватный ключ шифрования, и это ЕДИНСТВЕННЫЙ способ восстановить данные в случае выхода из аккаунта, потери устройства или его неисправности.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Мы не храним этот ключ. Вы сами отвечаете за его сохранность и должны хранить его в безопасном месте вне приложения $appName.';
  }

  @override
  String get showKeyConfirmation => 'Я понимаю.\nПоказать ключ.';

  @override
  String get storageAddedSuccessfully => 'Хранилище успешно добавлено';

  @override
  String get networkErrorDuringValidation =>
      'Во время проверки произошла ошибка сети.';

  @override
  String get verifyAndConnect => 'Проверить и подключить';

  @override
  String get requiredField => 'Обязательно';

  @override
  String get providerKeysVerifiedLocally =>
      'Ваши ключи проверяются локально и шифруются перед отправкой.';

  @override
  String get enterYourCredentials => 'Введите ваши данные';

  @override
  String connectProvider(String provider) {
    return 'Подключить $provider';
  }

  @override
  String get deviceLimitReached => 'Достигнут лимит устройств';

  @override
  String get pleaseTryAgainWithExclamation => 'Пожалуйста, попробуйте снова!';

  @override
  String get notThisDevice => 'Не это устройство!';

  @override
  String get confirmSignoutDeviceTitle => 'Подтвердите выход с устройства';

  @override
  String get areYouSure => 'Вы уверены?';

  @override
  String get cancel => 'Отмена';

  @override
  String get ok => 'ОК';

  @override
  String get noDeviceFound => 'Устройства не найдены';

  @override
  String get backTooltip => 'Назад';

  @override
  String get devicesTitle => 'Устройства';

  @override
  String get longPressToDownload => 'Нажмите и удерживайте для скачивания';

  @override
  String get fewItemsExistLocally =>
      'Некоторые элементы всё ещё есть локально.';

  @override
  String selectedItemsCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get delete => 'Удалить';

  @override
  String get info => 'Информация';

  @override
  String get download => 'Скачать';

  @override
  String get archive => 'Архивировать';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Журналы';

  @override
  String get settings => 'Настройки';

  @override
  String get trash => 'Корзина';

  @override
  String get storage => 'Хранилище';

  @override
  String get search => 'Поиск';

  @override
  String get database => 'База данных';

  @override
  String get addFolderTitle => 'Добавить папку';

  @override
  String get confirm => 'Подтвердить';

  @override
  String get tapPlusToAddSyncFolder =>
      'Нажмите +, чтобы добавить папку синхронизации.';

  @override
  String get thisFolderIsEmpty => 'Эта папка пуста.';

  @override
  String get fileNotFound => 'Файл не найден';

  @override
  String filePartsTitle(int count) {
    return 'Части файла ($count)';
  }

  @override
  String get fileDetailsTitle => 'Сведения о файле';

  @override
  String get encryptedBackup => 'Зашифрованная резервная копия';

  @override
  String get sizeLabel => 'Размер';

  @override
  String get providerLabel => 'Провайдер';

  @override
  String get uploadedAtLabel => 'Дата загрузки';

  @override
  String get statusLabel => 'Статус';

  @override
  String get uploadedStatus => 'Загружено';

  @override
  String errorWithMessage(String message) {
    return 'Ошибка: $message';
  }

  @override
  String get noLogsAvailable => 'Журналы отсутствуют';

  @override
  String get searchLogsHint => 'Поиск по журналам...';

  @override
  String get clearLogs => 'Очистить журналы';

  @override
  String get searchWithMinThreeCharacters =>
      'Введите минимум 3 символа для поиска';

  @override
  String get typeBelowToSearch => 'Начните вводить текст для поиска';

  @override
  String get noResults => 'Ничего не найдено.';

  @override
  String get welcomeTitle => 'Добро пожаловать';

  @override
  String signInToContinue(String appName) {
    return 'Войдите, чтобы продолжить в $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Введите ваш адрес электронной почты';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Введите корректный адрес электронной почты';

  @override
  String get emailAddressLabel => 'Адрес электронной почты';

  @override
  String get emailAddressHint => 'your.email@example.com';

  @override
  String get retrySendingOtp => 'Повторно отправить OTP';

  @override
  String get sendOtp => 'Отправить OTP';

  @override
  String get checkYourEmail => 'Проверьте почту';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Мы отправили 6-значный код на\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Введите OTP';

  @override
  String get otpMustBeSixDigits => 'OTP должен состоять из 6 цифр';

  @override
  String get enterOtpLabel => 'Введите OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Повторить проверку';

  @override
  String get verifyOtp => 'Проверить OTP';

  @override
  String get useDifferentEmail => 'Использовать другой адрес';

  @override
  String get alreadySignedIn => 'Вход уже выполнен';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Не удалось отправить OTP. Пожалуйста, попробуйте снова!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Не удалось проверить OTP. Пожалуйста, попробуйте снова.';

  @override
  String get dbViewerTitle => 'Просмотр БД';

  @override
  String get selectTableToViewData =>
      'Выберите таблицу, чтобы посмотреть её данные';

  @override
  String get selectTable => 'Выберите таблицу';

  @override
  String get permissionRequiredTitle => 'Требуется разрешение';

  @override
  String get storagePermissionSettingsDescription =>
      'Чтобы автоматически создавать резервные копии, управлять и защищать ваши файлы в фоновом режиме, нам нужен доступ к хранилищу устройства. Ваши данные шифруются локально, что обеспечивает полную конфиденциальность. Разрешите доступ, чтобы продолжить.';

  @override
  String get openSettings => 'Открыть настройки';

  @override
  String get secureLocalAccessTitle => 'Безопасный локальный доступ';

  @override
  String get storagePermissionPageDescription =>
      'Чтобы просматривать, шифровать и автоматически создавать резервные копии файлов, нам нужен доступ к хранилищу устройства.';

  @override
  String get verifying => 'Проверка...';

  @override
  String get grantAccess => 'Предоставить доступ';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Шифрованное хранилище Zero-Knowledge';

  @override
  String get notificationPermissionTitle => 'Доступ к уведомлениям';

  @override
  String get notificationPermissionPageDescription =>
      'Чтобы быстро синхронизировать и загружать файлы в фоновом режиме через панель уведомлений, приложению требуется разрешение на показ уведомлений. Вы можете отключить его в любое время в настройках.';

  @override
  String get notificationPermissionGrantButton => 'Разрешить уведомления';

  @override
  String get notificationPermissionSettingsDescription =>
      'Уведомления необходимы для работы функции быстрой синхронизации через панель уведомлений. Включите их в настройках системы, чтобы все ваши данные были успешно загружены.';

  @override
  String requiresAppPro(String appName) {
    return 'Требуется $appName Pro.';
  }

  @override
  String get noStorageFound => 'Хранилища не найдены';

  @override
  String get howToConnect => 'Как подключить';

  @override
  String get modify => 'Изменить';

  @override
  String storageUsed(String used, String total) {
    return 'Использовано: $used / $total';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'До $size бесплатно';
  }

  @override
  String get notConnected => 'Не подключено';

  @override
  String get connect => 'Подключить';

  @override
  String get modifyStorageCapacityTitle => 'Изменить объём хранилища';

  @override
  String get enterNewStorageLimitForProvider =>
      'Введите новый лимит хранилища для этого провайдера.';

  @override
  String get sizePrefix => 'Размер: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Введите размер';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Введите корректное число больше 1';

  @override
  String get submit => 'Сохранить';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Подписка на $appName Pro успешно оформлена!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Покупка отменена или не удалась.';

  @override
  String get purchasesRestoredSuccessfully => 'Покупки успешно восстановлены!';

  @override
  String get noActiveSubscriptionsFound => 'Активные подписки не найдены.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Управляйте подписками в настройках устройства.';

  @override
  String get freePlanTitle => 'Бесплатно';

  @override
  String get freeForeverPrice => '\$0.00 / навсегда';

  @override
  String get freeBenefitProviderStorage =>
      'Используйте бесплатное хранилище провайдеров';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Безопасная синхронизация до 3 устройств';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Годовой';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Изменяйте лимит хранилища для каждого провайдера';

  @override
  String get proBenefitSyncTenDevices => 'Синхронизация до 10 устройств';

  @override
  String get restorePurchases => 'Восстановить покупки';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Подписка привязана к электронной почте, а не к устройству';

  @override
  String get subscriptionExpiredTitle => 'Срок подписки истёк';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Преимущества $appName Pro приостановлены. Продлите подписку ниже, чтобы восстановить лимиты хранилища и синхронизацию устройств.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro активен';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Изменение лимитов хранилища для каждого провайдера\n✓ Кросс-синхронизация до 10 устройств';

  @override
  String get manageSubscription => 'Управление подпиской';

  @override
  String get currentPlanBadge => 'ТЕКУЩИЙ';

  @override
  String get subscribeNow => 'Оформить подписку';

  @override
  String get subscribeOnMobileApp => 'Оформите подписку в мобильном приложении';

  @override
  String get recover => 'Восстановить';

  @override
  String get empty => 'Очистить';

  @override
  String get noItems => 'Нет элементов.';
}
