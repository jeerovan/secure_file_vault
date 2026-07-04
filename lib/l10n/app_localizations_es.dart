// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'FiFe';

  @override
  String continueAgreementText(String terms, String privacy) {
    return 'Al continuar, aceptas nuestros $terms y nuestra $privacy.';
  }

  @override
  String get termsOfService => 'Términos del servicio';

  @override
  String get privacyPolicy => 'Política de privacidad';

  @override
  String get andLabel => ' y ';

  @override
  String get theme => 'Tema';

  @override
  String get themeTooltip => 'Tema claro/oscuro';

  @override
  String get logging => 'Registro';

  @override
  String get quickSyncNotificationSettingTitle =>
      'Notificación de sincronización rápida';

  @override
  String get quickSyncNotificationTitle =>
      'Servicio de sincronización de archivos';

  @override
  String get quickSyncNotificationText =>
      'Toca el botón de abajo para sincronizar';

  @override
  String get quickSyncNotificationButton => 'Sincronizar ahora';

  @override
  String get quickSyncNotificationInProgress => 'En curso...';

  @override
  String get reportIssue => 'Reportar problema';

  @override
  String get sourceCode => 'Código fuente';

  @override
  String get desktopApp => 'Aplicación de escritorio';

  @override
  String get mobileApp => 'Aplicación móvil';

  @override
  String get leaveReview => 'Dejar una reseña';

  @override
  String get share => 'Compartir';

  @override
  String get versionLabel => 'Versión: ';

  @override
  String get loading => 'Cargando...';

  @override
  String get signOut => 'Cerrar sesión';

  @override
  String get settingsPageTitle => 'Ajustes';

  @override
  String get language => 'Idioma';

  @override
  String get tapToSelect => 'Toca para seleccionar';

  @override
  String get appTagline => 'Tu transporte privado para archivos';

  @override
  String get onboardingPurposeDescription =>
      'Un servicio de almacenamiento en la nube de código abierto, creado con arquitectura zero-trust. Tus datos se cifran en tu dispositivo antes de salir de él.';

  @override
  String get failedToFetch => 'No se pudo cargar.';

  @override
  String get supportedStorageTitle => 'Almacenamientos compatibles';

  @override
  String get supportedStorageDescription =>
      'Conecta tus proveedores favoritos. Empieza de inmediato con 1 GB de almacenamiento seguro gratuito incluido en FiFe.';

  @override
  String get fifeCloud => 'FiFe Cloud';

  @override
  String get startBackupsInstantly =>
      'Empieza tus copias de seguridad al instante';

  @override
  String get freeStorageSizeOneGb => '1.0 GB';

  @override
  String get freeLabel => 'Gratis';

  @override
  String get providerStorageDisclaimer =>
      '* Almacenamiento gratuito según lo indicado en el sitio web del proveedor. Pago por uso con proveedores compatibles.';

  @override
  String get whyUseFifeTitle => '¿Por qué usar FiFe?';

  @override
  String get claimFreeCloudStorageTitle =>
      'Aprovecha almacenamiento gratuito en la nube';

  @override
  String get claimFreeCloudStorageDescription =>
      'Aumenta tu espacio conectando varios proveedores en la nube. Aprovecha de forma segura sus planes gratuitos desde una sola app.';

  @override
  String get topNotchSecurityTitle => 'Seguridad de primer nivel';

  @override
  String get topNotchSecurityDescription =>
      'Impulsado por criptografía avanzada de Sodium. Todo el cifrado y descifrado se realiza localmente en tu dispositivo.';

  @override
  String get bringYourOwnKeyTitle => 'Bring Your Own Key (BYOK)';

  @override
  String get bringYourOwnKeyDescription =>
      'Mantén el control total de tus datos en todos los proveedores de almacenamiento en la nube. Usa almacenamiento cifrado con tus propias cuentas.';

  @override
  String get payAsYouGoStorageTitle =>
      'Paga solo por el almacenamiento que uses.';

  @override
  String get payAsYouGoStorageDescription =>
      'Paga solo por el almacenamiento que realmente uses con proveedores compatibles. Sin intermediarios ni bloqueo de datos.';

  @override
  String get zeroKnowledgePrivacyTitle => 'Privacidad de conocimiento cero';

  @override
  String get zeroKnowledgePrivacyDescription =>
      'Tus datos quedan protegidos en tu dispositivo antes de salir de él. No podemos ver, leer ni analizar tus archivos.';

  @override
  String get localSelectionTitle => '1. Selección local';

  @override
  String get localSelectionDescription =>
      'Tú eliges una carpeta. Todo el procesamiento comienza de forma segura en tu dispositivo.';

  @override
  String get metadataEncryptionTitle => '2. Cifrado de metadatos';

  @override
  String get metadataEncryptionDescription =>
      'La información del archivo, como nombres, tipos y tamaños, se cifra antes de enviarse al servidor.';

  @override
  String get contentEncryptionTitle => '3. Cifrado del contenido';

  @override
  String get contentEncryptionDescription =>
      'El contenido real del archivo se fragmenta y se cifra antes de subirse al almacenamiento en la nube.';

  @override
  String get blindServerTitle => '4. Servidor ciego';

  @override
  String get blindServerDescription =>
      'Nuestros servidores no tienen conocimiento de tus datos. Solo vemos bloques cifrados, lo que garantiza una privacidad total.';

  @override
  String get dontTrustVerifyTitle => 'No confíes, verifica.';

  @override
  String get openSourceVerificationDescription =>
      '100 % de código abierto. Puedes revisar el código para ver exactamente cómo se cifran tus archivos.';

  @override
  String get getStarted => 'Empezar';

  @override
  String get next => 'Siguiente';

  @override
  String get unauthorized => 'No autorizado';

  @override
  String get tryAgain => 'Intentar de nuevo';

  @override
  String get errorTitle => 'Error';

  @override
  String get failureTitle => 'Fallo';

  @override
  String get invalidWordList => 'Lista de palabras no válida';

  @override
  String get invalidAccessKey => 'Clave de acceso no válida';

  @override
  String get unexpectedDecryptionError =>
      'Ocurrió un error inesperado durante el descifrado.';

  @override
  String get fileMustContainExactly24Words =>
      'El archivo debe contener exactamente 24 palabras.';

  @override
  String get errorReadingFile => 'Error al leer el archivo';

  @override
  String get encryptionTitle => 'Cifrado';

  @override
  String get accessKeyDecodeDescription =>
      'Introduce tu frase de recuperación de 24 palabras o carga un archivo .txt para activar la sincronización en la nube de forma segura.';

  @override
  String get recoveryPhraseLabel => 'Frase de recuperación';

  @override
  String get recoveryPhraseHint => 'word1 word2 word3...';

  @override
  String get paste => 'Pegar';

  @override
  String wordCountLabel(int count) {
    return '$count / 24 palabras';
  }

  @override
  String get pleaseEnterRecoveryPhrase => 'Introduce tu frase de recuperación';

  @override
  String get mustContainExactly24Words =>
      'Debe contener exactamente 24 palabras';

  @override
  String get verify => 'Verificar';

  @override
  String get orLabel => 'O';

  @override
  String get loadFromTxtFile => 'Cargar desde archivo .txt';

  @override
  String get saveAccessKey => 'Guardar clave de acceso';

  @override
  String get fileSavedSuccessfully => 'Archivo guardado correctamente.';

  @override
  String get accessKeyShareMessage => 'Aquí tienes tu clave de acceso.';

  @override
  String get pleaseTryAgain => 'Inténtalo de nuevo.';

  @override
  String get copiedToClipboard => 'Copiado al portapapeles';

  @override
  String get accessKeyTitle => 'Clave de acceso';

  @override
  String get accessKeyDescription =>
      'Guarda esta clave en un lugar seguro. Solo con ella podrás acceder a tus datos cifrados.';

  @override
  String get copy => 'Copiar';

  @override
  String get downloadAsTextFile => 'Descargar como archivo de texto';

  @override
  String get continueLabel => 'Continuar';

  @override
  String get importantTitle => 'Importante';

  @override
  String get accessKeyNoticePrimary =>
      'En la siguiente pantalla verás una serie de 24 palabras. Esta es tu clave de cifrado privada y única, y es la ÚNICA forma de recuperar tus datos en caso de cerrar sesión, perder el dispositivo o sufrir un fallo.';

  @override
  String accessKeyNoticeResponsibility(String appName) {
    return 'Nosotros no almacenamos esta clave. Es TU responsabilidad guardarla en un lugar seguro fuera de la app $appName.';
  }

  @override
  String get showKeyConfirmation => 'Lo entiendo.\nMuéstrame la clave.';

  @override
  String get storageAddedSuccessfully => 'Almacenamiento añadido correctamente';

  @override
  String get networkErrorDuringValidation =>
      'Ocurrió un error de red durante la validación.';

  @override
  String get verifyAndConnect => 'Verificar y conectar';

  @override
  String get requiredField => 'Obligatorio';

  @override
  String get providerKeysVerifiedLocally =>
      'Tus claves se verifican localmente y se cifran antes de enviarse.';

  @override
  String get enterYourCredentials => 'Introduce tus credenciales';

  @override
  String connectProvider(String provider) {
    return 'Conectar $provider';
  }

  @override
  String get deviceLimitReached => 'Se alcanzó el límite de dispositivos';

  @override
  String get pleaseTryAgainWithExclamation => '¡Inténtalo de nuevo!';

  @override
  String get notThisDevice => '¡No este dispositivo!';

  @override
  String get confirmSignoutDeviceTitle =>
      'Confirmar cierre de sesión del dispositivo';

  @override
  String get areYouSure => '¿Estás seguro?';

  @override
  String get cancel => 'Cancelar';

  @override
  String get ok => 'Aceptar';

  @override
  String get noDeviceFound => 'No se encontró ningún dispositivo';

  @override
  String get backTooltip => 'Atrás';

  @override
  String get devicesTitle => 'Dispositivos';

  @override
  String get longPressToDownload => 'Mantén pulsado para descargar';

  @override
  String get fewItemsExistLocally =>
      'Algunos elementos siguen existiendo localmente.';

  @override
  String selectedItemsCount(int count) {
    return '$count seleccionados';
  }

  @override
  String get delete => 'Eliminar';

  @override
  String get info => 'Información';

  @override
  String get download => 'Descargar';

  @override
  String get archive => 'Archivar';

  @override
  String appPro(String appName) {
    return '$appName Pro';
  }

  @override
  String get logs => 'Registros';

  @override
  String get settings => 'Ajustes';

  @override
  String get trash => 'Papelera';

  @override
  String get storage => 'Almacenamiento';

  @override
  String get search => 'Buscar';

  @override
  String get database => 'Base de datos';

  @override
  String get addFolderTitle => 'Añadir carpeta';

  @override
  String get confirm => 'Confirmar';

  @override
  String get tapPlusToAddSyncFolder =>
      'Toca + para añadir una carpeta de sincronización.';

  @override
  String get thisFolderIsEmpty => 'Esta carpeta está vacía.';

  @override
  String get fileNotFound => 'Archivo no encontrado';

  @override
  String filePartsTitle(int count) {
    return 'Partes del archivo ($count)';
  }

  @override
  String get fileDetailsTitle => 'Detalles del archivo';

  @override
  String get encryptedBackup => 'Copia de seguridad cifrada';

  @override
  String get sizeLabel => 'Tamaño';

  @override
  String get providerLabel => 'Proveedor';

  @override
  String get uploadedAtLabel => 'Subido el';

  @override
  String get statusLabel => 'Estado';

  @override
  String get uploadedStatus => 'Subido';

  @override
  String errorWithMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get noLogsAvailable => 'No hay registros disponibles';

  @override
  String get searchLogsHint => 'Buscar en los registros...';

  @override
  String get clearLogs => 'Borrar registros';

  @override
  String get searchWithMinThreeCharacters => 'Busca con al menos 3 caracteres';

  @override
  String get typeBelowToSearch => 'Escribe abajo para buscar';

  @override
  String get noResults => 'Sin resultados.';

  @override
  String get welcomeTitle => 'Bienvenido';

  @override
  String signInToContinue(String appName) {
    return 'Inicia sesión para continuar en $appName';
  }

  @override
  String get pleaseEnterYourEmail => 'Introduce tu correo electrónico';

  @override
  String get pleaseEnterValidEmailAddress =>
      'Introduce una dirección de correo válida';

  @override
  String get emailAddressLabel => 'Correo electrónico';

  @override
  String get emailAddressHint => 'tu.correo@ejemplo.com';

  @override
  String get retrySendingOtp => 'Reenviar OTP';

  @override
  String get sendOtp => 'Enviar OTP';

  @override
  String get checkYourEmail => 'Revisa tu correo';

  @override
  String sentSixDigitCodeTo(String email) {
    return 'Hemos enviado un código de 6 dígitos a\n$email';
  }

  @override
  String get pleaseEnterOtp => 'Introduce el OTP';

  @override
  String get otpMustBeSixDigits => 'El OTP debe tener 6 dígitos';

  @override
  String get enterOtpLabel => 'Introduce el OTP';

  @override
  String get otpHint => '000000';

  @override
  String get retryVerification => 'Reintentar verificación';

  @override
  String get verifyOtp => 'Verificar OTP';

  @override
  String get useDifferentEmail => 'Usar otro correo electrónico';

  @override
  String get alreadySignedIn => 'Sesión ya iniciada';

  @override
  String get sendingOtpFailedPleaseTryAgain =>
      'Error al enviar el OTP. ¡Inténtalo de nuevo!';

  @override
  String get otpVerificationFailedPleaseTryAgain =>
      'La verificación del OTP falló. Inténtalo de nuevo.';

  @override
  String get dbViewerTitle => 'Visor de BD';

  @override
  String get selectTableToViewData => 'Selecciona una tabla para ver sus datos';

  @override
  String get selectTable => 'Seleccionar tabla';

  @override
  String get permissionRequiredTitle => 'Permiso necesario';

  @override
  String get storagePermissionSettingsDescription =>
      'Para hacer copias de seguridad automáticas, gestionar y proteger tus archivos en segundo plano, necesitamos acceso al almacenamiento de tu dispositivo. Tus datos se cifran localmente para garantizar una privacidad total. Permite el acceso para continuar.';

  @override
  String get openSettings => 'Abrir ajustes';

  @override
  String get secureLocalAccessTitle => 'Acceso local seguro';

  @override
  String get storagePermissionPageDescription =>
      'Para explorar, cifrar y hacer copias de seguridad automáticas de tus archivos, necesitamos acceso al almacenamiento de tu dispositivo.';

  @override
  String get verifying => 'Verificando...';

  @override
  String get grantAccess => 'Conceder acceso';

  @override
  String get zeroKnowledgeEncryptedStorage =>
      'Almacenamiento cifrado de conocimiento cero';

  @override
  String get notificationPermissionTitle => 'Acceso a Notificaciones';

  @override
  String get notificationPermissionPageDescription =>
      'Para sincronizar y subir tus archivos rápidamente en segundo plano desde el panel de notificaciones, necesitamos permiso para mostrar notificaciones. Puedes desactivarlo en cualquier momento desde la configuración.';

  @override
  String get notificationPermissionGrantButton => 'Permitir Notificaciones';

  @override
  String get notificationPermissionSettingsDescription =>
      'Las notificaciones son necesarias para ofrecer la sincronización rápida desde el panel de notificaciones. Actívalas en la configuración del sistema para asegurarte de que todos tus datos se suban correctamente.';

  @override
  String requiresAppPro(String appName) {
    return 'Requiere $appName Pro.';
  }

  @override
  String get noStorageFound => 'No se encontró almacenamiento';

  @override
  String get howToConnect => 'Cómo conectar';

  @override
  String get modify => 'Modificar';

  @override
  String storageUsed(String used, String total) {
    return '$used / $total usados';
  }

  @override
  String percentageLabel(String value) {
    return '$value%';
  }

  @override
  String upToFree(String size) {
    return 'Hasta $size gratis';
  }

  @override
  String get notConnected => 'No conectado';

  @override
  String get connect => 'Conectar';

  @override
  String get modifyStorageCapacityTitle =>
      'Modificar capacidad de almacenamiento';

  @override
  String get enterNewStorageLimitForProvider =>
      'Introduce el nuevo límite de almacenamiento para este proveedor.';

  @override
  String get sizePrefix => 'Tamaño: ';

  @override
  String get gbSuffix => ' GB';

  @override
  String get pleaseEnterSize => 'Introduce un tamaño';

  @override
  String get enterValidNumberGreaterThanOne =>
      'Introduce un número válido mayor que 1';

  @override
  String get submit => 'Enviar';

  @override
  String successfullySubscribedToAppPro(String appName) {
    return '¡Suscripción a $appName Pro completada con éxito!';
  }

  @override
  String get purchaseCancelledOrFailed => 'La compra se canceló o falló.';

  @override
  String get purchasesRestoredSuccessfully =>
      '¡Compras restauradas correctamente!';

  @override
  String get noActiveSubscriptionsFound =>
      'No se encontraron suscripciones activas.';

  @override
  String get manageSubscriptionsInDeviceSettings =>
      'Gestiona las suscripciones desde los ajustes de tu dispositivo.';

  @override
  String get freePlanTitle => 'Gratis';

  @override
  String get freeForeverPrice => '\$0.00 / para siempre';

  @override
  String get freeBenefitProviderStorage =>
      'Disfruta del almacenamiento gratuito de los proveedores';

  @override
  String get freeBenefitSyncThreeDevices =>
      'Sincroniza hasta 3 dispositivos de forma segura';

  @override
  String appProYearlyTitle(String appName) {
    return '$appName Pro - Anual';
  }

  @override
  String get proBenefitModifyStorageLimit =>
      'Modifica el límite de almacenamiento de cada proveedor';

  @override
  String get proBenefitSyncTenDevices => 'Sincroniza hasta 10 dispositivos';

  @override
  String get restorePurchases => 'Restaurar compras';

  @override
  String get subscriptionAssociatedWithEmailNotDevice =>
      '* La suscripción está asociada a la cuenta de correo electrónico, no al dispositivo';

  @override
  String get subscriptionExpiredTitle => 'Suscripción vencida';

  @override
  String subscriptionExpiredDescription(String appName) {
    return 'Tus beneficios de $appName Pro están en pausa. Renueva abajo para recuperar tus límites de almacenamiento y la sincronización entre dispositivos.';
  }

  @override
  String appProIsActive(String appName) {
    return '$appName Pro está activo';
  }

  @override
  String get activePlanBenefitsSummary =>
      '✓ Modifica los límites de almacenamiento de cada proveedor\n✓ Sincronización entre dispositivos hasta en 10 dispositivos';

  @override
  String get manageSubscription => 'Gestionar suscripción';

  @override
  String get currentPlanBadge => 'ACTUAL';

  @override
  String get subscribeNow => 'Suscribirse ahora';

  @override
  String get subscribeOnMobileApp => 'Suscríbete desde la app móvil';

  @override
  String get recover => 'Recuperar';

  @override
  String get empty => 'Vaciar';

  @override
  String get noItems => 'No hay elementos.';
}
