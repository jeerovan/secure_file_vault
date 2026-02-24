import 'dart:io';
import 'dart:ui';

import 'package:file_vault_bb/ui/pages/page_access_key_check.dart';
import 'package:file_vault_bb/ui/pages/page_access_key_decode.dart';
import 'package:file_vault_bb/ui/pages/page_device_register.dart';

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

final logger = AppLogger(prefixes: ["main"]);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await StorageSqlite.initialize(mode: ExecutionMode.appForeground);
  await initializeSupabase();
  SecureStorage prefs = SecureStorage();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => FontSizeController(),
        ),
        ChangeNotifierProvider(
          create: (_) => AppSetupState(prefs),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

// --- Main Application Widget ---

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  ThemeMode _themeMode = ThemeMode.system;
  late bool _isDarkMode;

  final logger = AppLogger(prefixes: ["MainApp"]);

  @override
  void initState() {
    super.initState();
    // Load the theme from saved preferences
    String? savedTheme = ModelSetting.get("theme", null);
    switch (savedTheme) {
      case "light":
        _themeMode = ThemeMode.light;
        _isDarkMode = false;
        break;
      case "dark":
        _themeMode = ThemeMode.dark;
        _isDarkMode = true;
        break;
      default:
        // Default to system theme
        _themeMode = ThemeMode.system;
        _isDarkMode =
            PlatformDispatcher.instance.platformBrightness == Brightness.dark;
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
  Future<void> _onThemeToggle() async {
    setState(() {
      _themeMode = _isDarkMode ? ThemeMode.light : ThemeMode.dark;
      _isDarkMode = !_isDarkMode;
    });
    await ModelSetting.set("theme", _isDarkMode ? "dark" : "light");
  }

  @override
  Widget build(BuildContext context) {
    final textScaler = Provider.of<FontSizeController>(context).textScaler;
    return MaterialApp(
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
          ),
          child: child!,
        );
      },
      theme: AppThemes.lightTheme,
      darkTheme: AppThemes.darkTheme,
      themeMode: _themeMode,
      // Uses system theme by default
      home: AppNavigator(
        themeMode: _themeMode,
        onThemeToggle: _onThemeToggle,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppNavigator extends StatelessWidget {
  final ThemeMode themeMode;
  final VoidCallback onThemeToggle;

  const AppNavigator({
    super.key,
    required this.themeMode,
    required this.onThemeToggle,
  });

  @override
  Widget build(BuildContext context) {
    bool isLargeScreen = false;
    if (isDebugEnabled) {
      isLargeScreen = MediaQuery.of(context).size.width > 600;
    } else {
      isLargeScreen =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    }

    return Consumer<AppSetupState>(
      builder: (context, setupState, child) {
        switch (setupState.currentStep) {
          case SetupStep.loading:
            return const PageLoading();
          case SetupStep.signin:
            return PageSignin();
          case SetupStep.checkAccessKey:
            return PageAccessKeyCheck();
          case SetupStep.generateAccessKey:
            return const PageAccessKeyNotice(
              runningOnDesktop: false,
            );
          case SetupStep.decodeAccessKey:
            return PageAccessKeyDecode(runningOnDesktop: false);
          case SetupStep.showAccessKey:
            return const PageAccessKey(runningOnDesktop: false);
          case SetupStep.registerDevice:
            return PageRegisterDevice();
          case SetupStep.manageDevices:
            return const PageDevices();
          case SetupStep.storagePermission:
            return const StoragePermissionPage();
          /* case SetupStep.planSelection:
            return const PlanSelectionScreen(); */
          case SetupStep.complete:
            return PageExplorer(
              themeMode: themeMode,
              onThemeToggle: onThemeToggle,
            );
        }
      },
    );
  }
}
