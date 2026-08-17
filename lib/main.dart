import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/ui/pages/page_notification_permission.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_check.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_device_register.dart';
import 'package:file_vault_bb/ui/pages/page_welcome.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../models/model_setting.dart';
import '../services/service_logger.dart';
import '../storage/storage_secure.dart';
import '../storage/storage_sqlite.dart';
import '../ui/common_widgets.dart';
import 'l10n/app_localizations.dart';
import 'services/service_locale.dart';
import 'ui/pages/page_access_key_display.dart';
import '../ui/pages/page_access_key_notice.dart';
import '../ui/pages/page_devices.dart';
import '../ui/pages/page_explorer.dart';
import '../ui/pages/page_loading.dart';
import '../ui/pages/page_signin.dart';
import '../ui/pages/page_storage_permission.dart';
import '../ui/themes.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'utils/service_foreground_handler.dart';
import 'utils/utils_sync.dart';

@pragma('vm:entry-point')
void startForegroundTask() {
  FlutterForegroundTask.setTaskHandler(ForegroundTaskHandler());
}

@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    final workerLogger = AppLogger(prefixes: ['Workmanager']);
    return runBackgroundWorkerSafely(
      task: () async {
        WidgetsFlutterBinding.ensureInitialized();
        await StorageSqlite.initialize(ExecutionMode.backgroundWorker);
        await initializeDependencies(ExecutionMode.backgroundWorker);
        return SyncUtils().reconFolders(caller: 'Workmanager');
      },
      cleanupActions: [
        BackgroundCleanupAction('HTTP clients', AppHttpClients.closeAll),
        BackgroundCleanupAction('SQLite', StorageSqlite.instance.close),
      ],
      onError: (operation, error, stackTrace) {
        workerLogger.error(
          'Background sync $operation failed',
          error: error,
          stackTrace: stackTrace,
        );
      },
    );
  });
}

final logger = AppLogger(prefixes: ["Main"]);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.clearLegacyLogsOnce();
  await StorageSqlite.initialize(ExecutionMode.mainApp);
  await initializeInParallel();
  SecureStorage prefs = SecureStorage();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppSetupState(prefs),
        ),
        ChangeNotifierProvider(
          create: (context) => LocaleProvider(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> initializeInParallel() async {
  final startupTasks = <Future<void>>[
    initializeDependencies(ExecutionMode.mainApp),
    initializePurchases(),
  ];
  if (Platform.isIOS) {
    // iOS background execution is optional and must never delay foreground UI.
    unawaited(initializeBackgroundExecution());
  } else {
    startupTasks.add(initializeBackgroundExecution());
  }
  await Future.wait(startupTasks);
}

Future<void> initializeBackgroundExecution() async {
  try {
    await BackgroundExecutionService.instance.initialize(
      iosCallbackDispatcher: backgroundTaskDispatcher,
    );
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      SyncUtils().startAutoSync();
      logger.info("initialized autosync");
    }
  } catch (error, stackTrace) {
    logger.error(
      "Background execution initialization failed; foreground app will continue",
      error: error,
      stackTrace: stackTrace,
    );
  }
}

Future<void> initializePurchases() async {
  if (revenueCatSupported) {
    String rcKey = "";
    if (Platform.isAndroid) {
      rcKey = AppEnv.rcAndroidKey;
    } else if (Platform.isIOS || Platform.isMacOS) {
      rcKey = AppEnv.rcIosKey;
    }
    if (rcKey.isNotEmpty) {
      if (isDebugEnabled) {
        await Purchases.setLogLevel(LogLevel.debug);
      }
      PurchasesConfiguration configuration = PurchasesConfiguration(rcKey);
      await Purchases.configure(configuration);
      logger.info("Initialized purchases");
    }
  }
}

// --- Main Application Widget ---

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier(ThemeMode.system);

  final logger = AppLogger(prefixes: ["MainApp"]);

  @override
  void initState() {
    super.initState();
    // Load the theme from saved preferences
    String savedTheme = ModelSetting.get(AppString.theme.string);
    switch (savedTheme) {
      case "light":
        themeNotifier.value = ThemeMode.light;
        break;
      case "dark":
        themeNotifier.value = ThemeMode.dark;
        break;
      default:
        themeNotifier.value = ThemeMode.system;
        break;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    themeNotifier.dispose();
    AppHttpClients.closeAll();
    super.dispose();
  }

  // Toggle between light and dark modes
  void _onThemeChange(String? theme) async {
    logger.debug("Changing theme to -> $theme");
    switch (theme) {
      case "light":
        themeNotifier.value = ThemeMode.light;
        break;
      case "dark":
        themeNotifier.value = ThemeMode.dark;
        break;
      default:
        themeNotifier.value = ThemeMode.system;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final localeProvider = Provider.of<LocaleProvider>(context);
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode currentMode, child) {
        return MaterialApp(
          locale: localeProvider.locale,
          supportedLocales: L10n.all,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: currentMode,
          // Uses system theme by default
          home: AppNavigator(
            onThemeChange: _onThemeChange,
          ),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}

class AppNavigator extends StatelessWidget {
  final Function(String?) onThemeChange;

  const AppNavigator({
    super.key,
    required this.onThemeChange,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSetupState>(
      builder: (context, setupState, child) {
        switch (setupState.currentStep) {
          case SetupStep.loading:
            return const PageLoading();
          case SetupStep.onboard:
            return const FiFeOnboardingScreen();
          case SetupStep.signin:
            return PageSignin();
          case SetupStep.checkAccessKey:
            return PageAccessKeyCheck();
          case SetupStep.generateAccessKey:
            return const PageAccessKeyNotice();
          case SetupStep.decodeAccessKey:
            return PageAccessKeyDecode();
          case SetupStep.showAccessKey:
            return const PageAccessKey();
          case SetupStep.registerDevice:
            return PageRegisterDevice();
          case SetupStep.manageDevices:
            return const PageDevices(
              onStack: false,
            );
          case SetupStep.storagePermission:
            return const StoragePermissionPage();
          case SetupStep.notificationPermission:
            return const NotificationPermissionPage();
          case SetupStep.explorer:
            return PageExplorer(
              onThemeChange: onThemeChange,
            );
        }
      },
    );
  }
}
