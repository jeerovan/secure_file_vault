import 'dart:async';

import 'package:flutter/services.dart';

import '../models/model_state.dart';
import '../utils/utils_sync.dart';
import 'service_background_execution.dart';
import 'service_events.dart';
import 'service_session_work.dart';

/// The main engine owns this controller even while its window is closed.
/// Readiness is rechecked at the action boundary; a native menu is only a view.
class DesktopMenuController {
  DesktopMenuController({
    Future<bool> Function()? ready,
    Future<bool> Function()? busy,
    Future<void> Function()? sync,
    this.channel = const MethodChannel('com.jeerovan.fife/desktop'),
  })  : _ready = ready ?? isVaultSyncReady,
        _busy = busy ?? _hasWork,
        _sync = sync ?? _syncVault;

  final Future<bool> Function() _ready, _busy;
  final Future<void> Function() _sync;
  final MethodChannel channel;
  Timer? _poll;
  StreamSubscription<AppEvent>? _events;
  bool _disposed = false, _checking = false, _again = false, _syncing = false;
  bool _enabled = false, _working = false;
  int _signal = 0;
  Map<String, String> _labels = {};
  Future<void> _publishing = Future.value();

  static bool get _sessionReady =>
      SessionWork.active && !SessionWork.authenticationRequired;

  static Future<bool> _hasWork() => ModelState.hasActiveLeasePrefix(
      'operation_lease:', DateTime.now().toUtc().millisecondsSinceEpoch);
  static Future<void> _syncVault() async {
    await SyncUtils().reconFolders(caller: 'MenuBar');
  }

  void start() {
    if (_poll != null || _disposed) return;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'sync') await sync();
    });
    _events = EventStream().events.listen((event) {
      if (event.type != EventType.system) return;
      _signal++;
      if (!_sessionReady ||
          event.key == EventKey.signout ||
          event.key == EventKey.sessionInvalidated) {
        _enabled = false;
        _working = false;
        _publish();
      }
      unawaited(refresh());
    });
    // Continues while hidden: onboarding can finish after construction, and
    // transfers in another execution context cannot publish this event stream.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    unawaited(refresh());
  }

  void setLabels(Map<String, String> labels) {
    _labels = Map.of(labels);
    _publish();
  }

  void _publish() {
    final payload = <String, Object>{
      ..._labels,
      'busy': (_syncing || _working) && _sessionReady,
      'syncEnabled': _enabled && _sessionReady && !_syncing && !_working,
    };
    // Keep older, slower native calls from overwriting a newer auth/busy state.
    _publishing = _publishing.then((_) async {
      if (_disposed) return;
      try {
        await channel.invokeMethod<void>('updateMenu', payload);
      } on MissingPluginException {
        // Unsupported hosts do not have a menu bar.
      } on PlatformException {
        // Retry on the next state refresh.
      }
    });
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (_checking) {
      _again = true;
      return;
    }
    _checking = true;
    final signal = _signal;
    final session = SessionWork.revision;
    try {
      final ready = _sessionReady && await _ready();
      final working = ready && await _busy();
      if (!_disposed && signal == _signal && session == SessionWork.revision) {
        _enabled = ready && _sessionReady;
        _working = working;
      }
    } catch (_) {
      _enabled = false;
      _working = false;
    } finally {
      _checking = false;
      _publish();
      if (_again && !_disposed) {
        _again = false;
        unawaited(refresh());
      }
    }
  }

  Future<void> sync() async {
    if (_disposed || _syncing || !_sessionReady) return;
    _syncing = true;
    _publish();
    try {
      await SessionWork.run(() async {
        if (!await _ready() || await _busy()) return;
        await SessionWork.checkpoint();
        if (!_disposed) await _sync();
      });
    } catch (_) {
      // Sync's normal pipeline owns retry/error reporting. A stale menu action
      // must never escape into a new session or activate private navigation.
    } finally {
      _syncing = false;
      await refresh();
    }
  }

  void dispose() {
    _disposed = true;
    _poll?.cancel();
    unawaited(_events?.cancel());
    channel.setMethodCallHandler(null);
  }
}
