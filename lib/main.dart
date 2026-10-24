import 'dart:async';
import 'dart:io';

import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/services/service_http_clients.dart';
import 'package:file_vault_bb/services/service_sync_budget.dart';
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
import 'services/service_app_lock.dart';
import 'ui/app_lock.dart';
import 'services/service_events.dart';
import 'services/service_session_cleanup.dart';
import 'services/service_session_work.dart';
import 'services/service_recovery_reset.dart';
import 'ui/pages/page_recovery_reset.dart';
import 'ui/pages/page_session_cleanup.dart';
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
import 'package:flutter/services.dart';
import 'utils/service_foreground_handler.dart';
import 'utils/utils_sync.dart';
import 'utils/utils_tasks.dart';

@pragma('vm:entry-point')
void startForegroundTask() {
  FlutterForegroundTask.setTaskHandler(ForegroundTaskHandler());
}

@pragma('vm:entry-point')
void backgroundTaskDispatcher() async {
  WidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.jeerovan.fife/background_worker');
  SyncBudget? budget;
  var expired = false;
  channel.setMethodCallHandler((call) async {
    if (call.method == 'expire') {
      expired = true;
      budget?.cancel('expiration');
    }
  });
  final workerLogger = AppLogger(prefixes: ['Background Sync']);
  var succeeded = false;
  try {
    final ready = await channel.invokeMapMethod<String, dynamic>('ready');
    if (ready == null) throw StateError('Missing background deadline');
    final executionBudget = SyncBudget(
        deadline:
            DateTime.fromMillisecondsSinceEpoch(ready['deadline'] as int));
    budget = executionBudget;
    if (expired || ready['expired'] == true) {
      executionBudget.cancel('expiration');
    }
    final unregister = executionBudget.onCancel(AppHttpClients.closeAll);
    succeeded = await executionBudget.run(() => runBackgroundWorkerSafely(
          task: () async {
            SyncBudget.check();
            await StorageSqlite.initialize(ExecutionMode.backgroundWorker);
            if (!await SessionCleanup.instance.resume()) return false;
            if (SessionWork.authenticationRequired) return false;
            if (!await isIosBackgroundSyncReady()) return true;
            await initializeDependencies(ExecutionMode.backgroundWorker);
            SyncBudget.check();
            return SyncUtils().reconFolders(caller: 'BackgroundRefresh');
          },
          cleanupActions: [
            BackgroundCleanupAction(
                'Transfer wakes', TaskManager.stopBackgroundWakes),
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
        ));
    unregister();
    succeeded = succeeded && !executionBudget.interrupted;
  } catch (error, stackTrace) {
    workerLogger.error('Background worker initialization failed',
        error: error, stackTrace: stackTrace);
  } finally {
    budget?.dispose();
    await channel.invokeMethod<void>('finished', succeeded);
  }
}

final logger = AppLogger(prefixes: ["Main"]);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppLogger.clearLegacyLogsOnce();
  await StorageSqlite.initialize(ExecutionMode.mainApp);
  try {
    if (await SessionCleanup.instance.resume()) {
      if (SessionWork.authenticationRequired) {
        await SessionWork.authenticate(() async {
          await Future.wait([addTrustedCertificates(), initializePackages()]);
        });
      } else {
        await initializeInParallel();
      }
      if (AppEnv.effectiveApiBaseUrl.isNotEmpty &&
          !SessionWork.authenticationRequired &&
          !await RecoveryResetService.instance.hasPending() &&
          await ModelSetting.getRaw(AppString.signedIn.string) == 'yes' &&
          (await getDeviceUuid()).isNotEmpty) {
        await SessionWork.run(SyncUtils.checkDeviceStatus);
      }
    }
  } on SessionInvalidated {
    // A pending cleanup must still render its retry screen.
  } catch (error) {
    // Let setup display its retry screen when private storage is unavailable.
    logger.warning('Startup session check will retry: ${error.runtimeType}');
  }
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
    // iOS refresh is automatic, but availability must never delay foreground UI.
    unawaited(initializeBackgroundExecution());
  } else {
    startupTasks.add(initializeBackgroundExecution());
  }
  await Future.wait(startupTasks);
}

Future<void> initializeBackgroundExecution() async {
  try {
    await SessionWork.checkpoint();
    if (await RecoveryResetService.instance.hasPending()) return;
    await BackgroundExecutionService.instance.initialize(
      iosCallbackDispatcher: backgroundTaskDispatcher,
    );
    await SessionWork.checkpoint();
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
  if (subscriptionsSupported) {
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
      if (!simulateTesting()) {
        configuration.appUserID = await getSignedInUserId();
      }
      await Purchases.configure(configuration);
      logger.info("Initialized purchases");
    }
  }
}

// --- Main Application Widget ---

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.recoveryService, this.appLock});
  final RecoveryResetService? recoveryService;
  final AppLockController? appLock;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  GlobalKey<NavigatorState> _navigationKey = GlobalKey<NavigatorState>();
  StreamSubscription<AppEvent>? _sessionEvents;
  bool _checkingSession = false;
  late final AppLockController _appLock;
  late AppLockNavigatorObserver _appLockNavigation;
  final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier(ThemeMode.system);

  final logger = AppLogger(prefixes: ["MainApp"]);

  @override
  void initState() {
    super.initState();
    _appLock = widget.appLock ?? AppLockController();
    _appLockNavigation = AppLockNavigatorObserver(_appLock);
    unawaited(_appLock.load());
    _sessionEvents = EventStream().events.listen((event) {
      if (event.key == EventKey.sessionInvalidated && mounted) {
        _appLock.invalidateSession();
        _appLockNavigation.dispose();
        _appLockNavigation = AppLockNavigatorObserver(_appLock);
        // Discard protected routes and dialogs as well as the home page.
        setState(() => _navigationKey = GlobalKey<NavigatorState>());
      } else if (event.key == EventKey.signout && mounted) {
        // External cleanup can announce completion immediately before it
        // publishes the active revision. Read policy after that stack unwinds.
        unawaited(Future<void>.microtask(() async {
          if (mounted) await _appLock.load();
        }));
      } else if (event.key == EventKey.authenticated && mounted) {
        if (!_appLock.ready || _appLock.busy) unawaited(_appLock.load());
        // Expiry stopped scheduling, and a held cold start intentionally skips
        // it. Resume the normal platform scheduler only after activation.
        unawaited(SessionWork.run(initializeBackgroundExecution)
            .onError<SessionInvalidated>((error, stack) {}));
      }
    });
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
    unawaited(_sessionEvents?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    themeNotifier.dispose();
    _appLockNavigation.dispose();
    if (widget.appLock == null) _appLock.dispose();
    AppHttpClients.closeAll();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_checkSession());
  }

  Future<void> _checkSession() async {
    if (_checkingSession) return;
    _checkingSession = true;
    try {
      if (!await SessionCleanup.instance.resume()) {
        if (mounted) await context.read<AppSetupState>().recheckStatus();
        return;
      }
      if (SessionWork.authenticationRequired) {
        if (mounted) await context.read<AppSetupState>().recheckStatus();
        return;
      }
      // A lightweight identity check never reconciles files or starts sync.
      if (AppEnv.effectiveApiBaseUrl.isNotEmpty &&
          !await RecoveryResetService.instance.hasPending() &&
          await ModelSetting.getRaw(AppString.signedIn.string) == 'yes' &&
          (await getDeviceUuid()).isNotEmpty) {
        await SessionWork.run(SyncUtils.checkDeviceStatus);
      }
    } on SessionInvalidated {
      // Cleanup owns navigation and durable retry state.
    } catch (error) {
      logger.warning('Identity check will retry: ${error.runtimeType}');
    } finally {
      _checkingSession = false;
    }
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
    return ChangeNotifierProvider.value(
        value: _appLock,
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (context, ThemeMode currentMode, child) {
            return MaterialApp(
              builder: (context, child) => AppLockGate(
                  controller: _appLock,
                  cleanup: context.watch<AppSetupState>().currentStep ==
                          SetupStep.sessionCleanup
                      ? const PageSessionCleanup()
                      : null,
                  child: child ?? const SizedBox.shrink()),
              navigatorKey: _navigationKey,
              navigatorObservers: [_appLockNavigation],
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
                recoveryService: widget.recoveryService,
              ),
              debugShowCheckedModeBanner: false,
            );
          },
        ));
  }
}

class AppNavigator extends StatelessWidget {
  final Function(String?) onThemeChange;
  final RecoveryResetService? recoveryService;

  const AppNavigator({
    super.key,
    required this.onThemeChange,
    this.recoveryService,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSetupState>(
      builder: (context, setupState, child) {
        switch (setupState.currentStep) {
          case SetupStep.loading:
            return const PageLoading();
          case SetupStep.sessionCleanup:
            return const PageSessionCleanup();
          case SetupStep.recoveryReset:
            return PageRecoveryReset(service: recoveryService);
          case SetupStep.onboard:
            return const FiFeOnboardingScreen();
          case SetupStep.signin:
            return PageSignin();
          case SetupStep.checkAccessKey:
            return PageAccessKeyCheck();
          case SetupStep.generateAccessKey:
            return const PageAccessKeyNotice();
          case SetupStep.decodeAccessKey:
            return PageAccessKeyDecode(recoveryService: recoveryService);
          case SetupStep.showAccessKey:
            return const PageAccessKey(requireAcknowledgment: true);
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
