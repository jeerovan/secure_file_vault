import 'dart:io';
import 'dart:ui';

import 'package:file_vault_bb/services/service_events.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/model_setting.dart';
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
  late bool isDarkMode;

  @override
  void initState() {
    isDarkMode = ModelSetting.get(AppString.theme.string) == ""
        ? PlatformDispatcher.instance.platformBrightness == Brightness.dark
        : ModelSetting.get(AppString.theme.string) == "dark";
    super.initState();
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

  Future<void> _navigateBack() async {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
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
                  title: const Text("Theme"),
                  horizontalTitleGap: 24.0,
                  onTap: () => setTheme(isDarkMode ? 'light' : 'dark'),
                  trailing: IconButton(
                    tooltip: "Day/night theme",
                    icon: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        // Use both fade and rotation transitions
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
                        // Unique key for AnimatedSwitcher
                        color: isDarkMode ? Colors.orange : Colors.black,
                      ),
                    ),
                    onPressed: () => setTheme(isDarkMode ? 'light' : 'dark'),
                  ),
                ),
                ListTile(
                  leading: const Icon(LucideIcons.star, color: Colors.grey),
                  title: const Text('Leave a review'),
                  horizontalTitleGap: 24.0,
                  onTap: () => _redirectToFeedback(),
                ),
                ListTile(
                  leading: const Icon(LucideIcons.share2, color: Colors.grey),
                  title: const Text('Share'),
                  horizontalTitleGap: 24.0,
                  onTap: () {
                    _share();
                  },
                ),
                if (Platform.isAndroid || Platform.isIOS)
                  ListTile(
                    leading:
                        const Icon(LucideIcons.monitor, color: Colors.grey),
                    title: const Text('Desktop App'),
                    horizontalTitleGap: 24.0,
                    onTap: () => _redirectToOtherApps(),
                  ),
                if (Platform.isLinux || Platform.isWindows || Platform.isMacOS)
                  ListTile(
                    leading:
                        const Icon(LucideIcons.monitor, color: Colors.grey),
                    title: const Text('Mobile App'),
                    horizontalTitleGap: 24.0,
                    onTap: () => _redirectToOtherApps(),
                  ),
                ListTile(
                  leading: const Icon(LucideIcons.list, color: Colors.grey),
                  title: const Text("Logging"),
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
                  leading: const Icon(LucideIcons.github, color: Colors.grey),
                  trailing:
                      const Icon(LucideIcons.chevronRight, color: Colors.grey),
                  title: const Text('Source Code'),
                  horizontalTitleGap: 24.0,
                  onTap: () => _redirectToGithub(),
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
                        title: Text('Version: $version'),
                        onTap: null,
                      );
                    } else {
                      return const ListTile(
                        leading: Icon(LucideIcons.info, color: Colors.grey),
                        title: Text('Loading...'),
                        horizontalTitleGap: 24.0,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          buildBottomAppBar(
              color: surfaceColor,
              leading: IconButton(
                  tooltip: 'Back',
                  icon: const Icon(LucideIcons.arrowLeft),
                  onPressed: _navigateBack),
              title: Text("Settings"),
              actions: [])
        ],
      )),
    );
  }

  void _redirectToGithub() {
    const url = "https://github.com/jeerovan/secure_file_vault";
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
