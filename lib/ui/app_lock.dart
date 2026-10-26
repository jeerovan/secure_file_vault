import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../l10n/app_localizations.dart';
import '../models/model_setting.dart';
import '../services/service_app_lock.dart';

AppLockPrompt appLockPrompt(AppLocalizations loc, {bool settings = false}) =>
    AppLockPrompt(
        reason: settings ? loc.appLockChangeSettings : loc.appLockAuthenticate,
        title: loc.appLockTitle,
        hint: loc.appLockAuthHint,
        cancel: loc.cancel);

String? appLockFailureText(AppLocalizations loc, AppLockFailure? failure) =>
    switch (failure) {
      AppLockFailure.authenticationUnavailable => loc.appLockUnavailable,
      AppLockFailure.authenticationFailed => loc.appLockAuthenticationFailed,
      AppLockFailure.storageUnavailable => loc.appLockStorageError,
      null => null,
    };

/// Keep system Back and dismiss gestures from operating on hidden routes.
class AppLockNavigatorObserver extends NavigatorObserver {
  AppLockNavigatorObserver(this.controller) {
    controller.addListener(_changed);
  }
  final AppLockController controller;
  final Map<ModalRoute<dynamic>, _AppLockPopEntry> _routes = {};

  void _changed() {
    for (final entry in _routes.values) {
      entry.canPopNotifier.value = !controller.concealed;
    }
  }

  void _protect(Route<dynamic>? route) {
    if (route is ModalRoute<dynamic> && !_routes.containsKey(route)) {
      final entry = _AppLockPopEntry(!controller.concealed);
      _routes[route] = entry;
      route.registerPopEntry(entry);
    }
  }

  void _remove(Route<dynamic>? route) {
    final entry = _routes.remove(route);
    if (route is ModalRoute<dynamic> && entry != null) {
      route.unregisterPopEntry(entry);
      entry.canPopNotifier.dispose();
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _protect(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _remove(route);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _remove(oldRoute);
    _protect(newRoute);
  }

  void dispose() {
    controller.removeListener(_changed);
    for (final route in _routes.keys.toList()) {
      _remove(route);
    }
  }
}

class _AppLockPopEntry extends PopEntry<Object?> {
  _AppLockPopEntry(bool canPop) : canPopNotifier = ValueNotifier(canPop);
  @override
  final ValueNotifier<bool> canPopNotifier;
  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}
}

abstract interface class AppLockPrivacyBridge {
  bool get supported;
  bool get reportsApplicationLifecycle;
  Future<VoidCallback> watchLifecycle(ValueChanged<AppLifecycleState> listener);
  Future<void> setEnabled(bool enabled);
  Future<void> frameReady({bool allowNativeDocuments = false});
}

class SystemAppLockPrivacy implements AppLockPrivacyBridge {
  const SystemAppLockPrivacy();
  static const _channel = MethodChannel('com.jeerovan.fife/app_lock_privacy');
  static Object? _lifecycleOwner;
  @override
  bool get supported => Platform.isAndroid || Platform.isIOS;
  @override
  bool get reportsApplicationLifecycle => Platform.isIOS;
  @override
  Future<VoidCallback> watchLifecycle(
      ValueChanged<AppLifecycleState> listener) async {
    final owner = Object();
    _lifecycleOwner = owner;
    var lastRevision = -1;
    void accept(Object? value) {
      if (!identical(_lifecycleOwner, owner)) return;
      if (value is! Map ||
          value['active'] is! bool ||
          value['revision'] is! int) {
        throw const FormatException('Invalid native application lifecycle');
      }
      final revision = value['revision'] as int;
      if (revision <= lastRevision) return;
      lastRevision = revision;
      listener(value['active'] == true
          ? AppLifecycleState.resumed
          : AppLifecycleState.inactive);
    }

    void stop() {
      if (identical(_lifecycleOwner, owner)) {
        _lifecycleOwner = null;
        _channel.setMethodCallHandler(null);
      }
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'lifecycle') accept(call.arguments);
    });
    try {
      accept(await _channel.invokeMethod<Object?>('observeLifecycle'));
    } catch (_) {
      stop();
      rethrow;
    }
    return stop;
  }

  @override
  Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod<void>('setEnabled', enabled);
  @override
  Future<void> frameReady({bool allowNativeDocuments = false}) =>
      _channel.invokeMethod<void>(
          'frameReady', {'allowNativeDocuments': allowNativeDocuments});
}

/// The shield surrounds the Navigator, including routes, dialogs and sheets.
/// Private routes remain mounted but have no paint, focus or semantics while
/// concealed. Locking is immediate; no transition retains outgoing vault pixels.
class AppLockGate extends StatefulWidget {
  const AppLockGate(
      {super.key,
      required this.controller,
      required this.child,
      this.cleanup,
      this.privacy = const SystemAppLockPrivacy()});
  final AppLockController controller;
  final Widget child;
  // Render the safe cleanup/retry screen separately, never by revealing routes.
  final Widget? cleanup;
  final AppLockPrivacyBridge privacy;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  int _promptedRevision = -1;
  int _privacyFrame = 0;
  bool? _nativeEnabled;
  bool _privacyFailed = false;
  bool _lifecycleFailed = false;
  bool _nativeLifecycleReady = false;
  int _lifecycleEpoch = 0;
  VoidCallback? _stopNativeLifecycle;
  Future<void> _nativeWork = Future.value();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
    _configureLifecycle();
    _changed();
  }

  @override
  void didUpdateWidget(AppLockGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _promptedRevision = -1;
      _configureLifecycle();
      _changed();
    } else if (oldWidget.privacy != widget.privacy) {
      _configureLifecycle();
      _changed();
    } else if (oldWidget.cleanup != widget.cleanup) {
      _changed();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!widget.privacy.reportsApplicationLifecycle) {
      widget.controller.handleLifecycle(state);
    }
  }

  void _configureLifecycle() {
    _lifecycleEpoch++;
    _stopNativeLifecycle?.call();
    _stopNativeLifecycle = null;
    _nativeLifecycleReady = !widget.privacy.reportsApplicationLifecycle;
    if (_nativeLifecycleReady) {
      widget.controller.handleLifecycle(
          WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed);
    } else {
      widget.controller.handleLifecycle(AppLifecycleState.inactive);
      unawaited(_connectNativeLifecycle());
    }
  }

  Future<void> _connectNativeLifecycle() async {
    final epoch = ++_lifecycleEpoch;
    try {
      final stop = await widget.privacy.watchLifecycle((state) {
        if (!mounted || epoch != _lifecycleEpoch) return;
        setState(() {
          _nativeLifecycleReady = true;
          _lifecycleFailed = false;
        });
        widget.controller.handleLifecycle(state);
        _changed();
      });
      if (!mounted || epoch != _lifecycleEpoch) {
        stop();
      } else {
        _stopNativeLifecycle = stop;
      }
    } catch (_) {
      if (mounted && epoch == _lifecycleEpoch) {
        setState(() => _lifecycleFailed = true);
      }
    }
  }

  void _changed() {
    if (!mounted) return;
    if (widget.controller.concealed) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _syncNativePrivacy();
    _schedulePrompt();
  }

  void _syncNativePrivacy({bool retry = false}) {
    final privacy = widget.privacy;
    if (!privacy.supported) return;
    final frame = ++_privacyFrame;
    final controller = widget.controller;
    // Protect the enable transaction before its system dialog deactivates us.
    final enabled = controller.ready
        ? controller.enabled || controller.busy
        : _nativeEnabled;
    if (enabled != null && (enabled != _nativeEnabled || retry)) {
      _nativeEnabled = enabled;
      _nativeWork = _nativeWork.then((_) async {
        if (!mounted) return;
        try {
          await privacy.setEnabled(enabled);
          if (mounted && _privacyFailed) setState(() => _privacyFailed = false);
        } catch (_) {
          if (mounted) setState(() => _privacyFailed = true);
        }
      });
    }
    // Native platforms keep their cover until Flutter has painted a safe
    // resumed frame (either the lock screen or an authorized vault).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _nativeWork;
      if (!mounted ||
          !_nativeLifecycleReady ||
          !widget.controller.foreground ||
          frame != _privacyFrame) {
        return;
      }
      try {
        await privacy.frameReady(
            allowNativeDocuments: widget.cleanup == null &&
                !widget.controller.concealed &&
                !_privacyFailed);
      } catch (_) {
        if (mounted) setState(() => _privacyFailed = true);
      }
    });
  }

  void _schedulePrompt() {
    final controller = widget.controller;
    if (widget.cleanup != null ||
        !_nativeLifecycleReady ||
        _lifecycleFailed ||
        _privacyFailed ||
        !controller.ready ||
        !controller.enabled ||
        !controller.locked ||
        !controller.foreground ||
        controller.busy ||
        _promptedRevision == controller.lockRevision) {
      return;
    }
    _promptedRevision = controller.lockRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          controller == widget.controller &&
          controller.foreground &&
          controller.locked &&
          !controller.busy) {
        unawaited(
            controller.unlock(appLockPrompt(AppLocalizations.of(context)!)));
      }
    });
  }

  Future<void> _retry() async {
    if (!_nativeLifecycleReady) {
      await _connectNativeLifecycle();
      if (!_nativeLifecycleReady) return;
    }
    if (!mounted) return;
    if (_privacyFailed) _syncNativePrivacy(retry: true);
    final controller = widget.controller;
    if (!controller.ready) {
      await controller.load();
    } else {
      await controller.unlock(appLockPrompt(AppLocalizations.of(context)!));
    }
  }

  @override
  void dispose() {
    _lifecycleEpoch++;
    _stopNativeLifecycle?.call();
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final concealed = widget.cleanup != null ||
              controller.concealed ||
              _privacyFailed ||
              _lifecycleFailed ||
              !_nativeLifecycleReady;
          final loc = AppLocalizations.of(context)!;
          return Stack(fit: StackFit.expand, children: [
            Offstage(
                offstage: concealed,
                child: TickerMode(
                    enabled: !concealed,
                    child: FocusScope(
                        canRequestFocus: !concealed,
                        descendantsAreFocusable: !concealed,
                        descendantsAreTraversable: !concealed,
                        child: widget.child))),
            if (concealed && widget.cleanup != null) widget.cleanup!,
            if (concealed && widget.cleanup == null)
              Scaffold(
                  body: SafeArea(
                      child: Column(children: [
                Expanded(
                    child: Center(
                        child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(LucideIcons.lock,
                        size: 48, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 24),
                    Text(loc.appLocked,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 12),
                    Text(loc.appLockAuthenticate, textAlign: TextAlign.center),
                    if (_privacyFailed ||
                        _lifecycleFailed ||
                        controller.failure != null) ...[
                      const SizedBox(height: 16),
                      Text(
                          _privacyFailed || _lifecycleFailed
                              ? loc.appLockAuthenticationFailed
                              : appLockFailureText(loc, controller.failure)!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ],
                  ]),
                ))),
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        key: const ValueKey('app-lock-unlock'),
                        onPressed: controller.busy ||
                                !controller.foreground ||
                                (!controller.ready &&
                                    controller.failure == null)
                            ? null
                            : _retry,
                        icon: controller.busy ||
                                (!controller.ready &&
                                    controller.failure == null)
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(LucideIcons.unlock),
                        label: Text(controller.ready
                            ? loc.appLockUnlock
                            : loc.tryAgain),
                      ),
                    )),
              ]))),
          ]);
        });
  }
}

class AppLockSettings extends StatefulWidget {
  const AppLockSettings(
      {super.key, required this.controller, this.enabledActions = const []});
  final AppLockController controller;
  final List<Widget> enabledActions;

  @override
  State<AppLockSettings> createState() => _AppLockSettingsState();
}

class _AppLockSettingsState extends State<AppLockSettings> {
  int? _previewMinutes;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final minutes = _previewMinutes ?? controller.minutes;
          final choices = ModelSetting.appLockTimeoutChoices;
          return Column(children: [
            SwitchListTile.adaptive(
              key: const ValueKey('app-lock-switch'),
              secondary: const Icon(LucideIcons.lock, color: Colors.grey),
              title: Text(loc.appLockTitle),
              subtitle: Text(loc.appLockDescription),
              value: controller.enabled,
              onChanged: !controller.ready || controller.busy
                  ? null
                  : (value) async {
                      await controller.setEnabled(
                          value, appLockPrompt(loc, settings: true));
                    },
            ),
            if (controller.failure != null)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(appLockFailureText(loc, controller.failure)!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            // Disclosure follows the existing settings motion; reduced motion is instant.
            _AppLockDisclosure(
              child: !controller.enabled
                  ? const SizedBox.shrink()
                  : Column(children: [
                      ListTile(
                        leading:
                            const Icon(LucideIcons.clock, color: Colors.grey),
                        horizontalTitleGap: 24,
                        title: Text(loc.appLockTimeout),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(loc.syncIntervalMinutes(minutes)),
                              Text(loc.appLockTimeoutDescription),
                              Slider(
                                key: const ValueKey('app-lock-timeout'),
                                min: 0,
                                max: (choices.length - 1).toDouble(),
                                divisions: choices.length - 1,
                                value: choices.indexOf(minutes).toDouble(),
                                label:
                                    '${loc.appLockTimeout}: ${loc.syncIntervalMinutes(minutes)}',
                                semanticFormatterCallback: (value) =>
                                    loc.syncIntervalMinutes(
                                        choices[value.round()]),
                                onChanged: controller.busy
                                    ? null
                                    : (value) => setState(() =>
                                        _previewMinutes =
                                            choices[value.round()]),
                                onChangeEnd: (value) async {
                                  await controller
                                      .setTimeout(choices[value.round()]);
                                  if (mounted) {
                                    setState(() => _previewMinutes = null);
                                  }
                                },
                              ),
                              Row(children: [
                                Expanded(
                                    child: Text(loc
                                        .syncIntervalMinutes(choices.first))),
                                Expanded(
                                    child: Text(
                                        loc.syncIntervalMinutes(choices.last),
                                        textAlign: TextAlign.end)),
                              ]),
                            ]),
                      ),
                      ...widget.enabledActions
                    ]),
            ),
          ]);
        });
  }
}

class _AppLockDisclosure extends StatelessWidget {
  const _AppLockDisclosure({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedSize(
        duration: const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: child);
  }
}
