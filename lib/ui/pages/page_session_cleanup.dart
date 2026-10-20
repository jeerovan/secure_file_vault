import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/service_session_cleanup.dart';
import '../common_widgets.dart';

class PageSessionCleanup extends StatefulWidget {
  const PageSessionCleanup({super.key});

  @override
  State<PageSessionCleanup> createState() => _PageSessionCleanupState();
}

class _PageSessionCleanupState extends State<PageSessionCleanup> {
  bool _retrying = false;

  @override
  void initState() {
    super.initState();
    final running = SessionCleanup.instance.currentOperation;
    if (running != null) {
      _retrying = true;
      running.whenComplete(() {
        if (mounted) setState(() => _retrying = false);
      });
    }
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await context.read<AppSetupState>().recheckStatus();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_reset,
                        size: 48, color: theme.colorScheme.primary),
                    const SizedBox(height: 24),
                    Text(loc.localSessionCleanupTitle,
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                          _retrying
                              ? loc.localSessionCleanupInProgress
                              : loc.localSessionCleanupDescription,
                          textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 24),
                    if (_retrying)
                      const CircularProgressIndicator.adaptive()
                    else
                      FilledButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: Text(loc.tryAgain)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
