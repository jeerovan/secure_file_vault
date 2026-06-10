import 'package:file_vault_bb/services/service_backend.dart';

import '../../l10n/app_localizations.dart';
import '../../services/service_logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sodium/sodium_sumo.dart';

import '../../utils/common.dart';
import '../common_widgets.dart';
import '../../utils/enums.dart';
import '../../storage/storage_secure.dart';
import '../../utils/utils_crypto.dart';

class PageAccessKeyNotice extends StatefulWidget {
  const PageAccessKeyNotice({super.key});

  @override
  State<PageAccessKeyNotice> createState() => _PageAccessKeyNoticeState();
}

class _PageAccessKeyNoticeState extends State<PageAccessKeyNotice> {
  AppLogger logger = AppLogger(prefixes: ["PageAccessKeyNotice"]);
  SecureStorage secureStorage = SecureStorage();
  final api = BackendApi();
  bool processing = false;
  String appName = AppString.appName.string;

  @override
  void initState() {
    super.initState();
  }

  Future<void> generateKeys() async {
    String? userId = await getSignedInUserId();
    if (userId == null) return;
    setState(() {
      processing = true;
    });

    SodiumSumo sodium = await SodiumSumoInit.init();
    CryptoUtils cryptoUtils = CryptoUtils(sodium);

    ExecutionResult generationResult = cryptoUtils.generateKeys();
    Map<String, dynamic> keys = generationResult.getResult()!;
    Map<String, dynamic> privateKeys = keys[AppString.privateKeys.string];
    Map<String, dynamic> serverKeys = keys[AppString.serverKeys.string];
    try {
      bool showKeys = true;
      if (simulateTesting()) {
        await Future.delayed(const Duration(seconds: 1));
        await secureStorage.write(
          key: AppString.keyCipher.string,
          value: serverKeys[AppString.cipher.string],
        );
        await secureStorage.write(
          key: AppString.keyNonce.string,
          value: serverKeys[AppString.nonce.string],
        );
      } else {
        final result = await api.post(endpoint: '/keys', jsonBody: serverKeys);
        final status = result["success"];
        if (status <= 0) {
          showKeys = false;
          if (mounted) {
            displaySnackBar(
              context,
              message: result["message"].toString(),
              seconds: 2,
            );
          }
        }
      }
      if (showKeys) {
        String masterKeyBase64 = privateKeys[AppString.masterKey.string];
        String accessKeyBase64 = privateKeys[AppString.accessKey.string];
        String fileHashKeyBase64 = privateKeys[AppString.fileHashKey.string];
        await secureStorage.write(
          key: AppString.masterKey.string,
          value: masterKeyBase64,
        );
        await secureStorage.write(
          key: AppString.accessKey.string,
          value: accessKeyBase64,
        );
        await secureStorage.write(
          key: AppString.fileHashKey.string,
          value: fileHashKeyBase64,
        );
        if (mounted) {
          await context.read<AppSetupState>().showAccessKeys();
        }
      }
    } catch (e, s) {
      logger.error("generateKeys", error: e, stackTrace: s);
    }
    setState(() {
      processing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.importantTitle),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!.accessKeyNoticePrimary,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 20),
            Text(
              AppLocalizations.of(context)!
                  .accessKeyNoticeResponsibility(appName),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: processing ? null : generateKeys,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (processing)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DefaultTextStyle.of(context).style.color,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      AppLocalizations.of(context)!.showKeyConfirmation,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
