import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/model_item.dart';

Future<bool> confirmArchiveBackup(
    BuildContext context, Iterable<ModelItem> selection) async {
  if (!selection.any((item) => item.isFolder)) return true;
  final strings = AppLocalizations.of(context)!;
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(strings.archiveBackup),
          content: Text(strings.archiveFolderBackupMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(strings.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(strings.archiveBackup),
            ),
          ],
        ),
      ) ??
      false;
}
