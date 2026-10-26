import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// Read-only UIKit state for standalone in-app tests. This neither registers a
/// viewer nor creates its presenter: it observes normal launch/transition state.
Map<String, Object> appleViewerProbe() {
  if (!Platform.isIOS) {
    throw StateError('This probe requires the physical iOS app');
  }
  final native = DynamicLibrary.process();
  final allocate = native.lookupFunction<Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)>('malloc');
  final free = native.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final getClass = native.lookupFunction<Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)>('objc_getClass');
  final registerSelector = native.lookupFunction<
      Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)>('sel_registerName');
  T withText<T>(String value, T Function(Pointer<Uint8>) action) {
    final bytes = utf8.encode(value);
    final pointer = allocate(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Probe allocation failed');
    try {
      pointer.asTypedList(bytes.length + 1)
        ..setRange(0, bytes.length, bytes)
        ..[bytes.length] = 0;
      return action(pointer);
    } finally {
      free(pointer.cast());
    }
  }

  Pointer<Void> selector(String value) => withText(value, registerSelector);
  final object = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final integer = native.lookupFunction<
      IntPtr Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final boolean = native.lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final at = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UintPtr),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, int)>('objc_msgSend');
  Pointer<Void> obj(Pointer<Void> receiver, String name) =>
      object(receiver, selector(name));
  int number(Pointer<Void> receiver, String name) =>
      integer(receiver, selector(name));
  bool flag(Pointer<Void> receiver, String name) =>
      boolean(receiver, selector(name)) != 0;
  final responds = native.lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final application =
      obj(withText('UIApplication', getClass), 'sharedApplication');
  final active = number(application, 'applicationState') == 0;
  final onMainThread = flag(withText('NSThread', getClass), 'isMainThread');
  final result = <String, Object>{
    'applicationActive': active,
    'onMainThread': onMainThread,
    'nativeReady': active,
  };
  // UIView inspection belongs on the main thread. The application-state flag
  // is enough to wait for activation when using an unmerged Dart UI thread.
  if (!onMainThread) return result;
  final scenes = obj(obj(application, 'connectedScenes'), 'allObjects');
  Pointer<Void> host = nullptr;
  for (var s = 0; s < number(scenes, 'count'); s++) {
    final scene = at(scenes, selector('objectAtIndex:'), s);
    if (responds(scene, selector('respondsToSelector:'), selector('windows')) ==
        0) {
      continue;
    }
    if (number(scene, 'activationState') != 0) continue;
    final windows = obj(scene, 'windows');
    for (var w = 0; w < number(windows, 'count'); w++) {
      final window = at(windows, selector('objectAtIndex:'), w);
      if (flag(window, 'isKeyWindow')) {
        host = obj(window, 'rootViewController');
        break;
      }
    }
    if (host != nullptr) break;
  }
  while (host != nullptr) {
    final next = obj(host, 'presentedViewController');
    if (next == nullptr || flag(next, 'isBeingDismissed')) break;
    host = next;
  }
  final view = obj(host, 'viewIfLoaded');
  final attached = obj(view, 'window') != nullptr;
  final transitioning =
      flag(host, 'isBeingPresented') || flag(host, 'isBeingDismissed');
  final className = native.lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>)>('object_getClassName')(host);
  var length = 0;
  while (className != nullptr && length < 256 && className[length] != 0) {
    length++;
  }
  return {
    ...result,
    'hostAttached': attached,
    'hostTransitioning': transitioning,
    'hostClass': className == nullptr
        ? 'none'
        : utf8.decode(className.asTypedList(length)),
    'nativeReady': active && attached && !transitioning,
  };
}
