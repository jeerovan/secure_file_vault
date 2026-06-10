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

class PageAccessKey extends StatefulWidget {
  const PageAccessKey({
    super.key,
  });

  @override
  State<PageAccessKey> createState() => _PageAccessKeyState();
}

class _PageAccessKeyState extends State<PageAccessKey> {
  SecureStorage secureStorage = SecureStorage();
  AppLogger logger = AppLogger(prefixes: ["PageAccessKey"]);
  String sentence = "";

  @override
  void initState() {
    super.initState();
    loadAccessKey();
  }

  Future<void> loadAccessKey() async {
    String? accessKeyBase64 =
        await secureStorage.read(key: AppString.accessKey.string);
    Uint8List accessKeyBytes = base64Decode(accessKeyBase64!);
    String accessKeyHex = bytesToHex(accessKeyBytes);
    if (mounted) {
      setState(() {
        sentence = bip39.entropyToMnemonic(accessKeyHex);
      });
    }
  }

  Future<void> _downloadTextFile(String text) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final bool isDesktop =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;

      if (isDesktop) {
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: AppLocalizations.of(context)!.saveAccessKey,
          fileName: 'fife_access_key.txt',
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );

        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(text);

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
        await file.writeAsString(text);

        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(filePath)],
            text: loc.accessKeyShareMessage,
          ),
        );
      }
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
    if (mounted) {
      await context.read<AppSetupState>().registerDevice();
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
              onPressed: copyToClipboard,
              icon: const Icon(
                LucideIcons.copy,
              ),
              label: Text(
                AppLocalizations.of(context)!.copy,
              ),
            ),
            const SizedBox(height: 20.0),
            FilledButton.icon(
              onPressed: () => _downloadTextFile(sentence),
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
            const SizedBox(height: 20.0),
            OutlinedButton(
              onPressed: continueToNext,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                side: BorderSide(color: Theme.of(context).primaryColorLight),
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
        ),
      ),
    );
  }
}
