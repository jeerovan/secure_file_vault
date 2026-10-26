import 'dart:convert';

import 'package:file_vault_bb/l10n/app_localizations.dart';
import 'package:file_vault_bb/services/service_app_lock.dart';
import 'package:file_vault_bb/services/service_recovery_phrase.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/ui/pages/page_recovery_phrase_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'recovery_phrase_export_test.dart'
    show RecoveryPlatformProbe, syntheticRecoveryPhrase;
import 'support/app_lock_fixture.dart';

void main() {
  testWidgets('opening the phrase never copies or downloads without a tap',
      (tester) async {
    SessionWork.resetForTesting();
    final lock = AppLockController(
        store: MemoryAppLockStore()..enabled = true,
        authenticator: FakeAppLockAuthenticator());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      lock.dispose();
      SessionWork.resetForTesting();
    });
    await lock.load();
    expect(await lock.unlock(testAppLockPrompt), isTrue);
    final proof = await lock.authorizeSensitiveAction(testAppLockPrompt);
    expect(proof, isNotNull);
    final platform = RecoveryPlatformProbe();
    await tester.pumpWidget(MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RecoveryPhraseExportPage(
            authorization: proof!,
            service: RecoveryPhraseService(
                readAccessKey: () async => base64Encode(Uint8List(32)),
                signedIn: () async => true,
                platform: platform))));
    await tester.pumpAndSettle();
    expect(find.text(syntheticRecoveryPhrase), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(platform.copied, isEmpty,
        reason: 'Opening or reading must leave the clipboard untouched');
    expect(platform.saved, isEmpty,
        reason: 'Opening or reading must not create a saved copy');
    expect(find.byType(SnackBar), findsNothing);

    await tester.tap(find.byKey(const ValueKey('recovery-phrase-copy')));
    await tester.pumpAndSettle();
    expect(platform.copied, [syntheticRecoveryPhrase]);
    expect(platform.saved, isEmpty);

    await tester.tap(find.byKey(const ValueKey('recovery-phrase-download')));
    await tester.pumpAndSettle();
    expect(platform.saved, [syntheticRecoveryPhrase]);
    expect(platform.copied, [syntheticRecoveryPhrase],
        reason: 'Saving must not also copy to the clipboard');
  });
}
