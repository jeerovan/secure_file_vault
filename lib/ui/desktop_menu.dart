import 'dart:io';

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import '../services/service_desktop_menu.dart';

/// Outside AppLockGate so hiding private UI never suspends menu-bar sync.
class DesktopMenu extends StatefulWidget {
  const DesktopMenu({super.key, required this.child});
  final Widget child;
  @override
  State<DesktopMenu> createState() => _DesktopMenuState();
}

class _DesktopMenuState extends State<DesktopMenu> {
  DesktopMenuController? _controller;

  @override
  void initState() {
    super.initState();
    if (Platform.isMacOS || Platform.isWindows) {
      _controller = DesktopMenuController()..start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = AppLocalizations.of(context)!;
    _controller?.setLabels({
      'open': loc.menuBarOpen,
      'sync': loc.sync,
      'syncing': loc.quickSyncNotificationInProgress,
      'quit': loc.menuBarQuit,
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
