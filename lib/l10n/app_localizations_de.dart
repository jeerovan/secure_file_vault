// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Indem du fortfährst, stimmst du unseren $terms und der $privacy zu.';
  }

  @override
  String get termsOfService => 'Nutzungsbedingungen';

  @override
  String get privacyPolicy => 'Datenschutzerklärung';

  @override
  String get andLabel => ' und ';

  @override
  String get theme => 'Design';

  @override
  String get themeTooltip => 'Tag-/Nacht-Design';

  @override
  String get logging => 'Protokollierung';

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
  String get reportIssue => 'Problem melden';

  @override
  String get sourceCode => 'Quellcode';

  @override
  String get desktopApp => 'Desktop-App';

  @override
  String get mobileApp => 'Mobile-App';

  @override
  String get leaveReview => 'Bewertung abgeben';

  @override
  String get share => 'Teilen';

  @override
  String get versionLabel => 'Version: ';

  @override
  String get loading => 'Wird geladen...';

  @override
  String get signOut => 'Abmelden';

  @override
  String get settingsPageTitle => 'Einstellungen';

  @override
  String get language => 'Sprache';

  @override
  String get tapToSelect => 'Tippen zum Auswählen';

  @override
  String get appTagline => 'Deine private Fähre für Dateien';

  @override
  String get onboardingPurposeDescription =>
      'Ein Open-Source-Cloudspeicher mit Zero-Trust-Architektur. Deine Daten werden direkt auf deinem Gerät verschlüsselt, bevor sie es verlassen.';

  @override
  String get failedToFetch => 'Laden fehlgeschlagen.';

  @override
  String get supportedStorageTitle => 'Unterstützte Speicher';

  @override
  String get supportedStorageDescription =>
      'Verbinde deine bevorzugten Anbieter. Starte sofort mit 1 GB kostenlosem, sicherem Speicher von FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Backups sofort starten';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Kostenlos';

  @override
  String get providerStorageDisclaimer =>
      '* Kostenloser Speicher gemäß Angaben auf der Website des Anbieters. Pay-as-you-go bei kompatiblen Anbietern.';

  @override
  String get whyUseFifeTitle => 'Warum FiFe?';

  @override
  String get claimFreeCloudStorageTitle => 'Kostenlosen Cloudspeicher nutzen';

  @override
  String get claimFreeCloudStorageDescription =>
      'Hol mehr Speicher heraus, indem du mehrere Cloud-Anbieter verbindest. Nutze ihre kostenlosen Speicherangebote sicher in einer einzigen App.';

  @override
  String get topNotchSecurityTitle => 'Sicherheit auf höchstem Niveau';

  @override
  String get topNotchSecurityDescription =>
      'Angetrieben von fortschrittlicher Sodium-Kryptografie. Ver- und Entschlüsselung finden vollständig lokal auf deinem Gerät statt.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Behalte die volle Kontrolle über deine Daten bei allen Cloudspeicher-Anbietern. Nutze verschlüsselten Speicher mit deinen eigenen Konten.';

  @override
  String get payAsYouGoStorageTitle => 'Speicher nach Nutzung bezahlen.';

  @override
  String get payAsYouGoStorageDescription =>
      'Zahle bei kompatiblen Anbietern nur für den tatsächlich genutzten Speicher. Kein Zwischenhändler, kein Daten-Lock-in.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Zero-Knowledge-Datenschutz';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Deine Daten werden auf deinem Gerät gesichert, bevor sie es verlassen. Wir können deine Dateien weder sehen noch lesen oder scannen.';

  @override
  String get localSelectionTitle => '1. Lokale Auswahl';

  @override
  String get localSelectionDescription =>
      'Du wählst einen Ordner aus. Die gesamte Verarbeitung startet sicher auf deinem Gerät.';

  @override
  String get metadataEncryptionTitle => '2. Metadaten verschlüsseln';

  @override
  String get metadataEncryptionDescription =>
      'Dateiinformationen wie Namen, Typen und Größen werden verschlüsselt, bevor sie an den Server gesendet werden.';

  @override
  String get contentEncryptionTitle => '3. Inhalt verschlüsseln';

  @override
  String get contentEncryptionDescription =>
      'Der eigentliche Dateiinhalt wird aufgeteilt und verschlüsselt, bevor er in den Cloudspeicher hochgeladen wird.';

  @override
  String get blindServerTitle => '4. Blinder Server';

  @override
  String get blindServerDescription =>
      'Unsere Server haben kein Wissen über deine Daten. Wir sehen nur verschlüsselte Datenblöcke und gewährleisten so absolute Privatsphäre.';

  @override
  String get dontTrustVerifyTitle => 'Nicht vertrauen, prüfen.';

  @override
  String get openSourceVerificationDescription =>
      '100 % Open Source. Du kannst den Code prüfen und genau sehen, wie deine Dateien verschlüsselt werden.';

  @override
  String get getStarted => 'Loslegen';

  @override
  String get next => 'Weiter';

  @override
  String get unauthorized => 'Nicht autorisiert';

  @override
  String get tryAgain => 'Erneut versuchen';

  @override
  String get errorTitle => 'Fehler';

  @override
  String get failureTitle => 'Fehlgeschlagen';

  @override
  String get invalidWordList => 'Ungültige Wortliste';

  @override
  String get invalidAccessKey => 'Ungültiger Zugriffsschlüssel';

  @override
  String get unexpectedDecryptionError =>
      'Beim Entschlüsseln ist ein unerwarteter Fehler aufgetreten.';

  @override
  String get fileMustContainExactly24Words =>
      'Die Datei muss genau 24 Wörter enthalten.';

  @override
  String get errorReadingFile => 'Fehler beim Lesen der Datei';

  @override
  String get encryptionTitle => 'Verschlüsselung';

  @override
  String get accessKeyDecodeDescription =>
      'Gib deine Wiederherstellungsphrase mit 24 Wörtern ein oder lade eine .txt-Datei, um die Cloud-Synchronisierung sicher zu aktivieren.';

  @override
  String get recoveryPhraseLabel => 'Wiederherstellungsphrase';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => 'Einfügen';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 Wörter';
  }

  @override
  String get pleaseEnterRecoveryPhrase =>
      'Bitte gib deine Wiederherstellungsphrase ein';

  @override
  String get mustContainExactly24Words => 'Muss genau 24 Wörter enthalten';

  @override
  String get verify => 'Prüfen';

  @override
  String get orLabel => 'ODER';

  @override
  String get loadFromTxtFile => 'Aus .txt-Datei laden';

  @override
  String get saveAccessKey => 'Zugriffsschlüssel speichern';

  @override
  String get fileSavedSuccessfully => 'Datei erfolgreich gespeichert.';

  @override
  String get accessKeyShareMessage => 'Hier ist dein Zugriffsschlüssel.';

  @override
  String get pleaseTryAgain => 'Bitte versuche es erneut.';

  @override
  String get copiedToClipboard => 'In die Zwischenablage kopiert';

  @override
  String get accessKeyTitle => 'Zugriffsschlüssel';

  @override
  String get accessKeyDescription =>
      'Bitte bewahre diesen Schlüssel an einem sicheren Ort auf. Nur damit kannst du auf deine verschlüsselten Daten zugreifen.';

  @override
  String get copy => 'Kopieren';

  @override
  String get downloadAsTextFile => 'Als Textdatei herunterladen';

  @override
  String get continueLabel => 'Fortfahren';

  @override
  String get importantTitle => 'Wichtig';

  @override
  String get accessKeyNoticePrimary =>
      'Auf der nächsten Seite siehst du eine Folge aus 24 Wörtern. Das ist dein einzigartiger privater Verschlüsselungsschlüssel und die EINZIGE Möglichkeit, deine Daten nach Abmeldung, Geräteverlust oder einem Defekt wiederherzustellen.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Wir speichern diesen Schlüssel nicht. Du bist selbst dafür verantwortlich, ihn an einem sicheren Ort außerhalb der $appName-App aufzubewahren.';
  }

  @override
  String get showKeyConfirmation =>
      'Ich habe verstanden.\nZeig mir den Schlüssel.';

  @override
  String get storageAddedSuccessfully => 'Speicher erfolgreich hinzugefügt';

  @override
  String get networkErrorDuringValidation =>
      'Bei der Überprüfung ist ein Netzwerkfehler aufgetreten.';

  @override
  String get verifyAndConnect => 'Prüfen & verbinden';

  @override
  String get requiredField => 'Erforderlich';

  @override
  String get providerKeysVerifiedLocally =>
      'Deine Schlüssel werden lokal geprüft und vor der Übertragung verschlüsselt.';

  @override
  String get enterYourCredentials => 'Gib deine Zugangsdaten ein';

  @override
  String connectProvider(String provider) {
    return '$provider verbinden';
  }

  @override
  String get deviceLimitReached => 'Gerätelimit erreicht';

  @override
  String get pleaseTryAgainWithExclamation => 'Bitte versuche es noch einmal!';

  @override
  String get notThisDevice => 'Nicht dieses Gerät!';

  @override
  String get confirmSignoutDeviceTitle => 'Abmeldung des Geräts bestätigen';

  @override
  String get areYouSure => 'Bist du sicher?';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Kein Gerät gefunden';

  @override
  String get backTooltip => 'Zurück';

  @override
  String get devicesTitle => 'Geräte';

  @override
  String get longPressToDownload => 'Zum Herunterladen lange drücken';

  @override
  String get fewItemsExistLocally =>
      'Einige Elemente sind noch lokal vorhanden.';

  @override
  String selectedItemsCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get delete => 'Löschen';

  @override
  String get info => 'Info';

  @override
  String get download => 'Herunterladen';

  @override
  String get archive => 'Archivieren';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Protokolle';

  @override
  String get settings => 'Einstellungen';

  @override
  String get trash => 'Papierkorb';

  @override
  String get storage => 'Speicher';

  @override
  String get search => 'Suche';

  @override
  String get database => 'Datenbank';

  @override
  String get addFolderTitle => 'Ordner hinzufügen';

  @override
  String get confirm => 'Bestätigen';

  @override
  String get tapPlusToAddSyncFolder =>
      'Tippe auf +, um einen Sync-Ordner hinzuzufügen.';

  @override
  String get thisFolderIsEmpty => 'Dieser Ordner ist leer.';

  @override
  String get fileNotFound => 'Datei nicht gefunden';

  @override
  String filePartsTitle(int count) {
    return 'Dateiteile ($count)';
  }

  @override
  String get fileDetailsTitle => 'Dateidetails';

  @override
  String get encryptedBackup => 'Verschlüsseltes Backup';

  @override
  String get sizeLabel => 'Größe';

  @override
  String get providerLabel => 'Anbieter';

  @override
  String get uploadedAtLabel => 'Hochgeladen am';

  @override
  String get statusLabel => 'Status';

  @override
  String get uploadedStatus => 'Hochgeladen';

  @override
  String errorWithMessage(String message) {
    return 'Fehler: $message';
  }

  @override
  String get noLogsAvailable => 'Keine Protokolle verfügbar';

  @override
  String get searchLogsHint => 'Protokolle durchsuchen...';

  @override
  String get clearLogs => 'Protokolle löschen';

  @override
  String get searchWithMinThreeCharacters => 'Suche mit mindestens 3 Zeichen';

  @override
  String get typeBelowToSearch => 'Gib unten etwas ein, um zu suchen';

  @override
  String get noResults => 'Keine Ergebnisse.';

  @override
  String get welcomeTitle => 'Willkommen';

  @override
  String signInToContinue(String appName) {
    return 'Melde dich an, um mit $appName fortzufahren';
  }

  @override
  String get pleaseEnterYourEmail => 'Bitte gib deine E-Mail-Adresse ein';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Bitte gib eine gültige E-Mail-Adresse ein';

  @override
  String get emailAddressLabel => 'E-Mail-Adresse';

  @override
  String get emailAddressHint => 'deine.email@beispiel.de';

  @override
  String get retrySendingOtp => 'OTP erneut senden';

  @override
  String get sendOtp => 'OTP senden';

  @override
  String get checkYourEmail => 'Prüfe deine E-Mails';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Wir haben einen 6-stelligen Code gesendet an\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Bitte gib den OTP ein';

  @override
  String get otpMustBeSixDigits => 'Der OTP muss 6-stellig sein';

  @override
  String get enterOtpLabel => 'OTP eingeben';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Überprüfung erneut versuchen';

  @override
  String get verifyOtp => 'OTP prüfen';

  @override
  String get useDifferentEmail => 'Andere E-Mail-Adresse verwenden';

  @override
  String get alreadySignedIn => 'Bereits angemeldet';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Senden des OTP fehlgeschlagen. Bitte versuche es erneut!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'OTP-Prüfung fehlgeschlagen. Bitte versuche es erneut.';

  @override
  String get dbViewerTitle => 'DB-Viewer';

  @override
  String get selectTableToViewData =>
      'Wähle eine Tabelle aus, um ihre Daten anzuzeigen';

  @override
  String get selectTable => 'Tabelle auswählen';

  @override
  String get permissionRequiredTitle => 'Berechtigung erforderlich';

  @override
  String get storagePermissionSettingsDescription =>
      'Damit wir deine Dateien automatisch im Hintergrund sichern, verwalten und schützen können, benötigen wir Zugriff auf den Speicher deines Geräts. Deine Daten werden lokal verschlüsselt und bleiben damit vollständig privat. Bitte erlaube den Zugriff, um fortzufahren.';

  @override
  String get openSettings => 'Einstellungen öffnen';

  @override
  String get secureLocalAccessTitle => 'Sicherer lokaler Zugriff';

  @override
  String get storagePermissionPageDescription =>
      'Um deine Dateien automatisch zu durchsuchen, zu verschlüsseln und zu sichern, benötigen wir Zugriff auf den Gerätespeicher.';

  @override
  String get verifying => 'Wird geprüft...';

  @override
  String get grantAccess => 'Zugriff erlauben';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Zero-Knowledge-verschlüsselter Speicher';

  @override
  String get notificationPermissionTitle => 'Benachrichtigungszugriff';

  @override
  String get notificationPermissionPageDescription =>
      'Um deine Dateien synchron zu halten und Status-Updates in Echtzeit im Hintergrund bereitzustellen, benötigen wir die Erlaubnis, Benachrichtigungen anzuzeigen.';

  @override
  String get notificationPermissionGrantButton => 'Benachrichtigungen zulassen';

  @override
  String get notificationPermissionSettingsDescription =>
      'Benachrichtigungen sind erforderlich, um die Hintergrundsynchronisierung zu überwachen. Bitte aktiviere sie in den Systemeinstellungen, um sicherzustellen, dass deine Daten immer aktuell sind.';

  @override
  String requiresAppPro(String appName) {
    return 'Erfordert $appName Pro.';
  }

  @override
  String get noStorageFound => 'Kein Speicher gefunden';

  @override
  String get howToConnect => 'So verbindest du es';

  @override
  String get modify => 'Ändern';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total verwendet';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Bis zu $size kostenlos';
  }

  @override
  String get notConnected => 'Nicht verbunden';

  @override
  String get connect => 'Verbinden';

  @override
  String get modifyStorageCapacityTitle => 'Speicherkapazität ändern';

  @override
  String get enterNewStorageLimitForProvider =>
      'Gib das neue Speicherlimit für diesen Anbieter ein.';

  @override
  String get sizePrefix => 'Größe: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Bitte gib eine Größe ein';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Gib eine gültige Zahl größer als 1 ein';

  @override
  String get submit => 'Senden';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Erfolgreich $appName Pro abonniert!';
  }

  @override
  String get purchaseCancelledOrFailed =>
      'Kauf abgebrochen oder fehlgeschlagen.';

  @override
  String get purchasesRestoredSuccessfully =>
      'Käufe erfolgreich wiederhergestellt!';

  @override
  String get noActiveSubscriptionsFound =>
      'Keine aktiven Abonnements gefunden.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Bitte verwalte Abonnements in den Geräteeinstellungen.';

  @override
  String get freePlanTitle => 'Kostenlos';

  @override
  String get freeForeverPrice => '\$0.00 / für immer';

  @override
  String get freeBenefitProviderStorage =>
      'Kostenlosen Speicher bei Anbietern nutzen';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Bis zu 3 Geräte sicher synchronisieren';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Jährlich';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Speicherlimit für jeden Anbieter anpassen';

  @override
  String get proBenefitSyncTenDevices => 'Bis zu 10 Geräte synchronisieren';

  @override
  String get restorePurchases => 'Käufe wiederherstellen';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Das Abonnement ist mit dem E-Mail-Konto verknüpft, nicht mit dem Gerät';

  @override
  String get subscriptionExpiredTitle => 'Abonnement abgelaufen';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Deine Vorteile von $appName Pro sind pausiert. Erneuere unten dein Abo, um Speicherlimits und Gerätesynchronisierung wiederherzustellen.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro ist aktiv';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Speicherlimits für jeden Anbieter anpassen\n✓ Geräteübergreifende Synchronisierung auf bis zu 10 Geräten';

  @override
  String get manageSubscription => 'Abo verwalten';

  @override
  String get currentPlanBadge => 'AKTUELL';

  @override
  String get subscribeNow => 'Jetzt abonnieren';

  @override
  String get subscribeOnMobileApp => 'In der Mobile-App abonnieren';

  @override
  String get recover => 'Wiederherstellen';

  @override
  String get empty => 'Leeren';

  @override
  String get noItems => 'Keine Elemente.';
}
