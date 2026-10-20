import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

/// Creates a real Foundation bookmark for an app-owned integration fixture.
/// Resolution and access still go through the application's native channel.
/// This avoids presenting the Files picker for a folder already in our sandbox.
String createAppleTestBookmark(String path) {
  final native = DynamicLibrary.process();
  final allocate = native.lookupFunction<Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)>('malloc');
  final release = native.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final getClass = native.lookupFunction<Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)>('objc_getClass');
  final registerSelector = native.lookupFunction<
      Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)>('sel_registerName');

  T withText<T>(String value, T Function(Pointer<Uint8>) action) {
    final bytes = utf8.encode(value);
    final pointer = allocate(bytes.length + 1);
    if (pointer == nullptr) {
      throw StateError('Native fixture allocation failed');
    }
    try {
      pointer.asTypedList(bytes.length + 1)
        ..setRange(0, bytes.length, bytes)
        ..[bytes.length] = 0;
      return action(pointer);
    } finally {
      release(pointer.cast());
    }
  }

  Pointer<Void> selector(String name) => withText(name, registerSelector);
  final onePointer = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final filePath = withText(
      path,
      (pointer) => onePointer(withText('NSString', getClass),
          selector('stringWithUTF8String:'), pointer.cast()));
  final url = onePointer(
      withText('NSURL', getClass), selector('fileURLWithPath:'), filePath);
  final bookmark = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UnsignedLong,
          Pointer<Void>, Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>,
          Pointer<Void>, Pointer<Void>)>('objc_msgSend')(
    url,
    selector(
        'bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:'),
    // Foundation NSURL.h: withSecurityScope on macOS, minimalBookmark on iOS.
    1 << (Platform.isMacOS ? 11 : 9),
    nullptr,
    nullptr,
    nullptr,
  );
  if (bookmark == nullptr) throw StateError('Native fixture bookmark failed');
  final encoded = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UnsignedLong),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, int)>('objc_msgSend')(
    bookmark,
    selector('base64EncodedStringWithOptions:'),
    0,
  );
  final text = native.lookupFunction<
      Pointer<Uint8> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Uint8> Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend')(
    encoded,
    selector('UTF8String'),
  );
  if (text == nullptr) throw StateError('Native fixture encoding failed');
  var length = 0;
  while (length < 64 * 1024 && text[length] != 0) {
    length++;
  }
  if (length == 64 * 1024) throw StateError('Unexpected fixture bookmark size');
  return utf8.decode(text.asTypedList(length));
}
