import 'dart:io';
import 'dart:ui';

import 'package:file_vault_bb/ui/pages/page_access_key_check.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_device_register.dart';
import 'package:file_vault_bb/ui/pages/page_welcome.dart';
import 'package:workmanager/workmanager.dart';

import '../models/model_setting.dart';
import '../services/service_logger.dart';
import '../storage/storage_secure.dart';
import '../storage/storage_sqlite.dart';
import '../ui/common_widgets.dart';
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
import 'utils/utils_sync.dart';

// Mobile-specific callback - must be top-level function
@pragma('vm:entry-point')
void backgroundTaskDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await StorageSqlite.initialize(mode: ExecutionMode.appBackground);
      await initializeDependencies(mode: ExecutionMode.appBackground);
    } catch (e, s) {
      AppLogger(prefixes: ["Background"])
          .error("Initialize failed", error: e, stackTrace: s);
      return Future.value(false);
    }
    try {
      switch (taskName) {
        case DataSync.syncTaskId:
          await SyncUtils().syncRootFolders(inBackground: true);
          break;
      }
      return Future.value(true);
    } catch (e) {
      return Future.value(false);
    }
  });
}

final logger = AppLogger(prefixes: ["Main"]);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageSqlite.initialize(mode: ExecutionMode.appForeground);
  await initializeInParallel();
  SecureStorage prefs = SecureStorage();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AppSetupState(prefs),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> initializeInParallel() async {
  await Future.wait([
    initializeDependencies(mode: ExecutionMode.appForeground),
    initializeBackgroundSync()
  ]);
}

Future<void> initializeBackgroundSync() async {
  //initialize background sync
  await DataSync.initialize();
  logger.info("initialized datasync");
}

// --- Main Application Widget ---

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;

  final logger = AppLogger(prefixes: ["MainApp"]);

  @override
  void initState() {
    super.initState();
    // Load the theme from saved preferences
    String savedTheme = ModelSetting.get(AppString.theme.string);
    switch (savedTheme) {
      case "light":
        _themeMode = ThemeMode.light;
        break;
      case "dark":
        _themeMode = ThemeMode.dark;
        break;
      default:
        // Default to system theme
        _themeMode = ThemeMode.system;
        break;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    logger.info("App State:$state");
    if (Platform.isIOS || Platform.isAndroid) {
      if (state == AppLifecycleState.resumed) {
        context.read<AppSetupState>().recheckStatus();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Toggle between light and dark modes
  Future<void> _onThemeChange(String? theme) async {
    setState(() {
      switch (theme) {
        case "light":
          _themeMode = ThemeMode.light;
          break;
        case "dark":
          _themeMode = ThemeMode.dark;
          break;
        default:
          _themeMode = ThemeMode.system;
          break;
      }
    });
    if (theme == null) {
      await ModelSetting.delete(AppString.theme.string);
    } else {
      await ModelSetting.set(AppString.theme.string, theme);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: _themeMode,
      // Uses system theme by default
      home: AppNavigator(
        themeMode: _themeMode,
        onThemeChange: _onThemeChange,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppNavigator extends StatelessWidget {
  final ThemeMode themeMode;
  final Function(String?) onThemeChange;

  const AppNavigator({
    super.key,
    required this.themeMode,
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
          case SetupStep.explorer:
            return PageExplorer(
              themeMode: themeMode,
              onThemeChange: onThemeChange,
            );
        }
      },
    );
  }
}

class DataSync {
  static const String syncTaskId = 'dataSync';
  static final logger = AppLogger(prefixes: ["DataSync"]);
  // Initialize background sync based on platform
  static Future<void> initialize() async {
    if (Platform.isAndroid || Platform.isIOS) {
      await _initializeBackgroundForMobile();
    } else {
      // start auto sync
      SyncUtils().startAutoSync();
      logger.info("Started autosync");
    }
  }

  // Mobile-specific initialization using Workmanager
  static Future<void> _initializeBackgroundForMobile() async {
    await Workmanager().initialize(backgroundTaskDispatcher);
    await Workmanager().registerPeriodicTask(
      syncTaskId,
      syncTaskId,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
        requiresStorageNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: Duration(minutes: 15),
    );
    logger.info("Background Task Registered");
  }
}
