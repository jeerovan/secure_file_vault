import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../l10n/app_localizations.dart';
import '../../ui/common_widgets.dart';
import '../../utils/enums.dart';
import '../../services/service_logger.dart';
import '../../storage/storage_secure.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:bip39/bip39.dart' as bip39;
import '../../utils/common.dart';
import '../../services/service_session_work.dart';
import '../../services/service_vault_key_setup.dart';
import '../../storage/storage_sqlite.dart';

class PageAccessKey extends StatefulWidget {
  const PageAccessKey({
    super.key,
    this.requireAcknowledgment = false,
    this.onAcknowledged,
  });
  final bool requireAcknowledgment;
  final Future<void> Function()? onAcknowledged;

  @override
  State<PageAccessKey> createState() => _PageAccessKeyState();
}

class _PageAccessKeyState extends State<PageAccessKey> {
  SecureStorage secureStorage = SecureStorage();
  AppLogger logger = AppLogger(prefixes: ["PageAccessKey"]);
  String sentence = "";
  bool _saved = false;
  bool _continuing = false;

  @override
  void initState() {
    super.initState();
    loadAccessKey();
  }

  Future<void> loadAccessKey() async {
    try {
      await SessionWork.run(() async {
        String? accessKeyBase64 =
            await secureStorage.read(key: AppString.accessKey.string);
        if (accessKeyBase64 == null) return;
        Uint8List accessKeyBytes = base64Decode(accessKeyBase64);
        String accessKeyHex = bytesToHex(accessKeyBytes);
        await SessionWork.checkpoint();
        if (mounted) {
          setState(() {
            sentence = bip39.entropyToMnemonic(accessKeyHex);
          });
        }
      });
    } on SessionInvalidated {/* The root removes this private page. */}
  }

  Future<void> _downloadTextFile(String text) async {
    try {
      await SessionWork.run(() => _exportTextFile(text));
    } on SessionInvalidated {/* A retired phrase must not be shared. */}
  }

  Future<void> _exportTextFile(String text) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final bool isDesktop =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;

      if (isDesktop) {
        final Uri? outputFile = await FilePicker.saveFile(
          dialogTitle: AppLocalizations.of(context)!.saveAccessKey,
          fileName: 'fife_access_key.txt',
          bytes: Uint8List.fromList(utf8.encode(text)),
          mimeType: 'text/plain',
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );

        if (outputFile != null) {
          if (mounted) {
            displaySnackBar(
              context,
              message: AppLocalizations.of(context)!.fileSavedSuccessfully,
              seconds: 2,
            );
          }
        }
      } else {
        final directory = await getTemporaryDirectory();
        final filePath = path.join(directory.path, 'fife_access_key.txt');
        final file = File(filePath);
        // Serialize app-owned export creation with cleanup so an old callback
        // cannot recreate a private file after the cleanup sweep.
        await StorageSqlite.instance.runInTransaction(() async {
          await SessionWork.checkpoint();
          await file.writeAsString(text);
          await SessionWork.checkpoint();
        });

        await SessionWork.checkpoint();
        if (!mounted) return;

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            text: loc.accessKeyShareMessage,
          ),
        );
      }
    } on SessionInvalidated {
      rethrow;
    } catch (e) {
      if (mounted) {
        displaySnackBar(
          context,
          message: AppLocalizations.of(context)!.pleaseTryAgain,
          seconds: 1,
        );
      }
    }
  }

  void copyToClipboard() {
    Clipboard.setData(ClipboardData(text: sentence));
    if (mounted) {
      displaySnackBar(
        context,
        message: AppLocalizations.of(context)!.copiedToClipboard,
        seconds: 1,
      );
    }
  }

  Future<void> continueToNext() async {
    if (_continuing ||
        sentence.isEmpty ||
        widget.requireAcknowledgment && !_saved) {
      return;
    }
    setState(() => _continuing = true);
    try {
      if (widget.onAcknowledged case final acknowledge?) {
        await acknowledge();
      } else if (mounted) {
        await VaultKeySetupService.instance.acknowledge();
        if (!mounted) return;
        await context.read<AppSetupState>().registerDevice();
      }
    } on SessionInvalidated {
      // Root cleanup owns navigation after revocation.
    } finally {
      if (mounted) setState(() => _continuing = false);
    }
  }

  Future<void> checkKeys() async {
    if (mounted) {
      await context.read<AppSetupState>().decodeAccessKey();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.accessKeyTitle),
      ),
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  AppLocalizations.of(context)!.accessKeyDescription,
                  style: const TextStyle(
                    fontSize: 16.0,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20.0),
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: Text(
                    sentence,
                    style: const TextStyle(
                      fontSize: 18.0,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.justify,
                  ),
                ),
                const SizedBox(height: 30.0),
                FilledButton.icon(
                  onPressed: sentence.isEmpty ? null : copyToClipboard,
                  icon: const Icon(
                    LucideIcons.copy,
                  ),
                  label: Text(
                    AppLocalizations.of(context)!.copy,
                  ),
                ),
                const SizedBox(height: 20.0),
                FilledButton.icon(
                  onPressed: sentence.isEmpty
                      ? null
                      : () => _downloadTextFile(sentence),
                  icon: const Icon(
                    LucideIcons.download,
                  ),
                  label: Text(
                    AppLocalizations.of(context)!.downloadAsTextFile,
                  ),
                ),
                if (simulateTesting()) const SizedBox(height: 20.0),
                if (simulateTesting())
                  TextButton(onPressed: checkKeys, child: Text("Check Keys")),
                if (widget.requireAcknowledgment)
                  CheckboxListTile(
                    value: _saved,
                    onChanged: _continuing
                        ? null
                        : (value) => setState(() => _saved = value == true),
                    title:
                        Text(AppLocalizations.of(context)!.recoveryPhraseSaved),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: 20.0),
                OutlinedButton(
                  onPressed: sentence.isEmpty ||
                          _continuing ||
                          widget.requireAcknowledgment && !_saved
                      ? null
                      : continueToNext,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    side:
                        BorderSide(color: Theme.of(context).primaryColorLight),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8.0),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      AppLocalizations.of(context)!.continueLabel,
                      style: const TextStyle(fontSize: 16.0),
                    ),
                  ),
                ),
              ],
            )),
      ))),
    );
  }
}
