// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Door verder te gaan, ga je akkoord met onze $terms en ons $privacy.';
  }

  @override
  String get termsOfService => 'Servicevoorwaarden';

  @override
  String get privacyPolicy => 'Privacybeleid';

  @override
  String get andLabel => ' en ';

  @override
  String get theme => 'Thema';

  @override
  String get themeTooltip => 'Licht/donker thema';

  @override
  String get logging => 'Logboek';

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
  String get reportIssue => 'Probleem melden';

  @override
  String get sourceCode => 'Broncode';

  @override
  String get desktopApp => 'Desktop-app';

  @override
  String get mobileApp => 'Mobiele app';

  @override
  String get leaveReview => 'Laat een review achter';

  @override
  String get share => 'Delen';

  @override
  String get versionLabel => 'Versie: ';

  @override
  String get loading => 'Laden...';

  @override
  String get signOut => 'Uitloggen';

  @override
  String get settingsPageTitle => 'Instellingen';

  @override
  String get language => 'Taal';

  @override
  String get tapToSelect => 'Tik om te kiezen';

  @override
  String get appTagline => 'Jouw privéveerboot voor bestanden';

  @override
  String get onboardingPurposeDescription =>
      'Een open-source cloudopslagdienst gebouwd met een zero-trust-architectuur. Je gegevens worden lokaal versleuteld voordat ze je apparaat verlaten.';

  @override
  String get failedToFetch => 'Ophalen mislukt.';

  @override
  String get supportedStorageTitle => 'Ondersteunde opslag';

  @override
  String get supportedStorageDescription =>
      'Koppel je favoriete aanbieders. Begin meteen met 1 GB gratis en veilige opslag van FiFe zelf.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Start direct met back-ups';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Gratis';

  @override
  String get providerStorageDisclaimer =>
      '* Gratis opslag zoals vermeld op de website van de aanbieder. Bij compatibele aanbieders betaal je alleen voor wat je gebruikt.';

  @override
  String get whyUseFifeTitle => 'Waarom FiFe gebruiken?';

  @override
  String get claimFreeCloudStorageTitle => 'Profiteer van gratis cloudopslag';

  @override
  String get claimFreeCloudStorageDescription =>
      'Haal meer uit je opslag door meerdere cloudproviders te koppelen. Gebruik hun gratis opslag veilig in één overzichtelijke app.';

  @override
  String get topNotchSecurityTitle => 'Topbeveiliging';

  @override
  String get topNotchSecurityDescription =>
      'Aangedreven door geavanceerde Sodium-cryptografie. Alle versleuteling en ontsleuteling gebeurt volledig lokaal op je apparaat.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Behoud volledige controle over je gegevens bij al je cloudopslagproviders. Gebruik versleutelde opslag met je eigen accounts.';

  @override
  String get payAsYouGoStorageTitle => 'Betaal alleen voor gebruikte opslag.';

  @override
  String get payAsYouGoStorageDescription =>
      'Betaal alleen voor de opslag die je gebruikt bij compatibele aanbieders. Geen tussenpartij, geen vendor lock-in.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Zero-knowledge-privacy';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Je gegevens worden op je apparaat vergrendeld voordat ze vertrekken. Wij kunnen je bestanden niet zien, lezen of scannen.';

  @override
  String get localSelectionTitle => '1. Lokaal selecteren';

  @override
  String get localSelectionDescription =>
      'Je kiest een map. Alle verwerking begint veilig op je eigen apparaat.';

  @override
  String get metadataEncryptionTitle => '2. Metadata versleutelen';

  @override
  String get metadataEncryptionDescription =>
      'Bestandsinformatie, zoals namen, types en groottes, wordt versleuteld voordat die naar de server wordt verzonden.';

  @override
  String get contentEncryptionTitle => '3. Inhoud versleutelen';

  @override
  String get contentEncryptionDescription =>
      'De daadwerkelijke bestandsinhoud wordt opgesplitst en versleuteld voordat deze naar cloudopslag wordt geüpload.';

  @override
  String get blindServerTitle => '4. Blinde server';

  @override
  String get blindServerDescription =>
      'Onze servers weten niets van je gegevens. Ze zien alleen versleutelde blokken, zodat je privacy volledig behouden blijft.';

  @override
  String get dontTrustVerifyTitle =>
      'Vertrouw niet zomaar, controleer het zelf.';

  @override
  String get openSourceVerificationDescription =>
      '100% open source. Je kunt de code zelf bekijken om precies te zien hoe je bestanden worden versleuteld.';

  @override
  String get getStarted => 'Aan de slag';

  @override
  String get next => 'Volgende';

  @override
  String get unauthorized => 'Geen toegang';

  @override
  String get tryAgain => 'Opnieuw proberen';

  @override
  String get errorTitle => 'Fout';

  @override
  String get failureTitle => 'Mislukt';

  @override
  String get invalidWordList => 'Ongeldige woordenlijst';

  @override
  String get invalidAccessKey => 'Ongeldige toegangssleutel';

  @override
  String get unexpectedDecryptionError =>
      'Er is een onverwachte fout opgetreden tijdens het ontsleutelen.';

  @override
  String get fileMustContainExactly24Words =>
      'Het bestand moet precies 24 woorden bevatten.';

  @override
  String get errorReadingFile => 'Fout bij het lezen van bestand';

  @override
  String get encryptionTitle => 'Versleuteling';

  @override
  String get accessKeyDecodeDescription =>
      'Voer je herstelzin van 24 woorden in of laad een .txt-bestand om cloudsynchronisatie veilig in te schakelen.';

  @override
  String get recoveryPhraseLabel => 'Herstelzin';

  @override
  String get recoveryPhraseHint => 'woord1 woord2 woord3...';

  @override
  String get paste => 'Plakken';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 woorden';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'Voer je herstelzin in';

  @override
  String get mustContainExactly24Words => 'Moet precies 24 woorden bevatten';

  @override
  String get verify => 'Verifiëren';

  @override
  String get orLabel => 'OF';

  @override
  String get loadFromTxtFile => 'Laden uit .txt-bestand';

  @override
  String get saveAccessKey => 'Toegangssleutel opslaan';

  @override
  String get fileSavedSuccessfully => 'Bestand is opgeslagen.';

  @override
  String get accessKeyShareMessage => 'Hier is je toegangssleutel.';

  @override
  String get pleaseTryAgain => 'Probeer het opnieuw.';

  @override
  String get copiedToClipboard => 'Gekopieerd naar klembord';

  @override
  String get accessKeyTitle => 'Toegangssleutel';

  @override
  String get accessKeyDescription =>
      'Bewaar deze sleutel op een veilige plek. Alleen hiermee krijg je toegang tot je versleutelde gegevens.';

  @override
  String get copy => 'Kopiëren';

  @override
  String get downloadAsTextFile => 'Downloaden als tekstbestand';

  @override
  String get continueLabel => 'Doorgaan';

  @override
  String get importantTitle => 'Belangrijk';

  @override
  String get accessKeyNoticePrimary =>
      'Op de volgende pagina zie je een reeks van 24 woorden. Dit is jouw unieke en privé versleutelingssleutel en de ENIGE manier om je gegevens te herstellen als je uitlogt, je apparaat kwijtraakt of er een storing optreedt.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Wij slaan deze sleutel niet op. Het is jouw verantwoordelijkheid om hem op een veilige plek buiten de $appName-app te bewaren.';
  }

  @override
  String get showKeyConfirmation => 'Ik begrijp het.\nToon de sleutel.';

  @override
  String get storageAddedSuccessfully => 'Opslag succesvol toegevoegd';

  @override
  String get networkErrorDuringValidation =>
      'Er is een netwerktfout opgetreden tijdens de controle.';

  @override
  String get verifyAndConnect => 'Verifiëren en verbinden';

  @override
  String get requiredField => 'Verplicht';

  @override
  String get providerKeysVerifiedLocally =>
      'Je sleutels worden lokaal gecontroleerd en versleuteld voordat ze worden verzonden.';

  @override
  String get enterYourCredentials => 'Voer je inloggegevens in';

  @override
  String connectProvider(String provider) {
    return 'Verbind $provider';
  }

  @override
  String get deviceLimitReached => 'Apparaatlimiet bereikt';

  @override
  String get pleaseTryAgainWithExclamation => 'Probeer het opnieuw!';

  @override
  String get notThisDevice => 'Niet dit apparaat!';

  @override
  String get confirmSignoutDeviceTitle => 'Uitloggen van apparaat bevestigen';

  @override
  String get areYouSure => 'Weet je het zeker?';

  @override
  String get cancel => 'Annuleren';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Geen apparaat gevonden';

  @override
  String get backTooltip => 'Terug';

  @override
  String get devicesTitle => 'Apparaten';

  @override
  String get longPressToDownload => 'Houd ingedrukt om te downloaden';

  @override
  String get fewItemsExistLocally => 'Enkele items bestaan nog lokaal.';

  @override
  String selectedItemsCount(int count) {
    return '$count geselecteerd';
  }

  @override
  String get delete => 'Verwijderen';

  @override
  String get info => 'Info';

  @override
  String get download => 'Downloaden';

  @override
  String get archive => 'Archiveren';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Logboeken';

  @override
  String get settings => 'Instellingen';

  @override
  String get trash => 'Prullenbak';

  @override
  String get storage => 'Opslag';

  @override
  String get search => 'Zoeken';

  @override
  String get database => 'Database';

  @override
  String get addFolderTitle => 'Map toevoegen';

  @override
  String get confirm => 'Bevestigen';

  @override
  String get tapPlusToAddSyncFolder =>
      'Tik op + om een synchronisatiemap toe te voegen.';

  @override
  String get thisFolderIsEmpty => 'Deze map is leeg.';

  @override
  String get fileNotFound => 'Bestand niet gevonden';

  @override
  String filePartsTitle(int count) {
    return 'Bestandsdelen ($count)';
  }

  @override
  String get fileDetailsTitle => 'Bestandsdetails';

  @override
  String get encryptedBackup => 'Versleutelde back-up';

  @override
  String get sizeLabel => 'Grootte';

  @override
  String get providerLabel => 'Aanbieder';

  @override
  String get uploadedAtLabel => 'Geüpload op';

  @override
  String get statusLabel => 'Status';

  @override
  String get uploadedStatus => 'Geüpload';

  @override
  String errorWithMessage(String message) {
    return 'Fout: $message';
  }

  @override
  String get noLogsAvailable => 'Geen logboeken beschikbaar';

  @override
  String get searchLogsHint => 'Logboeken doorzoeken...';

  @override
  String get clearLogs => 'Logboeken wissen';

  @override
  String get searchWithMinThreeCharacters => 'Zoek met minimaal 3 tekens';

  @override
  String get typeBelowToSearch => 'Typ hieronder om te zoeken';

  @override
  String get noResults => 'Geen resultaten.';

  @override
  String get welcomeTitle => 'Welkom';

  @override
  String signInToContinue(String appName) {
    return 'Log in om verder te gaan naar $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Voer je e-mailadres in';

  @override
  String get pleaseEnterValidEmailAddress => 'Voer een geldig e-mailadres in';

  @override
  String get emailAddressLabel => 'E-mailadres';

  @override
  String get emailAddressHint => 'jouw.email@voorbeeld.com';

  @override
  String get retrySendingOtp => 'OTP opnieuw verzenden';

  @override
  String get sendOtp => 'OTP verzenden';

  @override
  String get checkYourEmail => 'Controleer je e-mail';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'We hebben een code van 6 cijfers gestuurd naar\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Voer de OTP in';

  @override
  String get otpMustBeSixDigits => 'OTP moet uit 6 cijfers bestaan';

  @override
  String get enterOtpLabel => 'Voer OTP in';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Verificatie opnieuw proberen';

  @override
  String get verifyOtp => 'OTP verifiëren';

  @override
  String get useDifferentEmail => 'Gebruik een ander e-mailadres';

  @override
  String get alreadySignedIn => 'Al ingelogd';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'OTP verzenden mislukt. Probeer het opnieuw!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'OTP-verificatie mislukt. Probeer het opnieuw.';

  @override
  String get dbViewerTitle => 'DB-viewer';

  @override
  String get selectTableToViewData =>
      'Selecteer een tabel om de gegevens te bekijken';

  @override
  String get selectTable => 'Selecteer een tabel';

  @override
  String get permissionRequiredTitle => 'Toestemming vereist';

  @override
  String get storagePermissionSettingsDescription =>
      'Om je bestanden automatisch op de achtergrond te back-uppen, beheren en beveiligen, hebben we toegang tot de opslag van je apparaat nodig. Je gegevens worden lokaal versleuteld, zodat je privacy beschermd blijft. Geef toegang om verder te gaan.';

  @override
  String get openSettings => 'Instellingen openen';

  @override
  String get secureLocalAccessTitle => 'Veilige lokale toegang';

  @override
  String get storagePermissionPageDescription =>
      'Om je bestanden te bekijken, versleutelen en automatisch te back-uppen, hebben we toegang tot de opslag van je apparaat nodig.';

  @override
  String get verifying => 'Controleren...';

  @override
  String get grantAccess => 'Toegang geven';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Zero-knowledge versleutelde opslag';

  @override
  String get notificationPermissionTitle => 'Toegang tot meldingen';

  @override
  String get notificationPermissionPageDescription =>
      'Om je bestanden gesynchroniseerd te houden en real-time statusupdates op de achtergrond te geven, hebben we toestemming nodig om meldingen te tonen.';

  @override
  String get notificationPermissionGrantButton => 'Meldingen toestaan';

  @override
  String get notificationPermissionSettingsDescription =>
      'Meldingen zijn vereist om synchronisatie op de achtergrond te bewaken. Schakel deze in de systeeminstellingen in om er zeker van te zijn dat je gegevens altijd up-to-date zijn.';

  @override
  String requiresAppPro(String appName) {
    return 'Vereist $appName Pro.';
  }

  @override
  String get noStorageFound => 'Geen opslag gevonden';

  @override
  String get howToConnect => 'Zo maak je verbinding';

  @override
  String get modify => 'Wijzigen';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total gebruikt';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Tot $size gratis';
  }

  @override
  String get notConnected => 'Niet verbonden';

  @override
  String get connect => 'Verbinden';

  @override
  String get modifyStorageCapacityTitle => 'Opslagcapaciteit wijzigen';

  @override
  String get enterNewStorageLimitForProvider =>
      'Voer de nieuwe opslaglimiet voor deze aanbieder in.';

  @override
  String get sizePrefix => 'Grootte: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Voer een grootte in';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Voer een geldig getal groter dan 1 in';

  @override
  String get submit => 'Verzenden';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Je bent nu geabonneerd op $appName Pro!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Aankoop geannuleerd of mislukt.';

  @override
  String get purchasesRestoredSuccessfully => 'Aankopen succesvol hersteld!';

  @override
  String get noActiveSubscriptionsFound =>
      'Geen actieve abonnementen gevonden.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Beheer abonnementen via de instellingen van je apparaat.';

  @override
  String get freePlanTitle => 'Gratis';

  @override
  String get freeForeverPrice => '\$0.00 / voor altijd';

  @override
  String get freeBenefitProviderStorage =>
      'Gebruik gratis opslag van aanbieders';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Synchroniseer veilig tot 3 apparaten';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Jaarlijks';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Pas de opslaglimiet per aanbieder aan';

  @override
  String get proBenefitSyncTenDevices => 'Synchroniseer tot 10 apparaten';

  @override
  String get restorePurchases => 'Aankopen herstellen';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* Abonnement is gekoppeld aan het e-mailaccount, niet aan het apparaat';

  @override
  String get subscriptionExpiredTitle => 'Abonnement verlopen';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Je voordelen van $appName Pro zijn gepauzeerd. Vernieuw hieronder om je opslaglimieten en apparaatsynchronisatie te herstellen.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro is actief';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Pas opslaglimieten per aanbieder aan\n✓ Synchroniseer tot 10 apparaten onderling';

  @override
  String get manageSubscription => 'Abonnement beheren';

  @override
  String get currentPlanBadge => 'HUIDIG';

  @override
  String get subscribeNow => 'Nu abonneren';

  @override
  String get subscribeOnMobileApp => 'Abonneer je via de mobiele app';

  @override
  String get recover => 'Herstellen';

  @override
  String get empty => 'Legen';

  @override
  String get noItems => 'Geen items.';
}
