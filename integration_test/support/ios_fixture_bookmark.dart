import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Supply a Foundation bookmark for an isolated fixture's own source folder.
/// This supplies no sync work or access outside its app container.
Future<String> bookmarkIosFixtureDirectory(String path) async {
  final documents = await getApplicationDocumentsDirectory();
  if (!Platform.isIOS ||
      !path.startsWith('${documents.path}/ios-startup-retry-') ||
      !await Directory(path).exists()) {
    throw StateError('Only an existing app-owned fixture folder is allowed');
  }
  final native = DynamicLibrary.process();
  final allocate = native.lookupFunction<Pointer<Uint8> Function(IntPtr),
      Pointer<Uint8> Function(int)>('malloc');
  final free = native.lookupFunction<Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('free');
  final getClass = native.lookupFunction<Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)>('objc_getClass');
  final register = native.lookupFunction<Pointer<Void> Function(Pointer<Uint8>),
      Pointer<Void> Function(Pointer<Uint8>)>('sel_registerName');
  T withText<T>(String value, T Function(Pointer<Uint8>) action) {
    final bytes = utf8.encode(value);
    final pointer = allocate(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Fixture allocation failed');
    try {
      pointer.asTypedList(bytes.length + 1)
        ..setRange(0, bytes.length, bytes)
        ..[bytes.length] = 0;
      return action(pointer);
    } finally {
      free(pointer.cast());
    }
  }

  Pointer<Void> selector(String name) => withText(name, register);
  final objectArgument = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final object = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final option = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UintPtr),
      Pointer<Void> Function(
          Pointer<Void>, Pointer<Void>, int)>('objc_msgSend');
  final bookmark = native.lookupFunction<
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, UintPtr,
          Pointer<Void>, Pointer<Void>, Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>, Pointer<Void>, int, Pointer<Void>,
          Pointer<Void>, Pointer<Void>)>('objc_msgSend');
  final string = withText(
      path,
      (bytes) => objectArgument(withText('NSString', getClass),
          selector('stringWithUTF8String:'), bytes.cast()));
  final url = objectArgument(
      withText('NSURL', getClass), selector('fileURLWithPath:'), string);
  // NSURLBookmarkCreationMinimalBookmark in the installed Foundation SDK.
  final data = bookmark(
      url,
      selector(
          'bookmarkDataWithOptions:includingResourceValuesForKeys:relativeToURL:error:'),
      1 << 9,
      nullptr,
      nullptr,
      nullptr);
  if (data == nullptr) throw StateError('Fixture bookmark creation failed');
  final encoded = option(data, selector('base64EncodedStringWithOptions:'), 0);
  final bytes = object(encoded, selector('UTF8String')).cast<Uint8>();
  if (bytes == nullptr) throw StateError('Fixture bookmark encoding failed');
  var length = 0;
  while (length < 65536 && bytes[length] != 0) {
    length++;
  }
  if (length == 65536) throw StateError('Fixture bookmark exceeds limit');
  return utf8.decode(bytes.asTypedList(length));
}
