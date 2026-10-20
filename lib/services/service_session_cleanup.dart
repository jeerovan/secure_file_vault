import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../models/model_setting.dart';
import '../models/model_profile.dart';
import '../storage/storage_secure.dart';
import '../storage/storage_sqlite.dart';
import '../utils/common.dart';
import '../utils/enums.dart';
import '../utils/utils_sync.dart';
import '../utils/utils_tasks.dart';
import 'service_background_execution.dart';
import 'service_events.dart';
import 'service_foreground.dart';
import 'service_http_clients.dart';
import 'service_logger.dart';
import 'service_reconciliation_coordinator.dart';
import 'service_session_work.dart';

class SessionCleanupAction {
  const SessionCleanupAction(this.name, this.run);
  final String name;
  final Future<void> Function() run;
}

enum SessionCleanupMode { forced, recovery, reauthenticate }

/// The marker is outside account SQLite/documents and survives partial cleanup.
/// Its revision remains after success so old work cannot write into a new login.
class SessionCleanup {
  SessionCleanup._();
  static final instance = SessionCleanup._();
  final _logger = AppLogger(prefixes: ['Session cleanup']);
  File? _marker;
  Future<bool>? _running;
  Map<String, dynamic>? _requested;
  String? _requestedFromRevision;
  String? _observedRevision;
  String? _awaitingExternalRevision;
  bool _nativeStopNeeded = false;
  bool _publicationClosing = false;

  Future<bool>? get currentOperation => _running;

  @visibleForTesting
  SessionCleanup.test({
    required File marker,
    required List<SessionCleanupAction> actions,
  })  : _marker = marker,
        _testActions = actions;

  List<SessionCleanupAction>? _testActions;

  Future<void> initialize() async {
    if (_marker == null) {
      final directory = await getApplicationSupportDirectory();
      _marker = File(p.join(directory.path, 'fife-session-state.json'));
    }
    SessionWork.readRevision = () async {
      final state = await _read();
      return SessionRevision(state['revision'] as String,
          cleanupPending: state['pending'] == true);
    };
  }

  Future<Map<String, dynamic>> _read({bool includeRequested = true}) async {
    if (includeRequested && _requested != null) return _requested!;
    if (!await _marker!.exists()) return {'revision': '', 'pending': false};
    final raw = jsonDecode(await _marker!.readAsString());
    if (raw is! Map<String, dynamic> ||
        raw['revision'] is! String ||
        raw['pending'] is! bool) {
      // Corrupt durable state must not reopen an account without cleanup.
      return {'revision': 'invalid', 'pending': true};
    }
    return raw;
  }

  Future<void> _write(Map<String, dynamic> state) async {
    await _marker!.parent.create(recursive: true);
    final temporary = File('${_marker!.path}.${const Uuid().v4()}.partial');
    try {
      await temporary.writeAsString(jsonEncode(state), flush: true);
      await temporary.rename(_marker!.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  Future<bool> get pending async {
    await initialize();
    try {
      return (await _read())['pending'] == true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> request({SessionCleanupMode mode = SessionCleanupMode.forced}) {
    if (_running case final running?) return running;
    SessionWork.check();
    final expectedRevision = SessionWork.revision;
    return _singleFlight(() async {
      await initialize();
      final requested = <String, dynamic>{
        'revision': const Uuid().v4(),
        'pending': true,
        'mode': mode.name,
        // Do not wait on a transaction owned by the work being canceled.
        'locale': ModelSetting.get(AppString.locale.string),
      };
      _publicationClosing = true;
      try {
        // Finish an already publishing file before invalidation. This lock is
        // separate from account SQLite and is released before cleanup waits on
        // canceled SQL/key-store transactions, avoiding reversed lock order.
        await _withPublicationGate(() async {
          SessionWork.check();
          final durable = await _read(includeRequested: false);
          // Join another engine's cleanup instead of replaying it over a later
          // login. The pending marker is durable before another publication.
          if (durable['pending'] == true ||
              durable['revision'] != expectedRevision) {
            return;
          }
          _requestedFromRevision = expectedRevision;
          _requested = requested;
          _invalidate(requested['revision'] as String);
          await _write(requested);
        });
      } on SessionInvalidated {
        rethrow;
      } catch (_) {
        // Preserve the existing fail-closed retry when the marker directory or
        // disk is unavailable. No publication can obtain an unusable gate.
        _requestedFromRevision ??= expectedRevision;
        _requested ??= requested;
        _invalidate(_requested!['revision'] as String);
        rethrow;
      } finally {
        _publicationClosing = false;
      }
      return _resumeLocked();
    });
  }

  /// Filesystem side effects cannot roll back with an account SQL transaction.
  /// Serialize final publication with the durable invalidation marker across
  /// app/background engines. The action must not acquire account write locks.
  Future<T> withPublication<T>(Future<T> Function() action) async {
    await initialize();
    if (_publicationClosing) throw const SessionInvalidated();
    return _withPublicationGate(() async {
      if (_publicationClosing) throw const SessionInvalidated();
      await SessionWork.checkpoint();
      return action();
    });
  }

  Future<T> _withPublicationGate<T>(Future<T> Function() action) async {
    await _marker!.parent.create(recursive: true);
    while (true) {
      Database? mutex;
      try {
        mutex = await openDatabase('${_marker!.path}.publication.sqlite',
            singleInstance: false,
            onConfigure: (db) async => db.execute('PRAGMA busy_timeout = 0'));
        await mutex.execute(
            'CREATE TABLE IF NOT EXISTS publication_mutex (id INTEGER PRIMARY KEY)');
        return await mutex.transaction((tx) async {
          await tx.rawInsert(
              'INSERT OR REPLACE INTO publication_mutex (id) VALUES (1)');
          return action();
        }, exclusive: true);
      } on DatabaseException catch (error) {
        final code = error.getResultCode();
        if (code == null || !{5, 6}.contains(code & 0xff)) rethrow;
        // Yield rather than blocking the native SQL thread while the owning
        // publisher finishes. Contending downloads also wait instead of failing.
      } finally {
        await mutex?.close();
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<bool> expiredAuthentication() async {
    final stage =
        await SecureStorage().read(key: AppString.recoveryResetStage.string);
    return request(
        mode: stage == null
            ? SessionCleanupMode.forced
            : SessionCleanupMode.reauthenticate);
  }

  /// Native foreground-service IPC is a wakeup only. The shared durable marker
  /// supplies authority, so delayed messages cannot invalidate a newer login.
  Future<void> observeExternalState() async {
    try {
      await initialize();
      final state = await _read(includeRequested: false);
      if (state['pending'] == true) {
        _awaitingExternalRevision = state['revision'] as String;
        _invalidate(_awaitingExternalRevision!);
      }
      var finished = await resume();
      if (!finished && _awaitingExternalRevision != null) {
        // Completion can arrive while this isolate is still unwinding a failed
        // lease attempt. Let that single flight clear before checking again.
        final current = await _read(includeRequested: false);
        if (current['pending'] != true) {
          await Future<void>.delayed(Duration.zero);
          finished = await resume();
        }
      }
      if (finished && _awaitingExternalRevision != null) {
        final current = await _read(includeRequested: false);
        if (current['pending'] != true) {
          _awaitingExternalRevision = null;
          EventStream().publish(AppEvent(
              type: EventType.system, id: 'signout', key: EventKey.signout));
        }
      }
    } catch (_) {
      // A failed wakeup cannot reopen cached private routes. Startup/resume and
      // the cleanup screen can retry reading the authoritative marker.
      _invalidate(_observedRevision ?? 'invalid');
    }
  }

  void _notifyForegroundApp() {
    if (Platform.isAndroid &&
        StorageSqlite.executionMode == ExecutionMode.foregroundService) {
      try {
        FlutterForegroundTask.sendDataToMain(sessionStateChangedMessage);
      } catch (_) {
        _logger.warning('Native cleanup wakeup could not be delivered');
      }
    }
  }

  Future<bool> resume() => _singleFlight(() async {
        await initialize();
        return _resumeLocked();
      });

  Future<bool> _resumeLocked() async {
    // This separate database serializes marker changes across app/service
    // isolates without waiting on a canceled account-database transaction.
    await _marker!.parent.create(recursive: true);
    final mutex = await openDatabase('${_marker!.path}.lock.sqlite',
        singleInstance: false,
        onConfigure: (db) async => db.execute('PRAGMA busy_timeout = 1000'));
    bool result;
    try {
      await mutex.execute(
          'CREATE TABLE IF NOT EXISTS cleanup_mutex (id INTEGER PRIMARY KEY)');
      result = await mutex.transaction((tx) async {
        await tx
            .rawInsert('INSERT OR REPLACE INTO cleanup_mutex (id) VALUES (1)');
        final state = await _withPublicationGate(() async {
          var state = await _read(includeRequested: false)
              .catchError((_) => <String, dynamic>{
                    'revision': 'invalid',
                    'pending': true,
                  });
          if (_requested != null &&
              state['pending'] != true &&
              state['revision'] == _requestedFromRevision) {
            state = _requested!;
            await _write(state);
          }
          // A retry after failed persistence needs the same publication order
          // as a new request. Never replay over a completed/newer revision.
          _requested = null;
          _requestedFromRevision = null;
          final revision = state['revision'] as String;
          if (state['pending'] == true) {
            _invalidate(revision);
          } else {
            if (_observedRevision != null && _observedRevision != revision) {
              _invalidate(revision);
              _nativeStopNeeded = true;
              EventStream().publish(AppEvent(
                  type: EventType.system,
                  id: 'signout',
                  key: EventKey.signout));
            }
            _observedRevision = revision;
            SessionWork.complete(revision);
          }
          return state;
        });
        if (state['pending'] == true) {
          // The pending marker is durable before notifying a different engine.
          _notifyForegroundApp();
          return _execute(state);
        }
        return true;
      }, exclusive: true);
    } finally {
      await mutex.close();
    }
    if (result && _nativeStopNeeded && _testActions == null) {
      _nativeStopNeeded = false;
      _notifyForegroundApp();
      // Stopping an owning engine before releasing both locks can terminate
      // cleanup itself and leave its peers unable to resume.
      try {
        if (Platform.isAndroid) {
          await ServiceForeground.instance.stop();
        } else if (Platform.isIOS) {
          await BackgroundExecutionService.instance.cancelIosWork();
        }
      } catch (_) {
        _logger.warning('Native background work could not be stopped');
      }
    }
    return result;
  }

  Future<bool> _singleFlight(Future<bool> Function() action) async {
    if (_running case final running?) return running;
    final operation = Future<bool>.sync(action).catchError((Object error) {
      _logger.error('Local cleanup remains pending: ${error.runtimeType}');
      return false;
    });
    _running = operation;
    try {
      return await operation;
    } finally {
      if (identical(_running, operation)) _running = null;
    }
  }

  Future<bool> _execute(Map<String, dynamic> state) async {
    return SessionWork.maintain(() async {
      // Keep this lease through clearDb so different isolates cannot clear a
      // newly signed-in account after the first cleanup has already finished.
      final lease =
          await ExclusiveOperationCoordinator.tryAcquire('session_cleanup');
      if (lease == null) return false;
      try {
        final revision = state['revision'] as String;
        var succeeded = true;
        for (final action in _testActions ?? _actions(state)) {
          try {
            await action.run();
          } catch (error) {
            succeeded = false;
            _logger.error(
                '${action.name} cleanup remains pending: ${error.runtimeType}');
          }
        }
        if (!succeeded) return false;
        await _write({'revision': revision, 'pending': false});
        _requested = null;
        SessionWork.complete(revision);
        _nativeStopNeeded = true;
        EventStream().publish(AppEvent(
            type: EventType.system, id: 'signout', key: EventKey.signout));
        return true;
      } finally {
        await lease.release();
      }
    });
  }

  void _invalidate(String revision) {
    _observedRevision = revision;
    SessionWork.invalidate(revision);
    ModelSetting.clear();
    SyncUtils().stopAutoSync();
    AppHttpClients.closeAll();
    EventStream().publish(AppEvent(
        type: EventType.system,
        id: 'session',
        key: EventKey.sessionInvalidated));
  }

  List<SessionCleanupAction> _actions(Map<String, dynamic> state) => [
        SessionCleanupAction('Scheduled work', () async {
          SyncUtils().stopAutoSync();
          await TaskManager.stopBackgroundWakes();
          AppHttpClients.closeAll();
        }),
        SessionCleanupAction('Secure storage', () async {
          final recovery = state['mode'] == SessionCleanupMode.recovery.name;
          final reauthenticate =
              state['mode'] == SessionCleanupMode.reauthenticate.name;
          if (!recovery && !reauthenticate) return SecureStorage().clear();
          await SecureStorage().clearExcept({
            AppString.recoveryResetStage.string,
            AppString.fcmId.string,
            if (recovery) AppString.sessionCookie.string,
            if (recovery) AppString.jwtToken.string,
          });
        }),
        SessionCleanupAction('Database', () async {
          await StorageSqlite.instance
              .clearDb(preserveStateKeys: {'operation_lease:session_cleanup'});
          ModelSetting.clear();
          final locale = state['locale'];
          if (locale is String && locale.isNotEmpty) {
            await ModelSetting.set(AppString.locale.string, locale);
          }
          await ModelSetting.set(AppString.onboarding.string, 'yes');
          if (state['mode'] == SessionCleanupMode.reauthenticate.name) {
            await ModelSetting.set(
                AppString.recoveryReauthentication.string, 'yes');
          }
          if (state['mode'] == SessionCleanupMode.recovery.name) {
            final raw = await SecureStorage()
                .read(key: AppString.recoveryResetStage.string);
            Map<String, dynamic>? stage;
            try {
              final decoded = raw == null ? null : jsonDecode(raw);
              if (decoded is Map<String, dynamic>) stage = decoded;
            } catch (_) {
              /* Retain damaged staging for explicit recovery guidance. */
            }
            if (stage?['userId'] is String && stage?['email'] is String) {
              await (await ModelProfile.fromMap(
                      {'id': stage!['userId'], 'email': stage['email']}))
                  .insert();
              await ModelSetting.set(AppString.signedIn.string, 'yes');
            }
          }
        }),
        SessionCleanupAction('Owned files', _clearOwnedFiles),
        SessionCleanupAction('Billing session', () async {
          if (state['mode'] == SessionCleanupMode.recovery.name) return;
          // Billing availability must never gate deletion of private data.
          try {
            if (!simulateTesting() &&
                subscriptionsSupported &&
                // On Apple platforms isAnonymous can terminate the native
                // process if billing was never configured in this engine.
                await Purchases.isConfigured
                    .timeout(const Duration(seconds: 5)) &&
                !await Purchases.isAnonymous
                    .timeout(const Duration(seconds: 5))) {
              await Purchases.logOut().timeout(const Duration(seconds: 5));
            }
          } catch (_) {
            _logger.warning('Billing session logout could not be completed');
          }
        }),
      ];

  static Future<void> _clearOwnedFiles() async {
    final documents = await getApplicationDocumentsDirectory();
    await removeOwnedPath(p.join(documents.path, 'FiFe'));
    final temporary = await getTemporaryDirectory();
    // Ciphertext filenames are content hashes, never user-provided filenames.
    final uploadArtifact =
        RegExp(r'^[A-Za-z0-9_-]{43}_[1-9][0-9]*\.crypt\.ready(?:\.partial)?$');
    await for (final entry in temporary.list(followLinks: false)) {
      final name = p.basename(entry.path);
      if (name == 'fife_access_key.txt' || uploadArtifact.hasMatch(name)) {
        await removeOwnedPath(entry.path);
      }
    }
  }

  static Future<void> removeOwnedPath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.link) {
      await Link(path).delete();
    } else if (type == FileSystemEntityType.directory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _marker = null;
    _requested = null;
    _requestedFromRevision = null;
    _observedRevision = null;
    _awaitingExternalRevision = null;
    _nativeStopNeeded = false;
    _publicationClosing = false;
    SessionWork.resetForTesting();
  }
}
