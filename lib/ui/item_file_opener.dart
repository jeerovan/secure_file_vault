import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/model_file.dart';
import '../models/model_item.dart';
import '../services/service_app_lock.dart';
import '../services/service_file_viewer.dart';
import '../services/service_session_work.dart';
import '../storage/local_item_access.dart';
import 'common_widgets.dart';

enum ItemOpenResult {
  opened,
  downloadRequired,
  unsupported,
  accessDenied,
  unavailable,
  failed,
  ignored,
}

/// Owns one presentation, not a cached filesystem-presence result.
class ItemFileOpener {
  bool _busy = false;
  bool _disposed = false;
  FileViewerPlatform? _viewer;

  Future<ItemOpenResult> open(String id,
      {required bool Function() canPresent}) async {
    if (_busy || _disposed || !canPresent()) return ItemOpenResult.ignored;
    _busy = true;
    try {
      return await SessionWork.run(() async {
        final item = await ModelItem.get(id);
        if (item == null || item.isFolder || item.archivedAt != 0) {
          return ItemOpenResult.unavailable;
        }
        final ancestry = await ModelItem.getPathRowsForItem(id);
        LocalItemAccess? access;
        try {
          access = await LocalItemAccess.acquire(id);
          await SessionWork.checkpoint();
          final type =
              await FileSystemEntity.type(access.itemPath, followLinks: false);
          final current = await ModelItem.get(id);
          final currentAncestry = await ModelItem.getPathRowsForItem(id);
          if (current == null ||
              current.isFolder ||
              current.archivedAt != 0 ||
              ancestry.length != currentAncestry.length ||
              !Iterable.generate(ancestry.length)
                  .every((i) => mapEquals(ancestry[i], currentAncestry[i]))) {
            return ItemOpenResult.unavailable;
          }
          await SessionWork.checkpoint();
          if (_disposed || !canPresent()) return ItemOpenResult.ignored;
          if (type == FileSystemEntityType.notFound) {
            return _missing(current);
          }
          if (type != FileSystemEntityType.file) {
            return ItemOpenResult.accessDenied;
          }
          final viewer = FileViewerPlatform.instance;
          _viewer = viewer;
          final unregister = SessionWork.onInvalidated(_cancel);
          try {
            final result = await viewer.open(access.itemPath);
            await SessionWork.checkpoint();
            return switch (result) {
              FileViewResult.opened => ItemOpenResult.opened,
              FileViewResult.unsupported => ItemOpenResult.unsupported,
              FileViewResult.denied => ItemOpenResult.accessDenied,
              FileViewResult.failed => ItemOpenResult.failed,
              FileViewResult.cancelled => ItemOpenResult.ignored,
              FileViewResult.missing => await FileSystemEntity.type(
                          access.itemPath,
                          followLinks: false) ==
                      FileSystemEntityType.notFound
                  ? await _missing(current)
                  : ItemOpenResult.accessDenied,
            };
          } finally {
            unregister();
            _viewer = null;
          }
        } finally {
          // Preview completion/dismissal must release its bookmark, without a
          // release error replacing the actual viewer outcome.
          try {
            await access?.release();
          } catch (_) {
            // The native access manager also balances failed/revoked scopes.
          }
        }
      });
    } on SessionInvalidated {
      return ItemOpenResult.ignored;
    } on PlatformException {
      return ItemOpenResult.accessDenied;
    } on FileSystemException {
      return ItemOpenResult.accessDenied;
    } catch (_) {
      return ItemOpenResult.failed;
    } finally {
      _busy = false;
    }
  }

  static Future<ItemOpenResult> _missing(ModelItem item) async {
    final hash = item.fileHash;
    final backup = hash == null ? null : await ModelFile.get(hash);
    return backup != null && backup.uploadedAt > 0
        ? ItemOpenResult.downloadRequired
        : ItemOpenResult.unavailable;
  }

  void _cancel() {
    final viewer = _viewer;
    if (viewer != null) {
      unawaited(viewer.cancel().catchError((_) {}));
    }
  }

  void dispose() {
    _disposed = true;
    _cancel();
  }
}

Future<void> openFileItem(BuildContext context, ModelItem item,
    ItemFileOpener opener, bool Function() stillCurrent) async {
  bool allowed() {
    if (!context.mounted ||
        !stillCurrent() ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return false;
    }
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    return !(context.read<AppLockController?>()?.concealed ?? false);
  }

  final result = await opener.open(item.id, canPresent: allowed);
  if (!context.mounted || !allowed()) return;
  final loc = AppLocalizations.of(context)!;
  final message = switch (result) {
    ItemOpenResult.downloadRequired => loc.longPressToDownload,
    ItemOpenResult.unsupported => loc.noSupportedApplication,
    ItemOpenResult.accessDenied => loc.fileAccessUnavailable,
    ItemOpenResult.unavailable => loc.fileNotAvailable,
    ItemOpenResult.failed => loc.unableToOpenFile,
    ItemOpenResult.opened || ItemOpenResult.ignored => null,
  };
  if (message != null) displaySnackBar(context, message: message, seconds: 4);
}
