import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/services/service_locale.dart';
import 'package:file_vault_bb/ui/archive_backup_confirmation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Archive backup confirmation is translated in every supported locale',
      () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    for (final locale in L10n.all) {
      final strings = await AppLocalizations.delegate.load(locale);
      expect(strings.archiveBackup.trim(), isNotEmpty);
      expect(strings.archiveFolderBackupMessage.trim(), isNotEmpty);
      if (locale.languageCode != 'en') {
        expect(strings.archiveFolderBackupMessage,
            isNot(english.archiveFolderBackupMessage),
            reason: locale.toString());
      }
    }
  });

  for (final locale in [const Locale('en'), const Locale('ar')]) {
    testWidgets(
        'Archive confirmation supports Cancel and large text in $locale',
        (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final folder = await ModelItem.fromMap(
          {'id': 'test-folder', 'name': 'synthetic', 'is_folder': 1});
      final strings = await AppLocalizations.delegate.load(locale);
      bool? result;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Builder(
            builder: (context) => Scaffold(
                    body: TextButton(
                  child: const Text('Open'),
                  onPressed: () async =>
                      result = await confirmArchiveBackup(context, [folder]),
                ))),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(TextButton, strings.cancel));
      await tester.pumpAndSettle();
      expect(result, isFalse);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, strings.archiveBackup));
      await tester.pumpAndSettle();
      expect(result, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
