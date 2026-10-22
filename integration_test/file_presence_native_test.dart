import 'dart:io';

import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../test/file_list_item_presence_test.dart' as presence;
import '../test/item_selection_actions_test.dart' as actions;
import 'support/iphone_results.dart';
import 'support/native_test_identity.dart';
import 'support/native_test_install.dart';

/// Run in a fresh per-run native fixture so the owner's selected folders
/// and current manual-test vault are preserved. This fixture controls the Files
/// permission boundary; it does not open or alter the owner's selected files.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  var isolatedInstallVerified = false;
  recordIphoneResults(binding, 'file-presence-and-actions');
  setUpAll(() async {
    expect(const bool.fromEnvironment('FIFE_RUN_FILE_PRESENCE_TESTS'), isTrue);
    expect(AppEnv.localTestingBuild, isTrue);
    final bundle = (await PackageInfo.fromPlatform()).packageName;
    expect(isIsolatedNativeTestBundle(bundle), isTrue);
    await verifyNativeTestStorageIsolation(bundle);
    isolatedInstallVerified = true;
  });
  presence.main();
  actions.main();
  tearDownAll(() async {
    if (!isolatedInstallVerified) return;
    await StorageSqlite.instance.close();
    final databases = await getDbStoragePath();
    final documents = await getApplicationDocumentsDirectory();
    // The native app removes its own sandbox data; terminal cleanup may be
    // denied by macOS container privacy even for a disposable test install.
    for (final directory in [
      Directory(databases),
      Directory('${documents.path}/FiFe/Temp'),
    ]) {
      if (await directory.exists()) await directory.delete(recursive: true);
      expect(await directory.exists(), isFalse);
    }
  });
}
