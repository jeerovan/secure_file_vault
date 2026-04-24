import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for Clipboard
import 'package:file_picker/file_picker.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../utils/common.dart';
import '../../ui/common_widgets.dart';
import '../../storage/storage_secure.dart';
import '../../utils/utils_crypto.dart';
import '../../utils/enums.dart';

class PageAccessKeyDecode extends StatefulWidget {
  const PageAccessKeyDecode({super.key});

  @override
  State<PageAccessKeyDecode> createState() => _PageAccessKeyDecodeState();
}

class _PageAccessKeyDecodeState extends State<PageAccessKeyDecode> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  final SecureStorage secureStorage = SecureStorage();

  bool processing = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// Validates input to ensure it contains exactly 24 words
  bool _validateWordCount(String input) {
    final words = input.trim().split(RegExp(r'\s+'));
    return words.length == 24;
  }

  /// Pastes content from clipboard directly into the text field
  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      _textController.text = clipboardData!.text!;
    }
  }

  /// Processes the validated 24 words further
  Future<void> _processWords(String words) async {
    setState(() => processing = true);

    try {
      words = utf8.decode(utf8.encode(words.trim()));
      words = words.replaceAll(RegExp(r'\s+'), ' ');

      SodiumSumo sodium = await SodiumSumoInit.init();
      CryptoUtils cryptoUtils = CryptoUtils(sodium);

      if (!bip39.validateMnemonic(words)) {
        if (mounted) showAlertMessage(context, "Error", "Invalid word list");
        return;
      }

      String accessKeyHex = bip39.mnemonicToEntropy(words);
      Uint8List accessKeyBytes = hexToBytes(accessKeyHex);

      String masterKeyCipheredBase64 =
          await secureStorage.read(key: AppString.keyCipher.string) as String;
      String masterKeyNonceBase64 =
          await secureStorage.read(key: AppString.keyNonce.string) as String;

      Uint8List masterKeyCipheredBytes = base64Decode(masterKeyCipheredBase64);
      Uint8List masterKeyNonceBytes = base64Decode(masterKeyNonceBase64);

      ExecutionResult masterKeyDecryptionResult = cryptoUtils.decryptBytes(
          cipherBytes: masterKeyCipheredBytes,
          nonce: masterKeyNonceBytes,
          key: accessKeyBytes);

      if (masterKeyDecryptionResult.isFailure) {
        if (mounted) showAlertMessage(context, "Failure", "Invalid access key");
      } else {
        Uint8List decryptedMasterKeyBytes =
            masterKeyDecryptionResult.getResult()!["decrypted"];
        String decryptedMasterKeyBase64 = base64Encode(decryptedMasterKeyBytes);

        String fileHashKeyBase64 = cryptoUtils.getHashingKeyFromMasterKey(
            decryptedMasterKeyBase64, AppString.fileHashKeyContext.string, 1);

        // Save keys to secure storage
        await secureStorage.write(
            key: AppString.masterKey.string, value: decryptedMasterKeyBase64);
        await secureStorage.write(
            key: AppString.accessKey.string,
            value: base64Encode(accessKeyBytes));
        await secureStorage.write(
            key: AppString.fileHashKey.string, value: fileHashKeyBase64);

        // Delete keycipher and keynonce
        await secureStorage.delete(key: AppString.keyCipher.string);
        await secureStorage.delete(key: AppString.keyNonce.string);

        if (mounted) {
          await context.read<AppSetupState>().registerDevice();
        }
      }
    } catch (e) {
      if (mounted) {
        showAlertMessage(context, "Error",
            "An unexpected error occurred during decryption.");
      }
    } finally {
      if (mounted) {
        setState(() => processing = false);
      }
    }
  }

  /// Handles file selection and validation
  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();

        if (_validateWordCount(content)) {
          // Update the text field so the user sees what was loaded
          _textController.text = content.trim();
          await _processWords(content.trim());
        } else {
          if (mounted) {
            showAlertMessage(context, "Error",
                'The file does not contain exactly 24 words.');
          }
        }
      }
    } catch (e) {
      if (mounted) {
        displaySnackBar(context, message: "Error reading file", seconds: 2);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine dynamic color for the word counter

    return Scaffold(
      appBar: AppBar(
        title: const Text('Encryption'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  LucideIcons.shieldCheck,
                  size: 48,
                  color: Colors.blueAccent,
                ),
                const SizedBox(height: 16.0),
                const Text(
                  "Enter your 24-word recovery phrase or load a .txt file to securely enable cloud sync.",
                  style: TextStyle(fontSize: 16.0, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32.0),

                // TextField with enhanced UX
                TextFormField(
                  controller: _textController,
                  enabled: !processing,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 6,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Recovery Phrase',
                    alignLabelWithHint: true,
                    hintText: 'word1 word2 word3...',
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceVariant
                        .withOpacity(0.3),

                    // GUARANTEED TO UPDATE: ValueListenableBuilder listens directly to the controller
                    counter: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _textController,
                      builder: (context, value, child) {
                        // Calculate word count in real-time
                        final text = value.text.trim();
                        final wordCount = text.isEmpty
                            ? 0
                            : text.split(RegExp(r'\s+')).length;

                        // Determine dynamic color
                        final counterColor = wordCount == 24
                            ? Colors.green.shade700
                            : (wordCount > 24
                                ? Colors.red
                                : Colors.grey.shade600);

                        return Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton.icon(
                              onPressed:
                                  processing ? null : _pasteFromClipboard,
                              icon: const Icon(LucideIcons.clipboardPaste,
                                  size: 16),
                              label: const Text("Paste"),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            Text(
                              '$wordCount / 24 words',
                              style: TextStyle(
                                color: counterColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your recovery phrase';
                    }
                    if (!_validateWordCount(value)) {
                      return 'Must contain exactly 24 words';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24.0),

                // Submit Button
                FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: processing
                      ? null
                      : () {
                          if (_formKey.currentState!.validate()) {
                            // Hide keyboard on submit
                            FocusScope.of(context).unfocus();
                            _processWords(_textController.text);
                          }
                        },
                  child: processing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Verify',
                          style: TextStyle(
                              fontSize: 16.0, fontWeight: FontWeight.bold),
                        ),
                ),
                const SizedBox(height: 24.0),

                // Separator Line
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'OR',
                        style: TextStyle(
                          fontSize: 12.0,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 24.0),

                // File Upload Button
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: processing ? null : _selectFile,
                  icon: const Icon(LucideIcons.fileText),
                  label: const Text(
                    "Load from .txt File",
                    style: TextStyle(fontSize: 16.0),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
