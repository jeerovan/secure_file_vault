import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/storage/storage_sqlite.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

import 'support/apple_bookmark.dart';
import 'support/native_test_install.dart';

/// A synthetic app-owned root exercises the real iOS bookmark channel and row.
/// External Files permissions and production account data are not modified.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  var isolated = false;
  final checks = <String, bool>{};
  setUpAll(() async {
    await verifyNativeTestInstall();
    expect(Platform.isIOS, isTrue);
    expect(
        const bool.fromEnvironment('FIFE_RUN_FOLDER_INDICATOR_TESTS'), isTrue);
    isolated = true;
  });
  unawaited(binding.allTestsPassed.future.then((passed) async {
    if (!isolated) return;
    runApp(MaterialApp(
        home: Scaffold(
            appBar: AppBar(title: const Text('Folder reconnect test')),
            body: Center(
                child: Text(passed ? 'Test completed' : 'Test stopped')))));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final documents = await getApplicationDocumentsDirectory();
      await File('${documents.path}/fife-folder-indicator-result.json')
          .writeAsString(
              jsonEncode({
                'runId': const String.fromEnvironment('FIFE_NATIVE_RUN_ID'),
                'passed': passed,
                'failureCount': binding.failureMethodsDetails.length,
                'checks': checks,
                'resultFrameBuilt': true,
              }),
              flush: true);
    });
  }));

  testWidgets('root warning follows real native bookmark availability',
      (tester) async {
    await StorageSqlite.initialize(ExecutionMode.mainApp);
    // The retained source app must still be signed out before this fixture.
    expect(await ModelSetting.getRaw(AppString.signedIn.string), isNot('yes'));
    final db = await StorageSqlite.instance.database;
    expect(await db.query('profiles'), isEmpty);
    final device = await getDeviceHash();
    final temporary = await getTemporaryDirectory();
    final fixture = await temporary.createTemp('folder-indicator-');
    final directory = await Directory('${fixture.path}/selected').create();
    final selected = ValueNotifier<Set<ModelItem>>({});
    final multiSelect = ValueNotifier(false);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      selected.dispose();
      multiSelect.dispose();
      if (await fixture.exists()) await fixture.delete(recursive: true);
      await StorageSqlite.instance.close();
    });

    Future<void> show(String bookmark,
        {required bool warning, String? storedPath}) async {
      final item = await ModelItem.fromMap({
        'id': 'native-folder-indicator-root',
        'parent_id': device,
        'root_id': 'native-folder-indicator-root',
        'name': 'Generated sync folder',
        'is_folder': 1,
        'path': storedPath ?? directory.path,
        'bookmark': bookmark,
      });
      await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
              body: FileListItem(
            key: const ValueKey('native-folder-indicator'),
            item: item,
            selectedItemsNotifier: selected,
            isMultiSelectNotifier: multiSelect,
            onTap: () {},
            onLongPress: () {},
          ))));
      final deadline = DateTime.now().add(const Duration(seconds: 20));
      // Every row check must finish, including the first matching/no-icon case.
      do {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      } while ((find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
              find.byIcon(LucideIcons.alertCircle).evaluate().isNotEmpty !=
                  warning) &&
          DateTime.now().isBefore(deadline));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(LucideIcons.alertCircle),
          warning ? findsOneWidget : findsNothing);
    }

    final bookmark = createAppleTestBookmark(directory.path);
    await show(bookmark,
        warning: false, storedPath: '/obsolete-container/generated-folder');
    expect(find.byIcon(LucideIcons.alertCircle), findsNothing);
    checks['resolvedNativeBookmarkIgnoresObsoleteStoredPath'] = true;

    // Real Foundation bookmark resolution follows this move; the target still
    // exists. This is a native component check, not a substitute for deleting
    // an external provider folder through Files and resuming the normal app.
    await Directory('${fixture.path}/.Trash').create();
    final trashed = await directory.rename('${fixture.path}/.Trash/selected');
    expect(await trashed.exists(), isTrue);
    await show(bookmark, warning: true);
    checks['readableTrashedNativeFolderShowsReconnectWarning'] = true;

    await trashed.rename(directory.path);
    await show(bookmark, warning: false);
    checks['restoredNativeBookmarkClearsWarning'] = true;

    await directory.delete();
    await show(bookmark, warning: true);
    expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
    checks['removedNativeFolderShowsReconnectWarning'] = true;

    await directory.create();
    await show(createAppleTestBookmark(directory.path), warning: false);
    expect(find.byIcon(LucideIcons.alertCircle), findsNothing);
    checks['replacementBookmarkClearsSameRootWarning'] = true;

    await show('invalid-native-bookmark', warning: true);
    expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
    checks['nativeResolutionFailureShowsReconnectWarning'] = true;
    expect(await directory.exists(), isTrue);
  });
}
