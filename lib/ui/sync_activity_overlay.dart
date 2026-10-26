import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/model_state.dart';
import '../services/service_events.dart';
import '../services/service_session_work.dart';

/// Keeps navigation and content stationary while shared sync work is active.
class SyncActivityOverlay extends StatefulWidget {
  const SyncActivityOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<SyncActivityOverlay> createState() => _SyncActivityOverlayState();
}

class _SyncActivityOverlayState extends State<SyncActivityOverlay>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  StreamSubscription<AppEvent>? _events;
  Timer? _poll;
  late final AnimationController _stillPhase;
  bool _foreground = true;
  bool _busy = false;
  bool _checking = false;
  bool _checkAgain = false;
  int _signal = 0;

  @override
  void initState() {
    super.initState();
    // A visible, stationary phase retains indeterminate semantics when the
    // user requests reduced motion. Material still supplies the entire style.
    _stillPhase = AnimationController(vsync: this, value: 0.35);
    WidgetsBinding.instance.addObserver(this);
    _events = EventStream().events.listen(_onEvent);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _monitor();
  }

  void _monitor() {
    _poll?.cancel();
    if (!_foreground) return;
    // The service can already be running when the UI attaches, and another
    // isolate cannot publish directly to this isolate's event stream.
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    unawaited(_refresh());
  }

  void _show(bool busy) {
    if (mounted && _busy != busy) setState(() => _busy = busy);
  }

  void _onEvent(AppEvent event) {
    if (event.type != EventType.system) return;
    if (event.key == EventKey.sessionInvalidated ||
        event.key == EventKey.signout) {
      _signal++;
      _show(false);
    } else if (event.key == EventKey.running) {
      _signal++;
      _show(_foreground && SessionWork.active);
    } else if (event.key == EventKey.stopped ||
        event.key == EventKey.authenticated) {
      _signal++;
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    if (!_foreground || !SessionWork.active) {
      _show(false);
      return;
    }
    if (_checking) {
      _checkAgain = true;
      return;
    }
    _checking = true;
    final signal = _signal;
    final session = SessionWork.revision;
    try {
      // Scans, metadata and direct uploads/downloads all hold operation leases.
      // Queued retries and expired leases must not imply work is still running.
      final active = await ModelState.hasActiveLeasePrefix(
          'operation_lease:', DateTime.now().toUtc().millisecondsSinceEpoch);
      if (mounted &&
          _foreground &&
          signal == _signal &&
          session == SessionWork.revision) {
        _show(active && SessionWork.active);
      }
    } on SessionInvalidated {
      if (signal == _signal) _show(false);
    } catch (_) {
      // A transient read failure cannot complete an operation. Keep the last
      // observed state and retry; an invalid session always removes the line.
      if (!SessionWork.active) _show(false);
    } finally {
      _checking = false;
      if (_checkAgain && mounted) {
        _checkAgain = false;
        unawaited(_refresh());
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _signal++;
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _show(false);
    _monitor();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    unawaited(_events?.cancel());
    _stillPhase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Stack(fit: StackFit.expand, children: [
      widget.child,
      if (_busy)
        Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
                child: SafeArea(
                    bottom: false,
                    child: TickerMode(
                        enabled: !reduceMotion,
                        child: LinearProgressIndicator(
                          controller: reduceMotion ? _stillPhase : null,
                          semanticsLabel: AppLocalizations.of(context)!
                              .quickSyncNotificationInProgress,
                        ))))),
    ]);
  }
}
