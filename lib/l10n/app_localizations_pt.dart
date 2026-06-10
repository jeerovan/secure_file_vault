// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Ao continuar, concorda com os nossos $terms e a nossa $privacy.';
  }

  @override
  String get termsOfService => 'Termos de Serviço';

  @override
  String get privacyPolicy => 'Política de Privacidade';

  @override
  String get andLabel => ' e ';

  @override
  String get theme => 'Tema';

  @override
  String get themeTooltip => 'Tema claro/escuro';

  @override
  String get logging => 'Registos';

  @override
  String get reportIssue => 'Reportar problema';

  @override
  String get sourceCode => 'Código-fonte';

  @override
  String get desktopApp => 'Aplicação para computador';

  @override
  String get mobileApp => 'Aplicação móvel';

  @override
  String get leaveReview => 'Deixar uma avaliação';

  @override
  String get share => 'Partilhar';

  @override
  String get versionLabel => 'Versão: ';

  @override
  String get loading => 'A carregar...';

  @override
  String get signOut => 'Terminar sessão';

  @override
  String get settingsPageTitle => 'Definições';

  @override
  String get language => 'Idioma';

  @override
  String get tapToSelect => 'Toque para selecionar';

  @override
  String get appTagline => 'O seu ferry privado para ficheiros';

  @override
  String get onboardingPurposeDescription =>
      'Um serviço de armazenamento na cloud open-source, criado com arquitetura zero-trust. Os seus dados são encriptados localmente antes de saírem do seu dispositivo.';

  @override
  String get failedToFetch => 'Falha ao obter dados.';

  @override
  String get supportedStorageTitle => 'Armazenamento suportado';

  @override
  String get supportedStorageDescription =>
      'Ligue os seus fornecedores favoritos. Comece já com 1 GB de armazenamento seguro gratuito incluído no FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly => 'Comece já a fazer cópias de segurança';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Grátis';

  @override
  String get providerStorageDisclaimer =>
      '* Armazenamento gratuito conforme indicado no site do fornecedor. Pagamento conforme a utilização com fornecedores compatíveis.';

  @override
  String get whyUseFifeTitle => 'Porquê usar o FiFe?';

  @override
  String get claimFreeCloudStorageTitle =>
      'Aproveite armazenamento cloud gratuito';

  @override
  String get claimFreeCloudStorageDescription =>
      'Aumente o seu espaço ao ligar vários fornecedores de cloud. Aproveite os seus planos gratuitos de forma segura numa única aplicação.';

  @override
  String get topNotchSecurityTitle => 'Segurança de topo';

  @override
  String get topNotchSecurityDescription =>
      'Com tecnologia de criptografia Sodium avançada. Toda a encriptação e desencriptação acontece localmente no seu dispositivo.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Mantenha controlo total sobre os seus dados em todos os fornecedores de armazenamento cloud. Guarde os dados encriptados nas suas próprias contas.';

  @override
  String get payAsYouGoStorageTitle => 'Pague apenas o armazenamento que usa.';

  @override
  String get payAsYouGoStorageDescription =>
      'Pague apenas pelo armazenamento utilizado com fornecedores compatíveis. Sem intermediários, sem dependência de plataforma.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Privacidade zero-knowledge';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Os seus dados ficam protegidos no seu dispositivo antes de saírem dele. Não conseguimos ver, ler nem analisar os seus ficheiros.';

  @override
  String get localSelectionTitle => '1. Seleção local';

  @override
  String get localSelectionDescription =>
      'Seleciona uma pasta. Todo o processamento começa de forma segura no seu dispositivo.';

  @override
  String get metadataEncryptionTitle => '2. Encriptação dos metadados';

  @override
  String get metadataEncryptionDescription =>
      'As informações dos ficheiros, como nomes, tipos e tamanhos, são encriptadas antes de serem enviadas para o servidor.';

  @override
  String get contentEncryptionTitle => '3. Encriptação do conteúdo';

  @override
  String get contentEncryptionDescription =>
      'O conteúdo real do ficheiro é fragmentado e encriptado antes do envio para o armazenamento cloud.';

  @override
  String get blindServerTitle => '4. Servidor cego';

  @override
  String get blindServerDescription =>
      'Os nossos servidores não têm conhecimento do conteúdo. Apenas veem blocos encriptados, garantindo privacidade total.';

  @override
  String get dontTrustVerifyTitle => 'Não confie apenas, verifique.';

  @override
  String get openSourceVerificationDescription =>
      '100% open source. Pode inspecionar o código para ver exatamente como os seus ficheiros são encriptados.';

  @override
  String get getStarted => 'Começar';

  @override
  String get next => 'Seguinte';

  @override
  String get unauthorized => 'Não autorizado';

  @override
  String get tryAgain => 'Tentar novamente';

  @override
  String get errorTitle => 'Erro';

  @override
  String get failureTitle => 'Falha';

  @override
  String get invalidWordList => 'Lista de palavras inválida';

  @override
  String get invalidAccessKey => 'Chave de acesso inválida';

  @override
  String get unexpectedDecryptionError =>
      'Ocorreu um erro inesperado durante a desencriptação.';

  @override
  String get fileMustContainExactly24Words =>
      'O ficheiro tem de conter exatamente 24 palavras.';

  @override
  String get errorReadingFile => 'Erro ao ler o ficheiro';

  @override
  String get encryptionTitle => 'Encriptação';

  @override
  String get accessKeyDecodeDescription =>
      'Introduza a sua frase de recuperação de 24 palavras ou carregue um ficheiro .txt para ativar a sincronização com a cloud em segurança.';

  @override
  String get recoveryPhraseLabel => 'Frase de recuperação';

  @override
  String get recoveryPhraseHint => 'palavra1 palavra2 palavra3...';

  @override
  String get paste => 'Colar';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 palavras';
  }

  @override
  String get pleaseEnterRecoveryPhrase =>
      'Introduza a sua frase de recuperação';

  @override
  String get mustContainExactly24Words =>
      'Tem de conter exatamente 24 palavras';

  @override
  String get verify => 'Verificar';

  @override
  String get orLabel => 'OU';

  @override
  String get loadFromTxtFile => 'Carregar de ficheiro .txt';

  @override
  String get saveAccessKey => 'Guardar chave de acesso';

  @override
  String get fileSavedSuccessfully => 'Ficheiro guardado com sucesso.';

  @override
  String get accessKeyShareMessage => 'Aqui está a sua chave de acesso.';

  @override
  String get pleaseTryAgain => 'Tente novamente.';

  @override
  String get copiedToClipboard => 'Copiado para a área de transferência';

  @override
  String get accessKeyTitle => 'Chave de acesso';

  @override
  String get accessKeyDescription =>
      'Guarde esta chave num local seguro. Só ela lhe permitirá aceder aos seus dados encriptados.';

  @override
  String get copy => 'Copiar';

  @override
  String get downloadAsTextFile => 'Transferir como ficheiro de texto';

  @override
  String get continueLabel => 'Continuar';

  @override
  String get importantTitle => 'Importante';

  @override
  String get accessKeyNoticePrimary =>
      'Na página seguinte verá uma sequência de 24 palavras. Esta é a sua chave de encriptação única e privada e é a ÚNICA forma de recuperar os seus dados em caso de terminar sessão, perder o dispositivo ou ocorrer uma avaria.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Nós não guardamos esta chave. É da sua responsabilidade guardá-la num local seguro fora da aplicação $appName.';
  }

  @override
  String get showKeyConfirmation => 'Compreendo.\nMostrar a chave.';

  @override
  String get storageAddedSuccessfully => 'Armazenamento adicionado com sucesso';

  @override
  String get networkErrorDuringValidation =>
      'Ocorreu um erro de rede durante a validação.';

  @override
  String get verifyAndConnect => 'Verificar e ligar';

  @override
  String get requiredField => 'Obrigatório';

  @override
  String get providerKeysVerifiedLocally =>
      'As suas chaves são verificadas localmente e encriptadas antes de serem transmitidas.';

  @override
  String get enterYourCredentials => 'Introduza as suas credenciais';

  @override
  String connectProvider(String provider) {
    return 'Ligar $provider';
  }

  @override
  String get deviceLimitReached => 'Limite de dispositivos atingido';

  @override
  String get pleaseTryAgainWithExclamation => 'Tente novamente!';

  @override
  String get notThisDevice => 'Não este dispositivo!';

  @override
  String get confirmSignoutDeviceTitle => 'Confirmar saída do dispositivo';

  @override
  String get areYouSure => 'Tem a certeza?';

  @override
  String get cancel => 'Cancelar';

  @override
  String get ok => 'OK';

  @override
  String get noDeviceFound => 'Nenhum dispositivo encontrado';

  @override
  String get backTooltip => 'Voltar';

  @override
  String get devicesTitle => 'Dispositivos';

  @override
  String get longPressToDownload => 'Prima continuamente para transferir';

  @override
  String get fewItemsExistLocally => 'Alguns itens ainda existem localmente.';

  @override
  String selectedItemsCount(int count) {
    return '$count selecionados';
  }

  @override
  String get delete => 'Eliminar';

  @override
  String get info => 'Informação';

  @override
  String get download => 'Transferir';

  @override
  String get archive => 'Arquivar';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Registos';

  @override
  String get settings => 'Definições';

  @override
  String get trash => 'Lixo';

  @override
  String get storage => 'Armazenamento';

  @override
  String get search => 'Pesquisar';

  @override
  String get database => 'Base de dados';

  @override
  String get addFolderTitle => 'Adicionar pasta';

  @override
  String get confirm => 'Confirmar';

  @override
  String get tapPlusToAddSyncFolder =>
      'Toque em + para adicionar uma pasta de sincronização.';

  @override
  String get thisFolderIsEmpty => 'Esta pasta está vazia.';

  @override
  String get fileNotFound => 'Ficheiro não encontrado';

  @override
  String filePartsTitle(int count) {
    return 'Partes do ficheiro ($count)';
  }

  @override
  String get fileDetailsTitle => 'Detalhes do ficheiro';

  @override
  String get encryptedBackup => 'Cópia de segurança encriptada';

  @override
  String get sizeLabel => 'Tamanho';

  @override
  String get providerLabel => 'Fornecedor';

  @override
  String get uploadedAtLabel => 'Carregado em';

  @override
  String get statusLabel => 'Estado';

  @override
  String get uploadedStatus => 'Carregado';

  @override
  String errorWithMessage(String message) {
    return 'Erro: $message';
  }

  @override
  String get noLogsAvailable => 'Não há registos disponíveis';

  @override
  String get searchLogsHint => 'Pesquisar nos registos...';

  @override
  String get clearLogs => 'Limpar registos';

  @override
  String get searchWithMinThreeCharacters =>
      'Pesquise com pelo menos 3 caracteres';

  @override
  String get typeBelowToSearch => 'Escreva abaixo para pesquisar';

  @override
  String get noResults => 'Sem resultados.';

  @override
  String get welcomeTitle => 'Bem-vindo';

  @override
  String signInToContinue(String appName) {
    return 'Inicie sessão para continuar no $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Introduza o seu e-mail';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Introduza um endereço de e-mail válido';

  @override
  String get emailAddressLabel => 'Endereço de e-mail';

  @override
  String get emailAddressHint => 'o.seu.email@exemplo.com';

  @override
  String get retrySendingOtp => 'Tentar enviar OTP novamente';

  @override
  String get sendOtp => 'Enviar OTP';

  @override
  String get checkYourEmail => 'Verifique o seu e-mail';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Enviámos um código de 6 dígitos para\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Introduza o OTP';

  @override
  String get otpMustBeSixDigits => 'O OTP tem de ter 6 dígitos';

  @override
  String get enterOtpLabel => 'Introduzir OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Tentar verificação novamente';

  @override
  String get verifyOtp => 'Verificar OTP';

  @override
  String get useDifferentEmail => 'Usar outro e-mail';

  @override
  String get alreadySignedIn => 'Sessão já iniciada';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Falha no envio do OTP. Tente novamente!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'Falha na verificação do OTP. Tente novamente.';

  @override
  String get dbViewerTitle => 'Visualizador da BD';

  @override
  String get selectTableToViewData => 'Selecione uma tabela para ver os dados';

  @override
  String get selectTable => 'Selecionar tabela';

  @override
  String get permissionRequiredTitle => 'Permissão necessária';

  @override
  String get storagePermissionSettingsDescription =>
      'Para fazer cópias de segurança automáticas, gerir e proteger os seus ficheiros em segundo plano, precisamos de acesso ao armazenamento do seu dispositivo. Os seus dados são encriptados localmente, garantindo total privacidade. Autorize o acesso para continuar.';

  @override
  String get openSettings => 'Abrir definições';

  @override
  String get storagePermissionRequiredToContinue =>
      'É necessária permissão de armazenamento para continuar';

  @override
  String get secureLocalAccessTitle => 'Acesso local seguro';

  @override
  String get storagePermissionPageDescription =>
      'Para explorar, encriptar e fazer cópias de segurança automáticas dos seus ficheiros, precisamos de acesso ao armazenamento do seu dispositivo.';

  @override
  String get verifying => 'A verificar...';

  @override
  String get grantAccess => 'Conceder acesso';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Armazenamento encriptado zero-knowledge';

  @override
  String requiresAppPro(String appName) {
    return 'Requer $appName Pro.';
  }

  @override
  String get noStorageFound => 'Nenhum armazenamento encontrado';

  @override
  String get howToConnect => 'Como ligar';

  @override
  String get modify => 'Modificar';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total utilizados';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Até $size grátis';
  }

  @override
  String get notConnected => 'Não ligado';

  @override
  String get connect => 'Ligar';

  @override
  String get modifyStorageCapacityTitle =>
      'Modificar capacidade de armazenamento';

  @override
  String get enterNewStorageLimitForProvider =>
      'Introduza o novo limite de armazenamento para este fornecedor.';

  @override
  String get sizePrefix => 'Tamanho: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Introduza um tamanho';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Introduza um número válido superior a 1';

  @override
  String get submit => 'Submeter';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return 'Subscrição de $appName Pro concluída com sucesso!';
  }

  @override
  String get purchaseCancelledOrFailed => 'Compra cancelada ou sem sucesso.';

  @override
  String get purchasesRestoredSuccessfully =>
      'Compras restauradas com sucesso!';

  @override
  String get noActiveSubscriptionsFound =>
      'Não foram encontradas subscrições ativas.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Gira as subscrições nas definições do seu dispositivo.';

  @override
  String get freePlanTitle => 'Grátis';

  @override
  String get freeForeverPrice => '\$0.00 / para sempre';

  @override
  String get freeBenefitProviderStorage =>
      'Aproveite o armazenamento gratuito dos fornecedores';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Sincronize até 3 dispositivos com segurança';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Anual';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Modifique o limite de armazenamento de cada fornecedor';

  @override
  String get proBenefitSyncTenDevices => 'Sincronize até 10 dispositivos';

  @override
  String get restorePurchases => 'Restaurar compras';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* A subscrição está associada à conta de e-mail, não ao dispositivo';

  @override
  String get subscriptionExpiredTitle => 'Subscrição expirada';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Os benefícios do $appName Pro foram suspensos. Renove abaixo para restaurar os seus limites de armazenamento e sincronizações entre dispositivos.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro está ativo';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Modifique os limites de armazenamento de cada fornecedor\n✓ Sincronização cruzada até 10 dispositivos';

  @override
  String get manageSubscription => 'Gerir subscrição';

  @override
  String get currentPlanBadge => 'ATUAL';

  @override
  String get subscribeNow => 'Subscrever agora';

  @override
  String get subscribeOnMobileApp => 'Subscreva na aplicação móvel';

  @override
  String get recover => 'Recuperar';

  @override
  String get empty => 'Esvaziar';

  @override
  String get noItems => 'Sem itens.';
}
