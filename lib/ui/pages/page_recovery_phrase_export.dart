import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../services/service_app_lock.dart';
import '../../services/service_recovery_phrase.dart';
import '../../services/service_session_work.dart';
import '../thumb_reach_list.dart';

/// Settings-only viewing/export. This page never enters key setup/registration.
class RecoveryPhraseExportPage extends StatefulWidget {
  const RecoveryPhraseExportPage(
      {super.key, required this.authorization, this.service});
  final AppLockAuthorization authorization;
  final RecoveryPhraseService? service;

  @override
  State<RecoveryPhraseExportPage> createState() =>
      _RecoveryPhraseExportPageState();
}

class _RecoveryPhraseExportPageState extends State<RecoveryPhraseExportPage> {
  final _reach = ThumbReachScrollController();
  late final RecoveryPhraseService _service;
  VoidCallback? _stopSessionWatch;
  String? _phrase;
  bool _started = false, _revoked = false, _failed = false;
  bool _copying = false, _saving = false;
  AppLockAuthorization get _proof => widget.authorization;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? RecoveryPhraseService();
    _proof.controller.addListener(_checkVisibility);
    try {
      _stopSessionWatch = SessionWork.onInvalidated(_conceal);
    } on SessionInvalidated {
      _conceal();
    }
    _checkVisibility();
  }

  void _checkVisibility() {
    if (!mounted || _revoked) return;
    if (!_proof.isValid || _started && !_proof.controller.foreground) {
      _conceal();
    } else if (!_started && _proof.available) {
      _started = true;
      unawaited(_load());
    }
  }

  void _conceal() {
    if (!mounted || _revoked) return;
    _proof.revoke();
    setState(() {
      _revoked = true;
      _phrase = null;
    });
    // No outgoing transition may retain the secret's pixels. Root privacy also
    // covers native snapshots, and the existing Settings route stays in place.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && route.isActive) {
        Navigator.of(context).removeRoute(route);
      }
    });
  }

  Future<void> _load() async {
    if (_revoked || !_proof.available) return;
    setState(() => _failed = false);
    try {
      final phrase = await _service.read(_proof);
      if (mounted && !_revoked && _proof.available) {
        setState(() => _phrase = phrase);
      }
    } on SessionInvalidated {
      _conceal();
    } on AppLockAccessDenied {
      _conceal();
    } catch (_) {
      // Never include key material or a decoding exception in logs/artifacts.
      if (mounted && !_revoked) setState(() => _failed = true);
    }
  }

  Future<void> _copy() async {
    final phrase = _phrase;
    if (_copying || _saving || phrase == null || !_proof.available) return;
    setState(() => _copying = true);
    try {
      await _service.copy(_proof, phrase);
      if (mounted && !_revoked && _proof.available) {
        _message(AppLocalizations.of(context)!.copiedToClipboard);
      }
    } on SessionInvalidated {
      _conceal();
    } on AppLockAccessDenied {
      _conceal();
    } catch (_) {
      if (mounted && !_revoked) {
        _message(AppLocalizations.of(context)!.pleaseTryAgain);
      }
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _save() async {
    final phrase = _phrase;
    if (_copying || _saving || phrase == null || !_proof.available) return;
    setState(() => _saving = true);
    try {
      final saved = await _service.save(
          _proof, phrase, AppLocalizations.of(context)!.downloadRecoveryPhrase);
      if (saved && mounted && !_revoked && _proof.available) {
        _message(AppLocalizations.of(context)!.fileSavedSuccessfully);
      }
    } on SessionInvalidated {
      _conceal();
    } on AppLockAccessDenied {
      _conceal();
    } catch (_) {
      if (mounted && !_revoked) {
        _message(AppLocalizations.of(context)!.pleaseTryAgain);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  @override
  void dispose() {
    _phrase = null;
    _proof.revoke();
    _proof.controller.removeListener(_checkVisibility);
    _stopSessionWatch?.call();
    _reach.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final phrase = _revoked ? null : _phrase;
    final usable = phrase != null && _proof.available && !_copying && !_saving;
    const progress = SizedBox.square(
        dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
    return PrimaryScrollController(
        controller: _reach,
        child: Scaffold(
            appBar: AppBar(title: Text(loc.recoveryPhraseLabel)),
            body: Column(children: [
              Expanded(
                  child: ThumbReachListView(
                      controller: _reach,
                      padding: const EdgeInsets.all(24),
                      children: [
                    Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(loc.recoveryPhraseExportWarning,
                                      style: theme.textTheme.bodyLarge),
                                  const SizedBox(height: 24),
                                  if (phrase != null)
                                    Container(
                                        key: const ValueKey(
                                            'recovery-phrase-words'),
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                            color: theme.colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color: theme.colorScheme
                                                    .outlineVariant)),
                                        child: Text(phrase,
                                            textDirection: TextDirection.ltr,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(height: 1.6))),
                                  if (phrase == null && !_failed && !_revoked)
                                    const Center(child: progress),
                                  if (_failed && !_revoked) ...[
                                    Semantics(
                                        liveRegion: true,
                                        child: Text(
                                            loc.recoveryPhraseUnavailable)),
                                    const SizedBox(height: 16),
                                    OutlinedButton(
                                        onPressed: _load,
                                        child: Text(loc.tryAgain)),
                                  ],
                                ]))),
                  ])),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FilledButton.icon(
                                key: const ValueKey('recovery-phrase-download'),
                                onPressed: usable ? _save : null,
                                icon: _saving
                                    ? progress
                                    : const Icon(LucideIcons.download),
                                label: Text(loc.downloadAsTextFile)),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                                key: const ValueKey('recovery-phrase-copy'),
                                onPressed: usable ? _copy : null,
                                icon: _copying
                                    ? progress
                                    : const Icon(LucideIcons.copy),
                                label: Text(loc.copy)),
                          ]))),
            ])));
  }
}

class RecoveryPhraseSettingsAction extends StatefulWidget {
  const RecoveryPhraseSettingsAction(
      {super.key, required this.controller, this.service});
  final AppLockController controller;
  final RecoveryPhraseService? service;

  @override
  State<RecoveryPhraseSettingsAction> createState() =>
      _RecoveryPhraseSettingsActionState();
}

class _RecoveryPhraseSettingsActionState
    extends State<RecoveryPhraseSettingsAction> {
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    final route = ModalRoute.of(context);
    final revision = SessionWork.revision;
    AppLockAuthorization? proof;
    try {
      await SessionWork.checkpoint();
      if (!mounted) return;
      final loc = AppLocalizations.of(context)!;
      proof = await widget.controller.authorizeSensitiveAction(AppLockPrompt(
          reason: loc.recoveryPhraseExportAuth,
          title: loc.appLockTitle,
          hint: loc.appLockAuthHint,
          cancel: loc.cancel));
      await SessionWork.checkpoint();
      if (proof == null ||
          !proof.isValid ||
          !mounted ||
          revision != SessionWork.revision ||
          route?.isCurrent != true) {
        return;
      }
      final page = RecoveryPhraseExportPage(
          authorization: proof, service: widget.service);
      await Navigator.of(context).push<void>(
          MediaQuery.disableAnimationsOf(context)
              ? PageRouteBuilder<void>(
                  pageBuilder: (context, animation, secondaryAnimation) => page,
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero)
              : MaterialPageRoute<void>(builder: (_) => page));
    } on SessionInvalidated {
      // Normal root session handling owns sign-out/reauthentication navigation.
    } finally {
      proof?.revoke();
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (!controller.ready || !controller.enabled) {
          return const SizedBox.shrink();
        }
        final loc = AppLocalizations.of(context)!;
        return ListTile(
            key: const ValueKey('download-recovery-phrase'),
            leading: const Icon(LucideIcons.key, color: Colors.grey),
            horizontalTitleGap: 24,
            title: Text(loc.downloadRecoveryPhrase),
            subtitle: Text(loc.recoveryPhraseExportHint),
            trailing: _opening
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(LucideIcons.chevronRight),
            onTap: _opening ||
                    controller.busy ||
                    controller.concealed ||
                    !SessionWork.active ||
                    SessionWork.authenticationRequired
                ? null
                : _open);
      });
}
