import 'dart:io';
import 'dart:ui';

import 'package:file_vault_bb/services/service_events.dart';
import 'package:file_vault_bb/services/service_foreground.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/model_setting.dart';
import '../../services/service_locale.dart';
import '../../services/service_logger.dart';
import '../../utils/common.dart';
import '../../utils/enums.dart';
import '../common_widgets.dart';

class SettingsPage extends StatefulWidget {
  final Function(String?) onThemeChange;

  const SettingsPage({
    super.key,
    required this.onThemeChange,
  });

  @override
  SettingsPageState createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> {
  final logger = AppLogger(prefixes: ["Settings"]);
  bool isAuthSupported = false;
  bool isAuthEnabled = false;
  bool loggingEnabled =
      ModelSetting.get(AppString.loggingEnabled.string, defaultValue: "no") ==
          "yes";
  bool quickSyncEnabled = ModelSetting.get(
          AppString.syncWithNotification.string,
          defaultValue: "yes") ==
      "yes";
  late bool isDarkMode;
  String? emailId = "";

  @override
  void initState() {
    isDarkMode = ModelSetting.get(AppString.theme.string) == ""
        ? PlatformDispatcher.instance.platformBrightness == Brightness.dark
        : ModelSetting.get(AppString.theme.string) == "dark";
    super.initState();
    _initializeData();
  }

  Future<void> _initializeData() async {
    String? signedEmailId = await getSignedInEmailId();
    setState(() {
      if (signedEmailId != null) {
        emailId = signedEmailId;
      }
    });
  }

  Future<void> setTheme(String theme) async {
    if (mounted) {
      setState(() {
        isDarkMode = theme == 'dark';
        widget.onThemeChange(theme);
      });
    }
    await ModelSetting.set(AppString.theme.string, theme);
  }

  Future<void> _setLogging(bool enable) async {
    if (enable) {
      await ModelSetting.set(AppString.loggingEnabled.string, "yes");
      EventStream().publish(AppEvent(
          type: EventType.settings,
          id: "yes",
          key: EventKey.logging,
          value: null));
    } else {
      await ModelSetting.set(AppString.loggingEnabled.string, "no");
      EventStream().publish(AppEvent(
          type: EventType.settings,
          id: "no",
          key: EventKey.logging,
          value: null));
    }
    if (mounted) {
      setState(() {
        loggingEnabled = enable;
      });
    }
  }

  Future<void> setQuickSyncWithNotification(bool enable) async {
    if (enable) {
      await ModelSetting.set(AppString.syncWithNotification.string, "yes");
      ServiceForeground.instance.start();
    } else {
      await ModelSetting.set(AppString.syncWithNotification.string, "no");
      ServiceForeground.instance.stop();
    }
    if (mounted) {
      setState(() {
        quickSyncEnabled = enable;
      });
    }
  }

  Future<void> _navigateBack() async {
    Navigator.pop(context);
  }

  Future<void> signout() async {
    context.read<AppSetupState>().logout();
    _navigateBack();
  }

  Future<void> setLocale(String localeCode) async {
    final provider = Provider.of<LocaleProvider>(context, listen: false);
    provider.setLocale(Locale(localeCode));
    await ModelSetting.set(AppString.locale.string, localeCode);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> clearLocale() async {
    final provider = Provider.of<LocaleProvider>(context, listen: false);
    // Clear locale to fallback to device default system language
    provider.clearLocale();
    await ModelSetting.delete(AppString.locale.string);
    if (mounted) {
      setState(() {});
    }
  }

  final List<_AppLanguageOption> _supportedLanguages = [
    _AppLanguageOption(
      code: 'ar',
      nativeName: 'العربية',
      locale: Locale('ar'),
    ),
    _AppLanguageOption(
      code: 'de',
      nativeName: 'Deutsch',
      locale: Locale('de'),
    ),
    _AppLanguageOption(
      code: 'el',
      nativeName: 'Ελληνικά',
      locale: Locale('el'),
    ),
    _AppLanguageOption(
      code: 'en',
      nativeName: 'English',
      locale: Locale('en'),
    ),
    _AppLanguageOption(
      code: 'es',
      nativeName: 'Español',
      locale: Locale('es'),
    ),
    _AppLanguageOption(
      code: 'fa',
      nativeName: 'فارسی',
      locale: Locale('fa'),
    ),
    _AppLanguageOption(
      code: 'fr',
      nativeName: 'Français',
      locale: Locale('fr'),
    ),
    _AppLanguageOption(
      code: 'he',
      nativeName: 'עברית',
      locale: Locale('he'),
    ),
    _AppLanguageOption(
      code: 'hi',
      nativeName: 'हिन्दी',
      locale: Locale('hi'),
    ),
    _AppLanguageOption(
      code: 'id',
      nativeName: 'Bahasa Indonesia',
      locale: Locale('id'),
    ),
    _AppLanguageOption(
      code: 'it',
      nativeName: 'Italiano',
      locale: Locale('it'),
    ),
    _AppLanguageOption(
      code: 'ja',
      nativeName: '日本語',
      locale: Locale('ja'),
    ),
    _AppLanguageOption(
      code: 'ko',
      nativeName: '한국어',
      locale: Locale('ko'),
    ),
    _AppLanguageOption(
      code: 'nl',
      nativeName: 'Nederlands',
      locale: Locale('nl'),
    ),
    _AppLanguageOption(
      code: 'pt',
      nativeName: 'Português',
      locale: Locale('pt'),
    ),
    _AppLanguageOption(
      code: 'ru',
      nativeName: 'Русский',
      locale: Locale('ru'),
    ),
    _AppLanguageOption(
      code: 'th',
      nativeName: 'ไทย',
      locale: Locale('th'),
    ),
    _AppLanguageOption(
      code: 'tr',
      nativeName: 'Türkçe',
      locale: Locale('tr'),
    ),
    _AppLanguageOption(
      code: 'uk',
      nativeName: 'Українська',
      locale: Locale('uk'),
    ),
    _AppLanguageOption(
      code: 'vi',
      nativeName: 'Tiếng Việt',
      locale: Locale('vi'),
    ),
    _AppLanguageOption(
      code: 'zh',
      nativeName: '简体中文',
      locale: Locale('zh'),
    ),
  ];

  String _normalizeLocaleCode(Locale locale) {
    final countryCode = locale.countryCode;
    if (countryCode != null && countryCode.isNotEmpty) {
      return '${locale.languageCode}-r$countryCode';
    }
    return locale.languageCode;
  }

  _AppLanguageOption? _selectedLanguageOption() {
    final savedCode = ModelSetting.get(AppString.locale.string);
    if (savedCode.isEmpty) return null;

    try {
      return _supportedLanguages.firstWhere(
        (item) => item.code == savedCode,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _showLanguagePicker(BuildContext context) async {
    final selected = _selectedLanguageOption();

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, scrollController) {
            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select language',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.separated(
                    controller: scrollController,
                    itemCount: _supportedLanguages.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _supportedLanguages[index];
                      final isSelected = selected?.code == item.code;

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        title: Text(item.nativeName),
                        trailing: isSelected
                            ? const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              )
                            : null,
                        onTap: () {
                          setLocale(_normalizeLocaleCode(item.locale));
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(
        context)!; // Extract localizations once for cleaner code
    final surfaceColor = Theme.of(context).colorScheme.surfaceContainerHighest;

    return CrossPlatformBackHandler(
      canPop: true,
      onManualBack: _navigateBack,
      child: Scaffold(
          body: Column(
        children: [
          Expanded(
            child: ListView(
              reverse: true,
              padding: const EdgeInsets.all(8.0),
              children: <Widget>[
                ListTile(
                  leading: const Icon(LucideIcons.sunMoon, color: Colors.grey),
                  title: Text(loc.theme), // Changed from "Theme"
                  horizontalTitleGap: 24.0,
                  onTap: () => setTheme(isDarkMode ? 'light' : 'dark'),
                  trailing: IconButton(
                    tooltip: loc.themeTooltip, // Changed from "Day/night theme"
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: RotationTransition(
                            turns: Tween<double>(begin: 0.75, end: 1.0)
                                .animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        isDarkMode ? Icons.light_mode : Icons.dark_mode,
                        key: ValueKey(isDarkMode ? 'dark' : 'light'),
                        color: isDarkMode ? Colors.orange : Colors.black,
                      ),
                    ),
                    onPressed: () => setTheme(isDarkMode ? 'light' : 'dark'),
                  ),
                ),
                if (Platform.isAndroid || Platform.isIOS)
                  ListTile(
                    leading:
                        const Icon(LucideIcons.refreshCcw, color: Colors.grey),
                    title: Text("Quick Sync Notification"),
                    horizontalTitleGap: 24.0,
                    trailing: Transform.scale(
                      scale: 0.7,
                      child: Switch(
                        value: quickSyncEnabled,
                        onChanged: setQuickSyncWithNotification,
                      ),
                    ),
                  ),
                ListTile(
                  leading: const Icon(LucideIcons.list, color: Colors.grey),
                  title: Text(loc.logging), // Changed from "Logging"
                  horizontalTitleGap: 24.0,
                  trailing: Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: loggingEnabled,
                      onChanged: _setLogging,
                    ),
                  ),
                ),
                ListTile(
                  leading:
                      const Icon(LucideIcons.languages, color: Colors.grey),
                  title: Text(loc.language),
                  horizontalTitleGap: 24.0,
                  subtitle: Text(
                    _selectedLanguageOption()?.nativeName ?? 'Tap to select',
                  ),
                  onTap: () => _showLanguagePicker(context),
                  trailing: _selectedLanguageOption() != null
                      ? IconButton(
                          onPressed: () {
                            clearLocale();
                          },
                          icon: const Icon(LucideIcons.rotateCcw))
                      : null,
                ),
                ListTile(
                  leading: const Icon(LucideIcons.bug, color: Colors.grey),
                  trailing:
                      const Icon(LucideIcons.chevronRight, color: Colors.grey),
                  title: Text(loc.reportIssue), // Changed from "Report Issue"
                  horizontalTitleGap: 24.0,
                  onTap: () => _redirectToIssues(),
                ),
                ListTile(
                  leading: const Icon(LucideIcons.github, color: Colors.grey),
                  title: Text(loc.sourceCode), // Changed from "Source Code"
                  horizontalTitleGap: 24.0,
                  onTap: () => _redirectToGithub(),
                ),
                if (Platform.isAndroid || Platform.isIOS)
                  ListTile(
                    leading:
                        const Icon(LucideIcons.monitor, color: Colors.grey),
                    title: Text(loc.desktopApp), // Changed from "Desktop App"
                    horizontalTitleGap: 24.0,
                    onTap: () => _redirectToOtherApps(),
                  ),
                if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
                  ListTile(
                    leading:
                        const Icon(LucideIcons.smartphone, color: Colors.grey),
                    title: Text(loc.mobileApp), // Changed from "Mobile App"
                    horizontalTitleGap: 24.0,
                    onTap: () => _redirectToOtherApps(),
                  ),
                ListTile(
                  leading: const Icon(LucideIcons.star, color: Colors.grey),
                  title: Text(loc.leaveReview), // Changed from "Leave a review"
                  horizontalTitleGap: 24.0,
                  onTap: () => _redirectToFeedback(),
                ),
                ListTile(
                  leading: const Icon(LucideIcons.share2, color: Colors.grey),
                  title: Text(loc.share), // Changed from "Share"
                  horizontalTitleGap: 24.0,
                  onTap: () {
                    _share();
                  },
                ),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      final version = snapshot.data?.version ?? '';
                      return ListTile(
                        leading:
                            const Icon(LucideIcons.info, color: Colors.grey),
                        horizontalTitleGap: 24.0,
                        title: Text(
                            "${loc.versionLabel}$version"), // Changed from "Version: $version"
                        onTap: null,
                      );
                    } else {
                      return ListTile(
                        leading: Icon(LucideIcons.info, color: Colors.grey),
                        title: Text(loc.loading), // Changed from "Loading..."
                        horizontalTitleGap: 24.0,
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(LucideIcons.user, color: Colors.grey),
                  title: Text(emailId != null ? emailId! : ""),
                  horizontalTitleGap: 24.0,
                  trailing: OutlinedButton(
                    onPressed: () {
                      signout();
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFBDBDBD)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(loc.signOut), // Changed from "Sign out"
                  ),
                )
              ],
            ),
          ),
          buildBottomAppBar(
              color: surfaceColor,
              leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: _navigateBack),
              title: Text(loc.settingsPageTitle), // Changed from "Settings"
              actions: [])
        ],
      )),
    );
  }

  void _redirectToGithub() {
    const url = "https://github.com/jeerovan/secure_file_vault";
    openURL(url);
  }

  void _redirectToIssues() {
    const url = "https://github.com/jeerovan/secure_file_vault/issues";
    openURL(url);
  }

  void _redirectToOtherApps() {
    const url = "https://fife.jeero.one";
    openURL(url);
  }

  void _redirectToFeedback() {
    const url =
        'https://play.google.com/store/apps/details?id=com.jeerovan.fife';
    // Use your package name
    openURL(url);
  }

  Future<void> _share() async {
    const String appLink =
        'https://play.google.com/store/apps/details?id=com.jeerovan.fife';
    SharePlus.instance.share(ShareParams(uri: Uri.parse(appLink)));
  }
}

class _AppLanguageOption {
  final String code;
  final String nativeName;
  final Locale locale;

  const _AppLanguageOption({
    required this.code,
    required this.nativeName,
    required this.locale,
  });
}
