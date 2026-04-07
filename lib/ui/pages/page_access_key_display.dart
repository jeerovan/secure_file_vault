import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons/lucide_icons.dart';
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
  final Function(PageType, bool, PageParams)? setShowHidePage;
  const PageAccessKey({
    super.key,
    this.setShowHidePage,
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
    try {
      // Determine if the current platform is a Desktop OS
      final bool isDesktop =
          Platform.isWindows || Platform.isMacOS || Platform.isLinux;

      if (isDesktop) {
        // DESKTOP: Open a native "Save As" dialog window
        final String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Access Key',
          fileName: 'fife_access_key.txt',
          type: FileType.custom,
          allowedExtensions: ['txt'],
        );

        // If user didn't cancel the dialog, save the file
        if (outputFile != null) {
          final file = File(outputFile);
          await file.writeAsString(text);

          if (mounted) {
            displaySnackBar(context,
                message: "File saved successfully.", seconds: 2);
          }
        }
      } else {
        // MOBILE: Save to temp directory and open the native Share Sheet
        final directory = await getTemporaryDirectory();
        final filePath = path.join(directory.path, 'fife_access_key.txt');
        final file = File(filePath);
        await file.writeAsString(text);

        // Updated share_plus syntax (replacing the deprecated Share.shareFiles)
        await SharePlus.instance.share(ShareParams(
          files: [XFile(filePath)],
          text: 'Here is your access key.',
        ));
      }
    } catch (e) {
      if (mounted) {
        displaySnackBar(context, message: "Please try again.", seconds: 1);
      }
    }
  }

  void copyToClipboard() {
    Clipboard.setData(ClipboardData(text: sentence));
    if (mounted) {
      displaySnackBar(context, message: "Copied to clipboard", seconds: 1);
    }
  }

  Future<void> continueToNext() async {
    if (mounted) {
      await context.read<AppSetupState>().registerDevice();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Access Key'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Description Text
            Text(
              "Please save this key in a secure place. Only this will allow you to access your encrypted data.",
              style: TextStyle(fontSize: 16.0, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.0),

            // Sentence Display
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: Colors.grey),
              ),
              child: Text(
                sentence,
                style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w400),
                textAlign: TextAlign.justify,
              ),
            ),
            SizedBox(height: 30.0),
            // Button to copy
            ElevatedButton.icon(
              onPressed: () => copyToClipboard(),
              icon: Icon(
                LucideIcons.copy,
                color: Colors.black,
              ),
              label: Text(
                "Copy",
                style: TextStyle(color: Colors.black),
              ),
            ),
            SizedBox(height: 20.0),
            // Button to Download and Save as Text File
            ElevatedButton.icon(
              onPressed: () => _downloadTextFile(sentence),
              icon: Icon(
                LucideIcons.download,
                color: Colors.black,
              ),
              label: Text(
                "Download as Text File",
                style: TextStyle(color: Colors.black),
              ),
            ),
            SizedBox(height: 20.0),

            // Button to Continue to Next Page
            OutlinedButton(
              onPressed: continueToNext,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                side: BorderSide(color: Theme.of(context).primaryColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Text(
                  "Continue",
                  style: TextStyle(fontSize: 16.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
