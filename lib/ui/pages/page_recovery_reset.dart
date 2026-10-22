import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/service_recovery_reset.dart';
import '../common_widgets.dart';
import 'page_access_key_display.dart';
import 'page_access_key_notice.dart';
import 'page_lost_recovery.dart';

class PageRecoveryReset extends StatefulWidget {
  const PageRecoveryReset({super.key, this.service});
  final RecoveryResetService? service;
  @override
  State<PageRecoveryReset> createState() => _PageRecoveryResetState();
}

class _PageRecoveryResetState extends State<PageRecoveryReset>
    with WidgetsBindingObserver {
  RecoveryResetService get _service =>
      widget.service ?? RecoveryResetService.instance;
  RecoveryResetView? _view;
  bool _busy = false;
  bool _confirming = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_view?.phase != RecoveryResetPhase.generation &&
          _view?.phase != RecoveryResetPhase.phrase &&
          _view?.phase != RecoveryResetPhase.registration) {
        unawaited(_refresh());
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _view?.phase != RecoveryResetPhase.phrase) {
      unawaited(_refresh());
    }
  }

  Future<void> _run(Future<RecoveryResetView> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final view = await action();
      if (!mounted) return;
      if (view.phase == RecoveryResetPhase.bootstrap) {
        await context.read<AppSetupState>().recheckStatus();
        return;
      }
      setState(() => _view = view);
      if (view.phase == RecoveryResetPhase.registration) {
        await context.read<AppSetupState>().registerDevice();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    if (_confirming) return;
    await _run(_service.refresh);
  }

  Future<void> _confirm() async {
    if (_busy || _confirming) return;
    setState(() => _confirming = true);
    final accepted = await confirmVaultReset(context);
    if (!mounted) return;
    setState(() => _confirming = false);
    if (accepted) {
      await _run(_service.confirm);
    }
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _service.prepareSignin();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _view = const RecoveryResetView(RecoveryResetPhase.unavailable));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discard() async {
    if (_busy || _confirming) return;
    setState(() => _confirming = true);
    final loc = AppLocalizations.of(context)!;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              scrollable: true,
              title: Text(loc.recoveryResetDiscard),
              content: Text(loc.recoveryResetDiscardBody),
              actions: [
                TextButton(
                    autofocus: true,
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(loc.cancel)),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(loc.recoveryResetDiscard)),
              ],
            ));
    if (!mounted) return;
    setState(() => _confirming = false);
    if (accepted == true) {
      await _run(_service.discardUnavailableStaging);
    }
  }

  String _date(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    final loc = MaterialLocalizations.of(context);
    return '${loc.formatFullDate(date)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context))}';
  }

  Widget _progress() {
    final loc = AppLocalizations.of(context)!;
    final view = _view;
    final phase = view?.phase;
    final waiting = phase == RecoveryResetPhase.waiting;
    final expiring = view?.error == 'confirmation_expiring';
    final body = switch (phase) {
      RecoveryResetPhase.waiting => loc.recoveryResetPendingBody,
      RecoveryResetPhase.confirmation => expiring
          ? loc.recoveryResetConfirmationWait
          : loc.recoveryResetNeedsConfirmation,
      RecoveryResetPhase.signIn => view?.email == null
          ? loc.recoveryResetSignin
          : loc.recoveryResetSigninAs('\u2068${view!.email}\u2069'),
      RecoveryResetPhase.missingKeys => loc.recoveryResetMissingKeys,
      _ => view == null ? loc.recoveryResetStarting : loc.pleaseTryAgain,
    };
    return Scaffold(
      appBar: AppBar(
          title: Text(loc.lostRecoveryPhrase),
          automaticallyImplyLeading: false),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(waiting ? Icons.cloud_sync_outlined : Icons.lock_reset,
                    size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 24),
                Semantics(
                    liveRegion: true,
                    child: Column(children: [
                      Text(
                          waiting
                              ? loc.recoveryResetPendingTitle
                              : loc.lostRecoveryPhrase,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Text(body, textAlign: TextAlign.center),
                    ])),
                if (waiting &&
                    view?.notBefore != null &&
                    view!.notBefore! >
                        DateTime.now().millisecondsSinceEpoch) ...[
                  const SizedBox(height: 16),
                  Text(loc.recoveryResetWaitUntil(_date(view.notBefore!)),
                      textAlign: TextAlign.center)
                ],
                if (waiting && view?.error != null ||
                    view?.error?.startsWith('storage_') == true) ...[
                  const SizedBox(height: 16),
                  Text(loc.recoveryResetStorageBlocked,
                      textAlign: TextAlign.center)
                ],
                if (expiring && view?.expiresAt != null) ...[
                  const SizedBox(height: 16),
                  Text(
                      loc.recoveryResetConfirmationUntil(
                          _date(view!.expiresAt!)),
                      textAlign: TextAlign.center)
                ],
                const SizedBox(height: 24),
                if (_busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16)
                ],
                if (phase == RecoveryResetPhase.confirmation && !expiring)
                  FilledButton(
                      onPressed: _busy || _confirming ? null : _confirm,
                      child: Text(loc.recoveryResetContinue)),
                if (phase == RecoveryResetPhase.signIn)
                  FilledButton(
                      onPressed: _busy ? null : _signIn,
                      child: Text(loc.recoveryResetDiscard)),
                if (view?.canReturn == true)
                  FilledButton(
                      onPressed: _busy ? null : _discard,
                      child: Text(loc.recoveryResetDiscard)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: _busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                    label: Text(loc.tryAgain)),
              ],
            )),
      ))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phrase = _view?.phase == RecoveryResetPhase.phrase;
    final generation = _view?.phase == RecoveryResetPhase.generation;
    return AnimatedSwitcher(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        child: KeyedSubtree(
            key: ValueKey(generation
                ? 'generation'
                : phrase
                    ? 'phrase'
                    : 'progress'),
            child: phrase
                ? PageAccessKey(
                    requireAcknowledgment: true,
                    onAcknowledged: () => _run(_service.acknowledgePhrase))
                : generation
                    ? PageAccessKeyNotice(
                        busy: _busy,
                        onGenerate: () => _run(_service.generateKeys))
                    : _progress()));
  }
}
