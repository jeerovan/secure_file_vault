import 'dart:async';

import '../../l10n/app_localizations.dart';
import '../../services/service_logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../common_widgets.dart';
import '../../utils/enums.dart';
import '../../services/service_session_work.dart';
import '../../services/service_vault_key_setup.dart';

class PageAccessKeyNotice extends StatefulWidget {
  const PageAccessKeyNotice(
      {super.key, this.onGenerate, this.busy = false, this.service});

  final Future<void> Function()? onGenerate;
  final bool busy;
  final VaultKeySetupService? service;

  @override
  State<PageAccessKeyNotice> createState() => _PageAccessKeyNoticeState();
}

class _PageAccessKeyNoticeState extends State<PageAccessKeyNotice> {
  AppLogger logger = AppLogger(prefixes: ["PageAccessKeyNotice"]);
  VaultKeySetupService get service =>
      widget.service ?? VaultKeySetupService.instance;
  bool processing = false;
  String appName = AppString.appName.string;

  @override
  void initState() {
    super.initState();
    if (widget.onGenerate == null) {
      processing = true;
      unawaited(_resume());
    }
  }

  Future<void> generateKeys() async {
    if (widget.onGenerate case final onGenerate?) {
      if (processing || widget.busy) return;
      setState(() => processing = true);
      try {
        await onGenerate();
      } finally {
        if (mounted) setState(() => processing = false);
      }
      return;
    }
    return SessionWork.run(_generateKeys);
  }

  Future<void> _generateKeys() async {
    if (processing) return;
    setState(() {
      processing = true;
    });
    try {
      final result = await service.generate();
      await _apply(result, attempted: true);
    } on SessionInvalidated {
      // Session cleanup owns the root transition.
    } catch (e, s) {
      logger.error("generateKeys", error: e, stackTrace: s);
    }
    if (mounted) {
      setState(() {
        processing = false;
      });
    }
  }

  Future<void> _resume() async {
    try {
      if (await service.hasPending()) await _apply(await service.resume());
    } on SessionInvalidated {
      // Never resume private candidates into a replaced login.
    } catch (e, s) {
      logger.error('resumeKeys', error: e, stackTrace: s);
    } finally {
      if (mounted) setState(() => processing = false);
    }
  }

  Future<void> _apply(VaultKeySetupResult result,
      {bool attempted = false}) async {
    if (!mounted) return;
    final setup = context.read<AppSetupState>();
    switch (result.phase) {
      case VaultKeySetupPhase.phrase:
        await setup.showAccessKeys();
      case VaultKeySetupPhase.registration:
        await setup.registerDevice();
      case VaultKeySetupPhase.recovery:
        await setup.recheckStatus();
      case VaultKeySetupPhase.generation:
      case VaultKeySetupPhase.unavailable:
        if (attempted && mounted) {
          displaySnackBar(context,
              message: AppLocalizations.of(context)!.pleaseTryAgain,
              seconds: 2);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = processing || widget.busy;
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.importantTitle),
      ),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Text(
                          AppLocalizations.of(context)!.accessKeyNoticePrimary,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          AppLocalizations.of(context)!
                              .accessKeyNoticeResponsibility(appName),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w400),
                        ),
                        const SizedBox(height: 30),
                        FilledButton(
                          onPressed: busy ? null : generateKeys,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (busy)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: DefaultTextStyle.of(context)
                                          .style
                                          .color,
                                    ),
                                  ),
                                ),
                              Flexible(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  AppLocalizations.of(context)!
                                      .showKeyConfirmation,
                                  textAlign: TextAlign.center,
                                ),
                              )),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )))),
    );
  }
}
