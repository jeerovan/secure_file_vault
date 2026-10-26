import 'dart:io';

import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

enum FileViewResult { opened, missing, unsupported, denied, failed, cancelled }

/// The operating-system handoff boundary. Item access and UI policy stay in
/// the caller; native tests exercise the default implementation on hardware.
abstract class FileViewerPlatform {
  static FileViewerPlatform instance = NativeFileViewer();

  Future<FileViewResult> open(String path);
  Future<void> cancel() async {}
}

class NativeFileViewer extends FileViewerPlatform {
  static const channel = MethodChannel('com.jeerovan.fife/file_viewer');

  @override
  Future<FileViewResult> open(String path) async {
    if (Platform.isIOS) {
      final status = await channel.invokeMethod<String>('open', {'path': path});
      return switch (status) {
        'opened' => FileViewResult.opened,
        'missing' => FileViewResult.missing,
        'unsupported' => FileViewResult.unsupported,
        'denied' => FileViewResult.denied,
        'cancelled' => FileViewResult.cancelled,
        _ => FileViewResult.failed,
      };
    }
    final result = await OpenFilex.open(path);
    return switch (result.type) {
      ResultType.done => FileViewResult.opened,
      ResultType.fileNotFound => FileViewResult.missing,
      ResultType.noAppToOpen => FileViewResult.unsupported,
      ResultType.permissionDenied => FileViewResult.denied,
      ResultType.error => FileViewResult.failed,
    };
  }

  @override
  Future<void> cancel() async {
    if (Platform.isIOS) await channel.invokeMethod<void>('cancel');
  }
}
