// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get localSessionCleanupTitle => 'Suppression des données locales';

  @override
  String get localSessionCleanupDescription =>
      'Votre session est terminée. FiFe doit terminer la suppression des données locales du compte avant votre prochaine connexion. Vos fichiers originaux sont conservés. Réessayez pour terminer.';

  @override
  String get localSessionCleanupInProgress =>
      'Suppression des données FiFe de cet appareil…';

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'En continuant, vous acceptez nos $terms et notre $privacy.';
  }

  @override
  String get termsOfService => 'Conditions d’utilisation';

  @override
  String get privacyPolicy => 'Politique de confidentialité';

  @override
  String get andLabel => ' et ';

  @override
  String get theme => 'Thème';

  @override
  String get themeTooltip => 'Thème jour/nuit';

  @override
  String get logging => 'Journaux';

  @override
  String get appLockTitle => 'Verrouillage de l’app';

  @override
  String get appLockDescription =>
      'Protégez FiFe avec l’empreinte, le visage ou le code PIN de votre appareil.';

  @override
  String get appLockTimeout => 'Délai de verrouillage';

  @override
  String get appLockTimeoutDescription =>
      'Exiger une authentification après ce temps passé hors de FiFe. Chaque redémarrage de l’app exige une authentification.';

  @override
  String get appLockAuthenticate =>
      'Authentifiez-vous pour déverrouiller FiFe.';

  @override
  String get appLockChangeSettings =>
      'Authentifiez-vous pour modifier le verrouillage de l’app.';

  @override
  String get appLockAuthHint => 'Vérifiez votre identité';

  @override
  String get appLocked => 'FiFe est verrouillé';

  @override
  String get appLockUnlock => 'Déverrouiller';

  @override
  String get appLockUnavailable =>
      'L’authentification de l’appareil est indisponible. Configurez un code PIN, un code d’accès ou la biométrie dans les réglages de l’appareil, puis réessayez.';

  @override
  String get appLockAuthenticationFailed =>
      'L’authentification n’a pas été effectuée. Réessayez.';

  @override
  String get appLockStorageError =>
      'Impossible de lire ou d’enregistrer les réglages de verrouillage. Réessayez pour protéger votre coffre.';

  @override
  String get quickSyncNotificationSettingTitle =>
      'Notification de synchronisation automatique';

  @override
  String get autoSyncInterval => 'Intervalle de synchronisation automatique';

  @override
  String get autoSyncIntervalDescription =>
      'Synchronise automatiquement lorsque la notification de synchronisation automatique est activée.';

  @override
  String syncIntervalMinutes(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutes minutes',
      one: '1 minute',
    );
    return '$_temp0';
  }

  @override
  String get autoSyncIntervalSaveError =>
      'Impossible d’enregistrer l’intervalle. Réessayez.';

  @override
  String get autoSyncIntervalApplyError =>
      'Intervalle enregistré. Désactivez puis réactivez la notification de synchronisation automatique pour l’appliquer.';

  @override
  String get sync => 'Synchroniser';

  @override
  String get quickSyncNotificationTitle =>
      'Service de synchronisation des fichiers';

  @override
  String quickSyncNotificationText(int minutes) {
    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: 'Exécuter toutes les $minutes minutes',
      one: 'Exécuter toutes les minutes',
    );
    return '$_temp0';
  }

  @override
  String get quickSyncNotificationInProgress => 'En cours...';

  @override
  String get reportIssue => 'Signaler un problème';

  @override
  String get sourceCode => 'Code source';

  @override
  String get desktopApp => 'Application de bureau';

  @override
  String get mobileApp => 'Application mobile';

  @override
  String get leaveReview => 'Laisser un avis';

  @override
  String get share => 'Partager';

  @override
  String get versionLabel => 'Version : ';

  @override
  String get loading => 'Chargement...';

  @override
  String get signOut => 'Se déconnecter';

  @override
  String get settingsPageTitle => 'Paramètres';

  @override
  String get language => 'Langue';

  @override
  String get tapToSelect => 'Appuyez pour choisir';

  @override
  String get appTagline => 'Votre passeur privé de fichiers';

  @override
  String get onboardingPurposeDescription =>
      'Un service de stockage cloud open source conçu avec une architecture zero-trust. Vos données sont chiffrées localement avant même de quitter votre appareil.';

  @override
  String get failedToFetch => 'Échec du chargement.';

  @override
  String get supportedStorageTitle => 'Stockages pris en charge';

  @override
  String get supportedStorageDescription =>
      'Connectez vos fournisseurs préférés. Commencez tout de suite avec 1 Go de stockage sécurisé gratuit intégré à FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Commencez vos sauvegardes immédiatement';

  @override
  String get freeStorageSizeOneGb => '1.0 Go';

  @override
  String get freeLabel => 'Gratuit';

  @override
  String get providerStorageDisclaimer =>
      '* Stockage gratuit selon les informations indiquées sur le site du fournisseur. Paiement à l’usage avec les fournisseurs compatibles.';

  @override
  String get whyUseFifeTitle => 'Pourquoi utiliser FiFe ?';

  @override
  String get claimFreeCloudStorageTitle => 'Profitez du stockage cloud gratuit';

  @override
  String get claimFreeCloudStorageDescription =>
      'Optimisez votre espace en connectant plusieurs fournisseurs cloud. Profitez en toute sécurité de leurs offres gratuites dans une seule application unifiée.';

  @override
  String get topNotchSecurityTitle => 'Sécurité de haut niveau';

  @override
  String get topNotchSecurityDescription =>
      'Propulsé par la cryptographie avancée Sodium. Tout le chiffrement et le déchiffrement se font entièrement en local sur votre appareil.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Gardez un contrôle total sur vos données chez tous les fournisseurs de stockage cloud. Conservez un stockage chiffré avec vos propres comptes.';

  @override
  String get payAsYouGoStorageTitle => 'Paiement à l’usage pour le stockage.';

  @override
  String get payAsYouGoStorageDescription =>
      'Payez uniquement l’espace réellement utilisé avec les fournisseurs compatibles. Sans intermédiaire, sans enfermement des données.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Confidentialité zero-knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Vos données sont verrouillées sur votre appareil avant même d’être envoyées. Nous ne pouvons ni voir, ni lire, ni analyser vos fichiers.';

  @override
  String get localSelectionTitle => '1. Sélection locale';

  @override
  String get localSelectionDescription =>
      'Vous sélectionnez un dossier. Tout le traitement commence de manière sécurisée sur votre appareil.';

  @override
  String get metadataEncryptionTitle => '2. Chiffrement des métadonnées';

  @override
  String get metadataEncryptionDescription =>
      'Les informations sur les fichiers (noms, types et tailles) sont chiffrées avant d’être envoyées au serveur.';

  @override
  String get contentEncryptionTitle => '3. Chiffrement du contenu';

  @override
  String get contentEncryptionDescription =>
      'Le contenu réel du fichier est fragmenté et chiffré avant son envoi vers le stockage cloud.';

  @override
  String get blindServerTitle => '4. Serveur aveugle';

  @override
  String get blindServerDescription =>
      'Nos serveurs n’ont aucune connaissance de vos données. Nous ne voyons que des blocs chiffrés, ce qui garantit une confidentialité absolue.';

  @override
  String get dontTrustVerifyTitle => 'Ne faites pas confiance, vérifiez.';

  @override
  String get openSourceVerificationDescription =>
      '100 % open source. Vous pouvez inspecter le code pour voir exactement comment vos fichiers sont chiffrés.';

  @override
  String get getStarted => 'Commencer';

  @override
  String get next => 'Suivant';

  @override
  String get unauthorized => 'Non autorisé';

  @override
  String get tryAgain => 'Réessayer';

  @override
  String get errorTitle => 'Erreur';

  @override
  String get failureTitle => 'Échec';

  @override
  String get invalidWordList => 'Liste de mots invalide';

  @override
  String get invalidAccessKey => 'Clé d’accès invalide';

  @override
  String get unexpectedDecryptionError =>
      'Une erreur inattendue s’est produite pendant le déchiffrement.';

  @override
  String get fileMustContainExactly24Words =>
      'Le fichier doit contenir exactement 24 mots.';

  @override
  String get errorReadingFile => 'Erreur lors de la lecture du fichier';

  @override
  String get encryptionTitle => 'Chiffrement';

  @override
  String get accessKeyDecodeDescription =>
      'Saisissez votre phrase de récupération de 24 mots ou chargez un fichier .txt pour activer la synchronisation cloud de manière sécurisée.';

  @override
  String get recoveryPhraseLabel => 'Phrase de récupération';

  @override
  String get recoveryPhraseHint => 'mot1 mot2 mot3...';

  @override
  String get paste => 'Coller';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 mots';
  }

  @override
  String get pleaseEnterRecoveryPhrase =>
      'Veuillez saisir votre phrase de récupération';

  @override
  String get mustContainExactly24Words => 'Doit contenir exactement 24 mots';

  @override
  String get verify => 'Vérifier';

  @override
  String get orLabel => 'OU';

  @override
  String get loadFromTxtFile => 'Charger depuis un fichier .txt';

  @override
  String get saveAccessKey => 'Enregistrer la clé d’accès';

  @override
  String get fileSavedSuccessfully => 'Fichier enregistré avec succès.';

  @override
  String get accessKeyShareMessage => 'Voici votre clé d’accès.';

  @override
  String get pleaseTryAgain => 'Veuillez réessayer.';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get accessKeyTitle => 'Clé d’accès';

  @override
  String get accessKeyDescription =>
      'Veuillez enregistrer cette clé dans un endroit sûr. Elle est le seul moyen d’accéder à vos données chiffrées.';

  @override
  String get copy => 'Copier';

  @override
  String get downloadAsTextFile => 'Télécharger en fichier texte';

  @override
  String get continueLabel => 'Continuer';

  @override
  String get importantTitle => 'Important';

  @override
  String get accessKeyNoticePrimary =>
      'Sur la page suivante, vous verrez une série de 24 mots. Il s’agit de votre clé de chiffrement unique et privée, et c’est le SEUL moyen de récupérer vos données en cas de déconnexion, de perte de l’appareil ou de dysfonctionnement.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Nous ne stockons pas cette clé. C’est à VOUS de la conserver dans un endroit sûr, en dehors de l’application $appName.';
  }

  @override
  String get showKeyConfirmation => 'J’ai compris.\nMontrez-moi la clé.';

  @override
  String get storageAddedSuccessfully => 'Stockage ajouté avec succès';

  @override
  String get networkErrorDuringValidation =>
      'Une erreur réseau s’est produite pendant la validation.';

  @override
  String get verifyAndConnect => 'Vérifier et connecter';

  @override
  String get requiredField => 'Obligatoire';

  @override
  String get providerKeysVerifiedLocally =>
      'Vos clés sont vérifiées localement et chiffrées avant transmission.';

  @override
  String get enterYourCredentials => 'Saisissez vos identifiants';

  @override
  String connectProvider(String provider) {
    return 'Connecter $provider';
  }

  @override
  String get deviceLimitReached => 'Limite d’appareils atteinte';

  @override
  String get pleaseTryAgainWithExclamation => 'Veuillez réessayer !';

  @override
  String get notThisDevice => 'Pas cet appareil !';

  @override
  String get confirmSignoutDeviceTitle =>
      'Confirmer la déconnexion de l’appareil';

  @override
  String get areYouSure => 'Êtes-vous sûr ?';

  @override
  String get cancel => 'Annuler';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Aucun appareil trouvé';

  @override
  String get backTooltip => 'Retour';

  @override
  String get devicesTitle => 'Appareils';

  @override
  String get longPressToDownload => 'Appui long pour télécharger';

  @override
  String get fewItemsExistLocally =>
      'Certains éléments existent encore localement.';

  @override
  String selectedItemsCount(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get delete => 'Supprimer';

  @override
  String get info => 'Infos';

  @override
  String get download => 'Télécharger';

  @override
  String get archive => 'Archiver';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Journaux';

  @override
  String get settings => 'Paramètres';

  @override
  String get trash => 'Corbeille';

  @override
  String get storage => 'Stockage';

  @override
  String get search => 'Recherche';

  @override
  String get database => 'Base de données';

  @override
  String get addFolderTitle => 'Ajouter un dossier';

  @override
  String get confirm => 'Confirmer';

  @override
  String get tapPlusToAddSyncFolder =>
      'Appuyez sur + pour ajouter un dossier de synchronisation.';

  @override
  String get thisFolderIsEmpty => 'Ce dossier est vide.';

  @override
  String get fileNotFound => 'Fichier introuvable';

  @override
  String filePartsTitle(int count) {
    return 'Parties du fichier ($count)';
  }

  @override
  String get fileDetailsTitle => 'Détails du fichier';

  @override
  String get encryptedBackup => 'Sauvegarde chiffrée';

  @override
  String get sizeLabel => 'Taille';

  @override
  String get providerLabel => 'Fournisseur';

  @override
  String get uploadedAtLabel => 'Téléversé le';

  @override
  String get statusLabel => 'Statut';

  @override
  String get uploadedStatus => 'Téléversé';

  @override
  String errorWithMessage(String message) {
    return 'Erreur : $message';
  }

  @override
  String get noLogsAvailable => 'Aucun journal disponible';

  @override
  String get searchLogsHint => 'Rechercher dans les journaux...';

  @override
  String get clearLogs => 'Effacer les journaux';

  @override
  String get searchWithMinThreeCharacters =>
      'Recherchez avec au moins 3 caractères';

  @override
  String get typeBelowToSearch => 'Saisissez ci-dessous pour rechercher';

  @override
  String get noResults => 'Aucun résultat.';

  @override
  String get welcomeTitle => 'Bienvenue';

  @override
  String signInToContinue(String appName) {
    return 'Connectez-vous pour continuer vers $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Veuillez saisir votre adresse e-mail';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Veuillez saisir une adresse e-mail valide';

  @override
  String get emailAddressLabel => 'Adresse e-mail';

  @override
  String get emailAddressHint => 'votre.email@exemple.com';

  @override
  String get retrySendingOtp => 'Renvoyer l’OTP';

  @override
  String get sendOtp => 'Envoyer l’OTP';

  @override
  String get checkYourEmail => 'Vérifiez votre e-mail';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Nous avons envoyé un code à 6 chiffres à\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Veuillez saisir l’OTP';

  @override
  String get otpMustBeSixDigits => 'L’OTP doit contenir 6 chiffres';

  @override
  String get enterOtpLabel => 'Saisir l’OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Réessayer la vérification';

  @override
  String get verifyOtp => 'Vérifier l’OTP';

  @override
  String get useDifferentEmail => 'Utiliser une autre adresse e-mail';

  @override
  String get alreadySignedIn => 'Déjà connecté';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Échec de l’envoi de l’OTP. Veuillez réessayer !';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Échec de la vérification de l’OTP. Veuillez réessayer.';

  @override
  String get dbViewerTitle => 'Visionneuse de base de données';

  @override
  String get selectTableToViewData =>
      'Sélectionnez une table pour afficher ses données';

  @override
  String get selectTable => 'Sélectionner une table';

  @override
  String get permissionRequiredTitle => 'Autorisation requise';

  @override
  String get storagePermissionSettingsDescription =>
      'Pour sauvegarder, gérer et sécuriser automatiquement vos fichiers en arrière-plan, nous avons besoin d’accéder au stockage de votre appareil. Vos données sont chiffrées localement, ce qui garantit une confidentialité totale. Veuillez autoriser l’accès pour continuer.';

  @override
  String get openSettings => 'Ouvrir les paramètres';

  @override
  String get secureLocalAccessTitle => 'Accès local sécurisé';

  @override
  String get storagePermissionPageDescription =>
      'Pour parcourir, chiffrer et sauvegarder automatiquement vos fichiers, nous avons besoin d’accéder au stockage de votre appareil.';

  @override
  String get verifying => 'Vérification...';

  @override
  String get grantAccess => 'Autoriser l’accès';

  @override
  String get zeroKnowledgeEncryptedStorage => 'Stockage chiffré zero-knowledge';

  @override
  String get notificationPermissionTitle => 'Accès aux Notifications';

  @override
  String get notificationPermissionPageDescription =>
      'Pour synchroniser et envoyer rapidement vos fichiers en arrière-plan depuis le panneau de notifications, nous avons besoin de l\'autorisation d\'afficher des notifications. Vous pourrez la désactiver à tout moment dans les paramètres.';

  @override
  String get notificationPermissionGrantButton => 'Autoriser les Notifications';

  @override
  String get notificationPermissionSettingsDescription =>
      'Les notifications sont nécessaires pour utiliser la synchronisation rapide depuis le panneau de notifications. Veuillez les activer dans les paramètres du système afin de garantir le téléversement complet de vos données.';

  @override
  String requiresAppPro(String appName) {
    return 'Nécessite $appName Pro.';
  }

  @override
  String get noStorageFound => 'Aucun stockage trouvé';

  @override
  String get howToConnect => 'Comment se connecter';

  @override
  String get modify => 'Modifier';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total utilisés';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Jusqu’à $size gratuits';
  }

  @override
  String get notConnected => 'Non connecté';

  @override
  String get connect => 'Connecter';

  @override
  String get modifyStorageCapacityTitle => 'Modifier la capacité de stockage';

  @override
  String get enterNewStorageLimitForProvider =>
      'Saisissez la nouvelle limite de stockage pour ce fournisseur.';

  @override
  String get sizePrefix => 'Taille : ';

  @override
  String get gbSuffix => ' Go';

  @override
  String get pleaseEnterSize => 'Veuillez saisir une taille';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Saisissez un nombre valide supérieur à 1';

  @override
  String get submit => 'Valider';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Abonnement à $appName Pro effectué avec succès !';
  }

  @override
  String get purchaseCancelledOrFailed => 'Achat annulé ou échoué.';

  @override
  String get purchasesRestoredSuccessfully => 'Achats restaurés avec succès !';

  @override
  String get noActiveSubscriptionsFound => 'Aucun abonnement actif trouvé.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Veuillez gérer vos abonnements dans les paramètres de votre appareil.';

  @override
  String get freePlanTitle => 'Gratuit';

  @override
  String get freeForeverPrice => '\$0.00 / à vie';

  @override
  String get freeBenefitProviderStorage =>
      'Profitez du stockage gratuit des fournisseurs';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Synchronisez jusqu’à 3 appareils en toute sécurité';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Annuel';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Modifier la limite de stockage de chaque fournisseur';

  @override
  String get proBenefitSyncTenDevices => 'Synchronisez jusqu’à 10 appareils';

  @override
  String get restorePurchases => 'Restaurer les achats';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* L’abonnement est associé au compte e-mail, pas à l’appareil';

  @override
  String get subscriptionExpiredTitle => 'Abonnement expiré';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Vos avantages $appName Pro sont suspendus. Renouvelez ci-dessous pour rétablir vos limites de stockage et la synchronisation de vos appareils.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro est actif';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Modifier les limites de stockage pour chaque fournisseur\n✓ Synchronisation multi-appareils jusqu’à 10 appareils';

  @override
  String get manageSubscription => 'Gérer l’abonnement';

  @override
  String get currentPlanBadge => 'ACTUEL';

  @override
  String get subscribeNow => 'S’abonner maintenant';

  @override
  String get subscribeOnMobileApp => 'S’abonner depuis l’application mobile';

  @override
  String get recover => 'Restaurer';

  @override
  String get empty => 'Vider';

  @override
  String get noItems => 'Aucun élément.';

  @override
  String get lostRecoveryPhrase => 'Phrase de récupération perdue';

  @override
  String get lostRecoveryIntro =>
      'Si un autre appareil est encore connecté, exportez votre phrase de récupération depuis celui-ci avant de repartir de zéro.';

  @override
  String get lostRecoveryDeleteConsequence =>
      'Votre coffre FiFe actuel, vos fichiers sauvegardés et vos anciennes clés de chiffrement seront définitivement supprimés.';

  @override
  String get lostRecoveryDevicesConsequence =>
      'Tous les enregistrements d’appareils existants seront supprimés.';

  @override
  String get lostRecoveryLogoutConsequence =>
      'Les autres appareils se déconnecteront et effaceront leurs données FiFe locales lorsqu’ils détecteront leur suppression en ligne.';

  @override
  String get lostRecoveryKeepConsequence =>
      'Votre compte e-mail, votre abonnement, vos connexions au stockage cloud et les identifiants des fournisseurs seront conservés. Les fichiers de vos propres dossiers en dehors de FiFe seront également conservés.';

  @override
  String get lostRecoveryWaitConsequence =>
      'Votre nouveau coffre restera verrouillé jusqu’à la vérification de la suppression dans le cloud. Cela peut prendre 15 minutes ou plus. Vous pouvez fermer FiFe et reprendre plus tard.';

  @override
  String get lostRecoveryNewPhraseConsequence =>
      'Vous resterez connecté sur cet appareil. Une fois la suppression vérifiée, générez et enregistrez une nouvelle phrase de récupération de 24 mots.';

  @override
  String get recoveryResetUnavailable =>
      'La réinitialisation du coffre est temporairement indisponible. Réessayez plus tard.';

  @override
  String get recoveryResetSigninRequired =>
      'Reconnectez-vous pour vérifier votre session avant de réinitialiser le coffre.';

  @override
  String get recoveryResetContinue => 'Poursuivre la réinitialisation';

  @override
  String get recoveryResetConfirmTitle =>
      'Supprimer définitivement votre coffre FiFe ?';

  @override
  String get recoveryResetConfirmBody =>
      'Cette action est irréversible. Votre phrase de récupération actuelle cessera de fonctionner et tous vos appareils seront supprimés.';

  @override
  String get recoveryResetDelete => 'Supprimer le coffre et repartir de zéro';

  @override
  String get recoveryResetPendingTitle => 'Suppression de votre ancien coffre';

  @override
  String get recoveryResetPendingBody =>
      'FiFe vérifie la suppression dans le cloud. Vous pouvez fermer l’app et revenir plus tard.';

  @override
  String recoveryResetWaitUntil(String when) {
    return 'La vérification ne peut pas se terminer avant $when.';
  }

  @override
  String get recoveryResetStorageBlocked =>
      'La suppression dans le cloud nécessite votre intervention. Rétablissez l’accès et les autorisations de suppression du stockage lié, puis réessayez.';

  @override
  String get recoveryResetSignin =>
      'Reconnectez-vous pour reprendre cette réinitialisation.';

  @override
  String recoveryResetSigninAs(String email) {
    return 'Connectez-vous avec $email pour reprendre cette réinitialisation.';
  }

  @override
  String get recoveryResetNeedsConfirmation =>
      'Confirmez la réinitialisation pour continuer. FiFe vérifiera si elle a déjà commencé.';

  @override
  String get recoveryResetConfirmationWait =>
      'Une confirmation précédente est encore valide. Vérifiez après son expiration avant de lancer une nouvelle confirmation.';

  @override
  String recoveryResetConfirmationUntil(String when) {
    return 'Vérifiez à nouveau après $when.';
  }

  @override
  String get recoveryResetMissingKeys =>
      'Les nouvelles clés de récupération ne sont pas disponibles sur cet appareil. Continuez sur l’appareil qui a lancé la réinitialisation. Si ces clés sont perdues, attendez la fin de la suppression, connectez-vous et choisissez à nouveau « Phrase de récupération perdue ».';

  @override
  String get recoveryResetDiscard => 'Revenir à la connexion';

  @override
  String get recoveryResetDiscardBody =>
      'Cela efface la configuration de récupération inachevée sur cet appareil. Après connexion, il vous faudra la nouvelle phrase de récupération ou réinitialiser à nouveau le coffre.';

  @override
  String get recoveryPhraseSaved =>
      'J’ai enregistré ma nouvelle phrase de récupération.';

  @override
  String get recoveryResetStarting => 'Démarrage de la réinitialisation…';
}
