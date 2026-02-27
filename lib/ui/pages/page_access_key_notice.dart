import 'package:file_vault_bb/services/service_backend.dart';

import '../../services/service_logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sodium_libs/sodium_libs_sumo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/common.dart';
import '../common_widgets.dart';
import '../../utils/enums.dart';
import '../../storage/storage_secure.dart';
import '../../utils/utils_crypto.dart';

class PageAccessKeyNotice extends StatefulWidget {
  final bool runningOnDesktop;
  final Function(PageType, bool, PageParams)? setShowHidePage;
  const PageAccessKeyNotice(
      {super.key, required this.runningOnDesktop, this.setShowHidePage});

  @override
  State<PageAccessKeyNotice> createState() => _PageAccessKeyNoticeState();
}

class _PageAccessKeyNoticeState extends State<PageAccessKeyNotice> {
  AppLogger logger = AppLogger(prefixes: ["PageAccessKeyNotice"]);
  SupabaseClient supabaseClient = Supabase.instance.client;
  SecureStorage secureStorage = SecureStorage();
  final api = BackendApi();
  bool processing = false;
  String appName = AppString.appName.string;

  @override
  void initState() {
    super.initState();
  }

  Future<void> generateKeys() async {
    String? userId = getSignedInUserId();
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
    serverKeys['id'] = userId;
    try {
      final result = await api.post(endpoint: '/keys', jsonBody: serverKeys);
      final status = result["status"];
      if (status <= 0) {
        if (mounted) {
          displaySnackBar(context, message: result["error"], seconds: 2);
        }
      } else {
        String masterKeyBase64 = privateKeys[AppString.masterKey.string];
        String accessKeyBase64 = privateKeys[AppString.accessKey.string];
        await secureStorage.write(
            key: AppString.masterKey.string, value: masterKeyBase64);
        await secureStorage.write(
            key: AppString.accessKey.string, value: accessKeyBase64);
        // navigate to display key
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
          title: Text('Important'),
          leading: widget.runningOnDesktop
              ? BackButton(
                  onPressed: () {
                    widget.setShowHidePage!(
                        PageType.accessKeyCreate, false, PageParams());
                  },
                )
              : null),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 20),
            Text(
              'On the next page you\'ll see a series of 24 words. This is your unique and private encryption key and it is the ONLY way to recover your data in case of logout, device loss or malfunction.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
            SizedBox(height: 20),
            Text(
              'We do not store the key. It is YOUR responsibility to store it in a safe place outside of $appName app.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: generateKeys,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (processing)
                    Padding(
                      padding: const EdgeInsets.only(
                          right: 8.0), // Add spacing between indicator and text
                      child: SizedBox(
                        width: 16, // Set width and height for the indicator
                        height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2, // Set color to white
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      textAlign: TextAlign.center,
                      'I understand.\nShow me the key.',
                      style: TextStyle(color: Colors.black),
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
