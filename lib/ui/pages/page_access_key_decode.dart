import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../l10n/app_localizations.dart';
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

  bool _validateWordCount(String input) {
    final words = input.trim().split(RegExp(r'\s+'));
    return words.length == 24;
  }

  Future<void> _pasteFromClipboard() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData?.text != null) {
      _textController.text = clipboardData!.text!;
    }
  }

  Future<void> _processWords(String words) async {
    setState(() => processing = true);

    try {
      words = utf8.decode(utf8.encode(words.trim()));
      words = words.replaceAll(RegExp(r'\s+'), ' ');

      SodiumSumo sodium = await SodiumSumoInit.init();
      CryptoUtils cryptoUtils = CryptoUtils(sodium);

      if (!bip39.validateMnemonic(words)) {
        if (mounted) {
          showAlertMessage(
            context,
            AppLocalizations.of(context)!.errorTitle,
            AppLocalizations.of(context)!.invalidWordList,
          );
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
        key: accessKeyBytes,
      );

      if (masterKeyDecryptionResult.isFailure) {
        if (mounted) {
          showAlertMessage(
            context,
            AppLocalizations.of(context)!.failureTitle,
            AppLocalizations.of(context)!.invalidAccessKey,
          );
        }
      } else {
        Uint8List decryptedMasterKeyBytes =
            masterKeyDecryptionResult.getResult()!["decrypted"];
        String decryptedMasterKeyBase64 = base64Encode(decryptedMasterKeyBytes);
        String decryptedAccessKeyBase64 = base64Encode(accessKeyBytes);
        String fileHashKeyBase64 = cryptoUtils.getHashingKeyFromMasterKey(
          decryptedMasterKeyBase64,
          AppString.fileHashKeyContext.string,
          1,
        );
        if (simulateTesting()) {
          String savedMasterKey = await secureStorage.read(
              key: AppString.masterKey.string) as String;
          String savedAccessKey = await secureStorage.read(
              key: AppString.accessKey.string) as String;
          String savedFileHashKey = await secureStorage.read(
              key: AppString.fileHashKey.string) as String;
          if (mounted &&
              savedMasterKey == decryptedMasterKeyBase64 &&
              savedAccessKey == decryptedAccessKeyBase64 &&
              savedFileHashKey == fileHashKeyBase64) {
            displaySnackBar(context, message: "Keys Matched", seconds: 2);
          } else if (mounted) {
            displaySnackBar(context, message: "Keys DID NOT Match", seconds: 2);
          }
        } else {
          await secureStorage.write(
            key: AppString.masterKey.string,
            value: decryptedMasterKeyBase64,
          );
          await secureStorage.write(
            key: AppString.accessKey.string,
            value: decryptedAccessKeyBase64,
          );
          await secureStorage.write(
            key: AppString.fileHashKey.string,
            value: fileHashKeyBase64,
          );
        }
        await secureStorage.delete(key: AppString.keyCipher.string);
        await secureStorage.delete(key: AppString.keyNonce.string);

        if (mounted) {
          await context.read<AppSetupState>().registerDevice();
        }
      }
    } catch (e) {
      if (mounted) {
        showAlertMessage(
          context,
          AppLocalizations.of(context)!.errorTitle,
          AppLocalizations.of(context)!.unexpectedDecryptionError,
        );
      }
    } finally {
      if (mounted) {
        setState(() => processing = false);
      }
    }
  }

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
          _textController.text = content.trim();
          await _processWords(content.trim());
        } else {
          if (mounted) {
            showAlertMessage(
              context,
              AppLocalizations.of(context)!.errorTitle,
              AppLocalizations.of(context)!.fileMustContainExactly24Words,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        displaySnackBar(
          context,
          message: AppLocalizations.of(context)!.errorReadingFile,
          seconds: 2,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.encryptionTitle),
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
                Text(
                  AppLocalizations.of(context)!.accessKeyDecodeDescription,
                  style: const TextStyle(fontSize: 16.0, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32.0),
                TextFormField(
                  controller: _textController,
                  enabled: !processing,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 6,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText:
                        AppLocalizations.of(context)!.recoveryPhraseLabel,
                    alignLabelWithHint: true,
                    hintText: AppLocalizations.of(context)!.recoveryPhraseHint,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withAlpha(60),
                    counter: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _textController,
                      builder: (context, value, child) {
                        final text = value.text.trim();
                        final wordCount = text.isEmpty
                            ? 0
                            : text.split(RegExp(r'\s+')).length;

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
                              icon: const Icon(
                                LucideIcons.clipboardPaste,
                                size: 16,
                              ),
                              label: Text(
                                AppLocalizations.of(context)!.paste,
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 30),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            Text(
                              AppLocalizations.of(context)!
                                  .wordCountLabel(wordCount),
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
                      return AppLocalizations.of(context)!
                          .pleaseEnterRecoveryPhrase;
                    }
                    if (!_validateWordCount(value)) {
                      return AppLocalizations.of(context)!
                          .mustContainExactly24Words;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24.0),
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
                      : Text(
                          AppLocalizations.of(context)!.verify,
                          style: const TextStyle(
                            fontSize: 16.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                const SizedBox(height: 24.0),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        AppLocalizations.of(context)!.orLabel,
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
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: processing ? null : _selectFile,
                  icon: const Icon(LucideIcons.fileText),
                  label: Text(
                    AppLocalizations.of(context)!.loadFromTxtFile,
                    style: const TextStyle(fontSize: 16.0),
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
