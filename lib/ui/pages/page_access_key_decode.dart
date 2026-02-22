import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:lucide_icons/lucide_icons.dart';
import '../../utils/common.dart';
import '../../ui/common_widgets.dart';
import '../../storage/storage_secure.dart';
import '../../utils/utils_crypto.dart';
import 'package:provider/provider.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';

import '../../utils/enums.dart';

class PageAccessKeyDecode extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  const PageAccessKeyDecode(
      {super.key, required this.runningOnDesktop, this.setShowHidePage});

  @override
  State<PageAccessKeyDecode> createState() => _PageAccessKeyDecodeState();
}

class _PageAccessKeyDecodeState extends State<PageAccessKeyDecode> {
  final _formKey = GlobalKey<FormState>();
  final _textController = TextEditingController();
  String _loadedFileContent = '';
  bool processing = false;
  SecureStorage secureStorage = SecureStorage();

  @override
  void initState() {
    super.initState();
    if (simulateTesting()) {
      simulateKeyInput();
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> simulateKeyInput() async {
    String? accessKeyBase64 =
        await secureStorage.read(key: AppString.accessKey.string);
    Uint8List accessKeyBytes = base64Decode(accessKeyBase64!);
    String accessKeyHex = bytesToHex(accessKeyBytes);
    if (mounted) {
      setState(() {
        _textController.text = bip39.entropyToMnemonic(accessKeyHex);
      });
    }
  }

  /// Validates input to ensure it contains exactly 24 words
  bool _validateWordCount(String input) {
    final words = input.trim().split(RegExp(r'\s+'));
    return words.length == 24;
  }

  /// Processes the validated 24 words further
  Future<void> _processWords(String words) async {
    words = words.trim();
    setState(() {
      processing = true;
    });
    words = utf8.decode(utf8.encode(words));
    words = words.trim().replaceAll(RegExp(r'\s+'), ' ');
    SodiumSumo sodium = await SodiumSumoInit.init();
    CryptoUtils cryptoUtils = CryptoUtils(sodium);
    if (!bip39.validateMnemonic(words)) {
      if (mounted) {
        showAlertMessage(context, "Error", "Invalid word list");
        setState(() {
          processing = false;
        });
      }
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
      if (mounted) {
        showAlertMessage(context, "Failure", "Invalid access key");
      }
    } else {
      Uint8List decryptedMasterKeyBytes =
          masterKeyDecryptionResult.getResult()!["decrypted"];
      String decryptedMasterKeyBase64 = base64Encode(decryptedMasterKeyBytes);

      // save keys to secure storage
      await secureStorage.write(
          key: AppString.masterKey.string, value: decryptedMasterKeyBase64);
      await secureStorage.write(
          key: AppString.accessKey.string, value: base64Encode(accessKeyBytes));

      // delete keycipher and keynonce
      await secureStorage.delete(key: AppString.keyCipher.string);
      await secureStorage.delete(key: AppString.keyNonce.string);

      if (mounted) {
        await context.read<AppSetupState>().registerDevice();
      }
    }
    setState(() {
      processing = false;
    });
  }

  /// Handles file selection and validation
  Future<void> _selectFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
      );
      if (result != null) {
        final file = File(result.files.single.path!);
        final content = await file.readAsString();
        if (_validateWordCount(content)) {
          setState(() {
            _loadedFileContent = content.trim();
          });
          _processWords(_loadedFileContent);
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
    return Scaffold(
      appBar: AppBar(
        title: Text('Enable Sync'),
        leading: widget.runningOnDesktop
            ? BackButton(
                onPressed: () {
                  widget.setShowHidePage!(
                      PageType.accessKeyInput, false, PageParams());
                },
              )
            : null,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Text Widget
                Text(
                  "Please enter your 24-word recovery phrase or load a .txt file containing it.",
                  style: TextStyle(fontSize: 16.0),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.0),

                // TextField with Validation
                TextFormField(
                  controller: _textController,
                  autofocus: true,
                  maxLines: null, // Allows all words to be visible
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Enter your 24-word phrase',
                    border: OutlineInputBorder(),
                    hintText: 'Enter your recovery phrase here',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your recovery phrase';
                    }
                    if (!_validateWordCount(value)) {
                      return 'Recovery phrase must contain exactly 24 words';
                    }
                    return null;
                  },
                  onEditingComplete: () {
                    _processWords(_textController.text);
                  },
                ),
                SizedBox(height: 20.0),

                // Submit Button
                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      _processWords(_textController.text);
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (processing)
                        Padding(
                          padding: const EdgeInsets.only(
                              right:
                                  8.0), // Add spacing between indicator and text
                          child: SizedBox(
                            width: 16, // Set width and height for the indicator
                            height: 16,
                            child: CircularProgressIndicator(
                              color: Colors.black,
                              strokeWidth: 2, // Set color to white
                            ),
                          ),
                        ),
                      Text(
                        'Submit',
                        style: TextStyle(fontSize: 16.0, color: Colors.black),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 30.0),

                // Separator Line
                Row(
                  children: [
                    Expanded(child: Divider(thickness: 1)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        'Or',
                        style: TextStyle(
                            fontSize: 14.0, fontWeight: FontWeight.w500),
                      ),
                    ),
                    Expanded(child: Divider(thickness: 1)),
                  ],
                ),
                SizedBox(height: 20.0),

                // File Upload Button
                ElevatedButton.icon(
                  onPressed: _selectFile,
                  icon: Icon(
                    LucideIcons.upload,
                    color: Colors.black,
                  ),
                  label: Text(
                    "Select .txt File",
                    style: TextStyle(color: Colors.black),
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
