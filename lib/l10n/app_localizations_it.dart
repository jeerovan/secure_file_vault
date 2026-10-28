// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get localSessionCleanupTitle => 'Eliminazione dei dati locali';

  @override
  String get localSessionCleanupDescription =>
      'La sessione è terminata. FiFe deve completare l\'eliminazione dei dati locali dell\'account prima che tu possa accedere di nuovo. I file originali vengono conservati. Riprova per completare.';

  @override
  String get localSessionCleanupInProgress =>
      'Eliminazione dei dati FiFe da questo dispositivo…';

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Continuando, accetti i nostri $terms e la nostra $privacy.';
  }

  @override
  String get termsOfService => 'Termini di servizio';

  @override
  String get privacyPolicy => 'Informativa sulla privacy';

  @override
  String get andLabel => ' e ';

  @override
  String get theme => 'Tema';

  @override
  String get themeTooltip => 'Tema giorno/notte';

  @override
  String get logging => 'Log';

  @override
  String get appLockTitle => 'Blocco app';

  @override
  String get appLockDescription =>
      'Proteggi FiFe con l’impronta, il volto o il PIN del dispositivo.';

  @override
  String get appLockTimeout => 'Tempo di blocco';

  @override
  String get appLockTimeoutDescription =>
      'Richiedi l’autenticazione dopo questo tempo fuori da FiFe. A ogni riavvio dell’app è sempre richiesta.';

  @override
  String get appLockAuthenticate => 'Autenticati per sbloccare FiFe.';

  @override
  String get appLockChangeSettings =>
      'Autenticati per modificare le impostazioni del blocco app.';

  @override
  String get appLockAuthHint => 'Verifica la tua identità';

  @override
  String get appLocked => 'FiFe è bloccato';

  @override
  String get appLockUnlock => 'Sblocca';

  @override
  String get appLockUnavailable =>
      'L’autenticazione del dispositivo non è disponibile. Configura un PIN, un codice o la biometria nelle impostazioni del dispositivo, poi riprova.';

  @override
  String get appLockAuthenticationFailed =>
      'L’autenticazione non è stata completata. Riprova.';

  @override
  String get appLockStorageError =>
      'Impossibile leggere o salvare le impostazioni di blocco. Riprova per proteggere la tua cassaforte.';

  @override
  String get quickSyncNotificationSettingTitle =>
      'Notifica di sincronizzazione automatica';

  @override
  String get autoSyncInterval => 'Intervallo di sincronizzazione automatica';

  @override
  String get autoSyncIntervalDescription =>
      'Sincronizza automaticamente mentre la notifica di sincronizzazione automatica è attiva.';

  @override
  String syncIntervalMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minuti',
      one: '1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get autoSyncIntervalSaveError =>
      'Impossibile salvare l’intervallo. Riprova.';

  @override
  String get autoSyncIntervalApplyError =>
      'Intervallo salvato. Disattiva e riattiva la notifica di sincronizzazione automatica per applicarlo.';

  @override
  String get sync => 'Sincronizza';

  @override
  String get quickSyncNotificationTitle => 'Servizio sincronizzazione file';

  @override
  String quickSyncNotificationText(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Esegui ogni $minutes minuti',
      one: 'Esegui ogni 1 minuto',
    );
    return '$_temp0';
  }

  @override
  String get quickSyncNotificationInProgress => 'In corso...';

  @override
  String get reportIssue => 'Segnala un problema';

  @override
  String get sourceCode => 'Codice sorgente';

  @override
  String get desktopApp => 'App desktop';

  @override
  String get mobileApp => 'App mobile';

  @override
  String get leaveReview => 'Lascia una recensione';

  @override
  String get share => 'Condividi';

  @override
  String get versionLabel => 'Versione: ';

  @override
  String get loading => 'Caricamento...';

  @override
  String get signOut => 'Esci';

  @override
  String get settingsPageTitle => 'Impostazioni';

  @override
  String get language => 'Lingua';

  @override
  String get tapToSelect => 'Tocca per selezionare';

  @override
  String get appTagline => 'Il tuo traghetto privato per i file';

  @override
  String get onboardingPurposeDescription =>
      'Un servizio di archiviazione cloud open source progettato con architettura zero-trust. I tuoi dati vengono crittografati localmente prima ancora di lasciare il dispositivo.';

  @override
  String get failedToFetch => 'Recupero non riuscito.';

  @override
  String get supportedStorageTitle => 'Archiviazioni supportate';

  @override
  String get supportedStorageDescription =>
      'Collega i tuoi provider preferiti. Inizia subito con 1 GB di spazio sicuro gratuito integrato in FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Avvia subito i backup';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Gratis';

  @override
  String get providerStorageDisclaimer =>
      '* Spazio gratuito come indicato sul sito del provider. Paghi solo ciò che usi con i provider compatibili.';

  @override
  String get whyUseFifeTitle => 'Perché usare FiFe?';

  @override
  String get claimFreeCloudStorageTitle => 'Ottieni spazio cloud gratuito';

  @override
  String get claimFreeCloudStorageDescription =>
      'Massimizza il tuo spazio collegando più provider cloud. Sfrutta in sicurezza i loro piani gratuiti in un’unica app.';

  @override
  String get topNotchSecurityTitle => 'Sicurezza di alto livello';

  @override
  String get topNotchSecurityDescription =>
      'Basato sulla crittografia avanzata Sodium. Tutta la crittografia e la decrittografia avvengono interamente in locale sul tuo dispositivo.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Mantieni il pieno controllo dei tuoi dati su tutti i provider di archiviazione cloud. Usa uno spazio crittografato con i tuoi account.';

  @override
  String get payAsYouGoStorageTitle => 'Paga solo ciò che usi per lo storage.';

  @override
  String get payAsYouGoStorageDescription =>
      'Paga solo lo spazio realmente usato con i provider compatibili. Nessun intermediario, nessun vincolo sui dati.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Privacy zero-knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'I tuoi dati vengono bloccati sul dispositivo prima ancora di essere inviati. Non possiamo vedere, leggere o analizzare i tuoi file.';

  @override
  String get localSelectionTitle => '1. Selezione locale';

  @override
  String get localSelectionDescription =>
      'Selezioni una cartella. Tutta l’elaborazione inizia in modo sicuro sul tuo dispositivo.';

  @override
  String get metadataEncryptionTitle => '2. Crittografia dei metadati';

  @override
  String get metadataEncryptionDescription =>
      'Le informazioni sui file, come nomi, tipi e dimensioni, vengono crittografate prima di essere inviate al server.';

  @override
  String get contentEncryptionTitle => '3. Crittografia del contenuto';

  @override
  String get contentEncryptionDescription =>
      'Il contenuto effettivo del file viene frammentato e crittografato prima del caricamento nel cloud.';

  @override
  String get blindServerTitle => '4. Server cieco';

  @override
  String get blindServerDescription =>
      'I nostri server non hanno alcuna conoscenza dei tuoi dati. Vedono solo blocchi crittografati, garantendo così la massima privacy.';

  @override
  String get dontTrustVerifyTitle => 'Non fidarti, verifica.';

  @override
  String get openSourceVerificationDescription =>
      '100% open source. Puoi ispezionare il codice per vedere esattamente come vengono crittografati i tuoi file.';

  @override
  String get getStarted => 'Inizia';

  @override
  String get next => 'Avanti';

  @override
  String get unauthorized => 'Non autorizzato';

  @override
  String get tryAgain => 'Riprova';

  @override
  String get errorTitle => 'Errore';

  @override
  String get failureTitle => 'Operazione non riuscita';

  @override
  String get invalidWordList => 'Elenco di parole non valido';

  @override
  String get invalidAccessKey => 'Chiave di accesso non valida';

  @override
  String get unexpectedDecryptionError =>
      'Si è verificato un errore imprevisto durante la decrittografia.';

  @override
  String get fileMustContainExactly24Words =>
      'Il file deve contenere esattamente 24 parole.';

  @override
  String get errorReadingFile => 'Errore durante la lettura del file';

  @override
  String get encryptionTitle => 'Crittografia';

  @override
  String get accessKeyDecodeDescription =>
      'Inserisci la tua frase di recupero di 24 parole oppure carica un file .txt per abilitare la sincronizzazione cloud in modo sicuro.';

  @override
  String get recoveryPhraseLabel => 'Frase di recupero';

  @override
  String get recoveryPhraseHint => 'parola1 parola2 parola3...';

  @override
  String get paste => 'Incolla';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 parole';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'Inserisci la tua frase di recupero';

  @override
  String get mustContainExactly24Words =>
      'Deve contenere esattamente 24 parole';

  @override
  String get verify => 'Verifica';

  @override
  String get orLabel => 'OPPURE';

  @override
  String get loadFromTxtFile => 'Carica da file .txt';

  @override
  String get saveAccessKey => 'Salva chiave di accesso';

  @override
  String get fileSavedSuccessfully => 'File salvato correttamente.';

  @override
  String get accessKeyShareMessage => 'Ecco la tua chiave di accesso.';

  @override
  String get pleaseTryAgain => 'Riprova.';

  @override
  String get copiedToClipboard => 'Copiato negli appunti';

  @override
  String get accessKeyTitle => 'Chiave di accesso';

  @override
  String get accessKeyDescription =>
      'Conserva questa chiave in un luogo sicuro. Solo questa chiave ti permetterà di accedere ai tuoi dati crittografati.';

  @override
  String get copy => 'Copia';

  @override
  String get downloadAsTextFile => 'Scarica come file di testo';

  @override
  String get continueLabel => 'Continua';

  @override
  String get importantTitle => 'Importante';

  @override
  String get accessKeyNoticePrimary =>
      'Nella pagina successiva vedrai una serie di 24 parole. Questa è la tua chiave di crittografia privata e unica ed è l’UNICO modo per recuperare i tuoi dati in caso di logout, smarrimento del dispositivo o malfunzionamento.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Noi non conserviamo questa chiave. È TUA responsabilità custodirla in un luogo sicuro, fuori dall’app $appName.';
  }

  @override
  String get showKeyConfirmation => 'Ho capito.\nMostrami la chiave.';

  @override
  String get storageAddedSuccessfully => 'Archiviazione aggiunta con successo';

  @override
  String get networkErrorDuringValidation =>
      'Si è verificato un errore di rete durante la convalida.';

  @override
  String get verifyAndConnect => 'Verifica e collega';

  @override
  String get requiredField => 'Obbligatorio';

  @override
  String get providerKeysVerifiedLocally =>
      'Le tue chiavi vengono verificate localmente e crittografate prima della trasmissione.';

  @override
  String get enterYourCredentials => 'Inserisci le tue credenziali';

  @override
  String connectProvider(String provider) {
    return 'Collega $provider';
  }

  @override
  String get deviceLimitReached => 'Limite dispositivi raggiunto';

  @override
  String get pleaseTryAgainWithExclamation => 'Riprova!';

  @override
  String get notThisDevice => 'Non questo dispositivo!';

  @override
  String get confirmSignoutDeviceTitle =>
      'Conferma disconnessione del dispositivo';

  @override
  String get areYouSure => 'Sei sicuro?';

  @override
  String get cancel => 'Annulla';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Nessun dispositivo trovato';

  @override
  String get backTooltip => 'Indietro';

  @override
  String get devicesTitle => 'Dispositivi';

  @override
  String get longPressToDownload => 'Tieni premuto per scaricare';

  @override
  String get fewItemsExistLocally =>
      'Alcuni elementi esistono ancora in locale.';

  @override
  String selectedItemsCount(int count) {
    return '$count selezionati';
  }

  @override
  String get delete => 'Elimina';

  @override
  String get info => 'Info';

  @override
  String get download => 'Scarica';

  @override
  String get archive => 'Archivia';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Log';

  @override
  String get settings => 'Impostazioni';

  @override
  String get trash => 'Cestino';

  @override
  String get storage => 'Archiviazione';

  @override
  String get search => 'Cerca';

  @override
  String get database => 'Database';

  @override
  String get addFolderTitle => 'Aggiungi cartella';

  @override
  String get confirm => 'Conferma';

  @override
  String get tapPlusToAddSyncFolder =>
      'Tocca + per aggiungere una cartella di sincronizzazione.';

  @override
  String get thisFolderIsEmpty => 'Questa cartella è vuota.';

  @override
  String get fileNotFound => 'File non trovato';

  @override
  String filePartsTitle(int count) {
    return 'Parti del file ($count)';
  }

  @override
  String get fileDetailsTitle => 'Dettagli file';

  @override
  String get encryptedBackup => 'Backup crittografato';

  @override
  String get sizeLabel => 'Dimensione';

  @override
  String get providerLabel => 'Provider';

  @override
  String get uploadedAtLabel => 'Caricato il';

  @override
  String get statusLabel => 'Stato';

  @override
  String get uploadedStatus => 'Caricato';

  @override
  String errorWithMessage(String message) {
    return 'Errore: $message';
  }

  @override
  String get noLogsAvailable => 'Nessun log disponibile';

  @override
  String get searchLogsHint => 'Cerca nei log...';

  @override
  String get clearLogs => 'Cancella log';

  @override
  String get searchWithMinThreeCharacters => 'Cerca con almeno 3 caratteri';

  @override
  String get typeBelowToSearch => 'Digita qui sotto per cercare';

  @override
  String get noResults => 'Nessun risultato.';

  @override
  String get welcomeTitle => 'Benvenuto';

  @override
  String signInToContinue(String appName) {
    return 'Accedi per continuare su $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Inserisci il tuo indirizzo email';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Inserisci un indirizzo email valido';

  @override
  String get emailAddressLabel => 'Indirizzo email';

  @override
  String get emailAddressHint => 'tua.email@esempio.com';

  @override
  String get retrySendingOtp => 'Invia di nuovo l’OTP';

  @override
  String get sendOtp => 'Invia OTP';

  @override
  String get checkYourEmail => 'Controlla la tua email';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Abbiamo inviato un codice di 6 cifre a\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Inserisci l’OTP';

  @override
  String get otpMustBeSixDigits => 'L’OTP deve essere di 6 cifre';

  @override
  String get enterOtpLabel => 'Inserisci OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Riprova la verifica';

  @override
  String get verifyOtp => 'Verifica OTP';

  @override
  String get useDifferentEmail => 'Usa un’altra email';

  @override
  String get alreadySignedIn => 'Hai già effettuato l’accesso';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Invio OTP non riuscito. Riprova!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Verifica OTP non riuscita. Riprova.';

  @override
  String get dbViewerTitle => 'Visualizzatore DB';

  @override
  String get selectTableToViewData =>
      'Seleziona una tabella per visualizzarne i dati';

  @override
  String get selectTable => 'Seleziona una tabella';

  @override
  String get permissionRequiredTitle => 'Autorizzazione richiesta';

  @override
  String get storagePermissionSettingsDescription =>
      'Per eseguire automaticamente il backup, gestire e proteggere i tuoi file in background, abbiamo bisogno dell’accesso alla memoria del dispositivo. I tuoi dati vengono crittografati localmente, garantendo la massima privacy. Consenti l’accesso per continuare.';

  @override
  String get openSettings => 'Apri impostazioni';

  @override
  String get secureLocalAccessTitle => 'Accesso locale sicuro';

  @override
  String get storagePermissionPageDescription =>
      'Per esplorare, crittografare ed eseguire il backup automatico dei tuoi file, abbiamo bisogno dell’accesso alla memoria del dispositivo.';

  @override
  String get verifying => 'Verifica in corso...';

  @override
  String get grantAccess => 'Concedi accesso';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Archiviazione crittografata zero-knowledge';

  @override
  String get notificationPermissionTitle => 'Accesso alle notifiche';

  @override
  String get notificationPermissionPageDescription =>
      'Per sincronizzare e caricare rapidamente i tuoi file in background dal pannello delle notifiche, abbiamo bisogno dell\'autorizzazione a mostrare notifiche. Puoi disattivarla in qualsiasi momento dalle impostazioni.';

  @override
  String get notificationPermissionGrantButton => 'Consenti notifiche';

  @override
  String get notificationPermissionSettingsDescription =>
      'Le notifiche sono necessarie per utilizzare la sincronizzazione rapida dal pannello delle notifiche. Abilitale nelle impostazioni di sistema per assicurarti che tutti i tuoi dati vengano caricati.';

  @override
  String requiresAppPro(String appName) {
    return 'Richiede $appName Pro.';
  }

  @override
  String get noStorageFound => 'Nessuna archiviazione trovata';

  @override
  String get howToConnect => 'Come collegarsi';

  @override
  String get modify => 'Modifica';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total utilizzati';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Fino a $size gratis';
  }

  @override
  String get notConnected => 'Non collegato';

  @override
  String get connect => 'Collega';

  @override
  String get modifyStorageCapacityTitle => 'Modifica capacità di archiviazione';

  @override
  String get enterNewStorageLimitForProvider =>
      'Inserisci il nuovo limite di archiviazione per questo provider.';

  @override
  String get sizePrefix => 'Dimensione: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Inserisci una dimensione';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Inserisci un numero valido maggiore di 1';

  @override
  String get submit => 'Invia';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Abbonamento a $appName Pro attivato con successo!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Acquisto annullato o non riuscito.';

  @override
  String get purchasesRestoredSuccessfully =>
      'Acquisti ripristinati con successo!';

  @override
  String get noActiveSubscriptionsFound => 'Nessun abbonamento attivo trovato.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Gestisci gli abbonamenti dalle impostazioni del dispositivo.';

  @override
  String get freePlanTitle => 'Gratis';

  @override
  String get freeForeverPrice => '\$0.00 / per sempre';

  @override
  String get freeBenefitProviderStorage =>
      'Approfitta dello spazio gratuito dei provider';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Sincronizza in sicurezza fino a 3 dispositivi';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Annuale';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Modifica il limite di archiviazione per ogni provider';

  @override
  String get proBenefitSyncTenDevices => 'Sincronizza fino a 10 dispositivi';

  @override
  String get restorePurchases => 'Ripristina acquisti';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* L’abbonamento è associato all’account email, non al dispositivo';

  @override
  String get subscriptionExpiredTitle => 'Abbonamento scaduto';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'I vantaggi di $appName Pro sono stati sospesi. Rinnova qui sotto per ripristinare i limiti di archiviazione e la sincronizzazione dei dispositivi.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro è attivo';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Modifica i limiti di archiviazione per ogni provider\n✓ Sincronizzazione tra dispositivi fino a 10 dispositivi';

  @override
  String get manageSubscription => 'Gestisci abbonamento';

  @override
  String get currentPlanBadge => 'ATTUALE';

  @override
  String get subscribeNow => 'Abbonati ora';

  @override
  String get subscribeOnMobileApp => 'Abbonati dall’app mobile';

  @override
  String get recover => 'Ripristina';

  @override
  String get empty => 'Svuota';

  @override
  String get noItems => 'Nessun elemento.';

  @override
  String get lostRecoveryPhrase => 'Frase di recupero persa';

  @override
  String get lostRecoveryIntro =>
      'Se un altro dispositivo è ancora connesso, esporta la frase di recupero da lì prima di ricominciare.';

  @override
  String get lostRecoveryDeleteConsequence =>
      'La cassaforte FiFe attuale, i file di backup e le vecchie chiavi di crittografia verranno eliminati definitivamente.';

  @override
  String get lostRecoveryDevicesConsequence =>
      'Tutte le registrazioni dei dispositivi esistenti verranno rimosse.';

  @override
  String get lostRecoveryLogoutConsequence =>
      'Gli altri dispositivi si disconnetteranno e cancelleranno i dati FiFe locali quando rileveranno la propria rimozione mentre sono online.';

  @override
  String get lostRecoveryKeepConsequence =>
      'Il tuo account e-mail, l\'abbonamento, le connessioni di archiviazione cloud e le credenziali dei provider verranno conservati. Verranno conservati anche i file nelle tue cartelle personali al di fuori di FiFe.';

  @override
  String get lostRecoveryWaitConsequence =>
      'La nuova cassaforte resterà bloccata finché l’eliminazione nel cloud non sarà verificata. Potrebbero volerci 15 minuti o più. Puoi chiudere FiFe e riprendere più tardi.';

  @override
  String get lostRecoveryNewPhraseConsequence =>
      'Resterai connesso su questo dispositivo. Dopo la verifica dell\'eliminazione, genera e salva una nuova frase di recupero di 24 parole.';

  @override
  String get recoveryResetUnavailable =>
      'Il ripristino del vault è temporaneamente non disponibile. Riprova più tardi.';

  @override
  String get recoveryResetSigninRequired =>
      'Accedi di nuovo per verificare la sessione prima di reimpostare la cassaforte.';

  @override
  String get recoveryResetContinue => 'Continua con il ripristino';

  @override
  String get recoveryResetConfirmTitle =>
      'Eliminare definitivamente la cassaforte FiFe?';

  @override
  String get recoveryResetConfirmBody =>
      'L’operazione è irreversibile. La frase di recupero attuale smetterà di funzionare e tutti i tuoi dispositivi verranno rimossi.';

  @override
  String get recoveryResetDelete => 'Elimina la cassaforte e ricomincia';

  @override
  String get recoveryResetPendingTitle =>
      'Eliminazione della cassaforte precedente';

  @override
  String get recoveryResetPendingBody =>
      'FiFe sta verificando l’eliminazione nel cloud. Puoi chiudere l’app e tornare più tardi.';

  @override
  String recoveryResetWaitUntil(String when) {
    return 'La verifica non può terminare prima di $when.';
  }

  @override
  String get recoveryResetStorageBlocked =>
      'L’eliminazione nel cloud richiede un intervento. Ripristina l’accesso e le autorizzazioni di eliminazione per gli archivi collegati, poi riprova.';

  @override
  String get recoveryResetSignin =>
      'Accedi di nuovo per riprendere questo ripristino.';

  @override
  String recoveryResetSigninAs(String email) {
    return 'Accedi come $email per riprendere questo ripristino.';
  }

  @override
  String get recoveryResetNeedsConfirmation =>
      'Conferma il ripristino per continuare. FiFe controllerà se è già iniziato.';

  @override
  String get recoveryResetConfirmationWait =>
      'Una conferma precedente è ancora valida. Ricontrolla dopo la scadenza prima di avviare una nuova conferma.';

  @override
  String recoveryResetConfirmationUntil(String when) {
    return 'Ricontrolla dopo $when.';
  }

  @override
  String get recoveryResetMissingKeys =>
      'Le nuove chiavi di recupero non sono disponibili su questo dispositivo. Continua sul dispositivo che ha avviato il ripristino. Se le chiavi sono state perse, attendi la fine dell’eliminazione, accedi e scegli di nuovo «Frase di recupero persa».';

  @override
  String get recoveryResetDiscard => 'Torna all’accesso';

  @override
  String get recoveryResetDiscardBody =>
      'Questa operazione cancella la configurazione di recupero incompleta su questo dispositivo. Dopo l’accesso servirà la nuova frase di recupero o un altro ripristino della cassaforte.';

  @override
  String get recoveryPhraseSaved => 'Ho salvato la nuova frase di recupero.';

  @override
  String get recoveryResetStarting => 'Avvio del ripristino…';

  @override
  String get sessionExpiredRetained =>
      'La sessione è scaduta. Accedi di nuovo per sbloccare il tuo archivio. I dati locali vengono conservati.';

  @override
  String get signinVerifiedContinue =>
      'La tua email è verificata. Continua per completare l’accesso.';

  @override
  String get noSupportedApplication =>
      'Nessuna applicazione compatibile per visualizzare questo file.';

  @override
  String get fileAccessUnavailable =>
      'Impossibile accedere a questo file. Controlla le autorizzazioni della cartella e riprova.';

  @override
  String get unableToOpenFile => 'Impossibile aprire questo file. Riprova.';

  @override
  String get fileNotAvailable =>
      'Questo file non è disponibile sul dispositivo né in un backup completato.';

  @override
  String get downloadRecoveryPhrase => 'Scarica la frase di recupero';

  @override
  String get recoveryPhraseExportHint =>
      'Autenticati per visualizzare, copiare o salvare la frase di recupero.';

  @override
  String get recoveryPhraseExportAuth =>
      'Autenticati per visualizzare la frase di recupero';

  @override
  String get recoveryPhraseExportWarning =>
      'Chiunque abbia queste parole può sbloccare la tua cassaforte. Conserva la tua copia in un luogo privato, fuori da FiFe.';

  @override
  String get recoveryPhraseUnavailable =>
      'Impossibile caricare la frase di recupero. Riprova oppure usa il backup salvato o un altro dispositivo su cui hai effettuato l’accesso.';

  @override
  String get reconnect => 'Riconnetti';

  @override
  String get archiveBackup => 'Archivia backup';

  @override
  String get archiveFolderBackupMessage =>
      'Spostare i backup delle cartelle selezionate nel Cestino e rimuovere le copie scaricate da FiFe? I file originali e le altre cartelle verranno conservati. Questi percorsi resteranno esclusi dalla sincronizzazione finché non li ripristini dal Cestino.';
}
