import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/model_setting.dart';
import '../../services/service_recovery_reset.dart';
import '../../services/service_session_work.dart';
import '../../utils/enums.dart';
import '../common_widgets.dart';

Future<bool> confirmVaultReset(BuildContext context) async {
  final loc = AppLocalizations.of(context)!;
  return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(loc.recoveryResetConfirmTitle),
                content: Text(loc.recoveryResetConfirmBody),
                actions: [
                  TextButton(
                      autofocus: true,
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(loc.cancel)),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                          foregroundColor:
                              Theme.of(context).colorScheme.onError),
                      child: Text(loc.recoveryResetDelete)),
                ],
              )) ??
      false;
}

class PageLostRecovery extends StatefulWidget {
  const PageLostRecovery({super.key, this.service});
  final RecoveryResetService? service;
  @override
  State<PageLostRecovery> createState() => _PageLostRecoveryState();
}

class _PageLostRecoveryState extends State<PageLostRecovery> {
  bool _busy = false;
  bool _confirming = false;
  bool _started = false;
  bool _failed = false;
  bool _checking = false;
  bool _signinRequired = false;
  bool _available =
      ModelSetting.get(AppString.recoveryResetAvailable.string) == 'yes';
  RecoveryResetService get _service =>
      widget.service ?? RecoveryResetService.instance;

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
  }

  Future<void> _refreshAvailability() async {
    if (_busy || _confirming || _checking) return;
    setState(() {
      _checking = true;
      _failed = false;
    });
    try {
      final available = await _service.checkAvailability();
      if (mounted) setState(() => _available = available);
    } on RecoveryReauthenticationRequired {
      if (mounted) {
        setState(() {
          _available = false;
          _signinRequired = true;
        });
      }
    } on SessionInvalidated {
      if (mounted) await context.read<AppSetupState>().recheckStatus();
    } catch (_) {
      if (mounted) {
        setState(() {
          _available = false;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _signIn() async {
    if (_busy || _confirming || _checking) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await _service.prepareSignin();
      if (!mounted) return;
      await context.read<AppSetupState>().recheckStatus();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy || _confirming || _checking || !_available) return;
    setState(() => _confirming = true);
    final accepted = await confirmVaultReset(context);
    if (!mounted) return;
    setState(() => _confirming = false);
    if (!accepted) return;
    setState(() {
      _busy = true;
      _started = true;
      _failed = false;
    });
    try {
      final result = await _service.confirm();
      if (!mounted) return;
      if (result.phase == RecoveryResetPhase.signIn) {
        setState(() {
          _started = false;
          _available = false;
          _signinRequired = true;
        });
      } else if (await _service.hasPending()) {
        if (!mounted) return;
        await context.read<AppSetupState>().showRecoveryReset();
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          setState(() {
            _started = false;
            _failed = true;
          });
        }
      }
    } on SessionInvalidated {
      if (mounted) await context.read<AppSetupState>().recheckStatus();
    } catch (_) {
      if (mounted) {
        setState(() {
          _started = false;
          _failed = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _consequence(IconData icon, String text, {bool destructive = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              color: destructive
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return PopScope(
        canPop: !_busy && !_started,
        child: Scaffold(
          appBar: AppBar(
              title: Text(loc.lostRecoveryPhrase),
              automaticallyImplyLeading: !_started),
          body: SafeArea(
              child: Center(
                  child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loc.lostRecoveryIntro,
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 24),
                    _consequence(Icons.delete_forever_outlined,
                        loc.lostRecoveryDeleteConsequence,
                        destructive: true),
                    _consequence(Icons.devices_outlined,
                        loc.lostRecoveryDevicesConsequence),
                    _consequence(
                        Icons.logout, loc.lostRecoveryLogoutConsequence),
                    _consequence(
                        Icons.folder_outlined, loc.lostRecoveryKeepConsequence),
                    _consequence(Icons.cloud_sync_outlined,
                        loc.lostRecoveryWaitConsequence),
                    _consequence(Icons.key_outlined,
                        loc.lostRecoveryNewPhraseConsequence),
                    if (_signinRequired) ...[
                      Semantics(
                          liveRegion: true,
                          child: Text(loc.recoveryResetSigninRequired)),
                      const SizedBox(height: 16),
                    ] else if (!_available || _checking) ...[
                      Semantics(
                          liveRegion: true,
                          child: Text(_checking
                              ? loc.loading
                              : loc.recoveryResetUnavailable)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          onPressed: _checking ? null : _refreshAvailability,
                          icon: _checking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh),
                          label: Text(loc.tryAgain)),
                      const SizedBox(height: 16),
                    ],
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Semantics(
                          liveRegion: true,
                          child: Text(_signinRequired
                              ? loc.localSessionCleanupInProgress
                              : loc.recoveryResetStarting)),
                      const SizedBox(height: 16)
                    ],
                    if (_failed) ...[
                      Text(loc.pleaseTryAgain,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                      const SizedBox(height: 16)
                    ],
                    FilledButton(
                        onPressed: _busy || _confirming || _checking
                            ? null
                            : _signinRequired
                                ? _signIn
                                : _available
                                    ? _confirm
                                    : null,
                        child: Text(_signinRequired
                            ? loc.recoveryResetDiscard
                            : loc.recoveryResetContinue)),
                  ],
                )),
          ))),
        ));
  }
}
