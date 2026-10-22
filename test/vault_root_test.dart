import 'dart:async';

import 'package:file_vault_bb/models/model_item.dart';
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_session_work.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/ui/common_widgets.dart';
import 'package:file_vault_bb/utils/enums.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async => fixture = await SyncFixture.create());
  tearDown(() => fixture.dispose());

  test('an obsolete failed key read cannot hide a newer sign-in state',
      () async {
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'no');
    final setup = AppSetupState(SecureStorage());
    final entered = Completer<void>(), release = Completer<void>();
    try {
      await setup.recheckStatus();
      fixture.beforeRead = (key) async {
        if (key == AppString.masterKey.string) {
          entered.complete();
          await release.future;
          throw PlatformException(code: 'OLD_KEY_READ_FAILED');
        }
      };
      await ModelSetting.set(AppString.signedIn.string, 'yes');
      final obsolete = setup.recheckStatus();
      await entered.future;
      await ModelSetting.set(AppString.signedIn.string, 'no');
      await setup.recheckStatus();
      expect(setup.currentStep, SetupStep.signin);
      release.complete();
      await obsolete;
      expect(setup.currentStep, SetupStep.signin);
    } finally {
      if (!release.isCompleted) release.complete();
      setup.dispose();
    }
  });

  test('a current key read failure still hides private UI', () async {
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
    fixture.beforeRead = (key) async {
      if (key == AppString.masterKey.string) {
        throw PlatformException(code: 'KEY_STORAGE_UNAVAILABLE');
      }
    };
    final setup = AppSetupState(SecureStorage());
    try {
      await setup.recheckStatus();
      expect(setup.currentStep, SetupStep.sessionCleanup);
    } finally {
      setup.dispose();
    }
  });

  test('concurrent root restoration preserves all other data and sync queues',
      () async {
    final before = await fixture.snapshot();
    final roots =
        await Future.wait(List.generate(4, (_) => ModelItem.ensureVaultRoot()));
    expect(roots.map((root) => root.id).toSet(), {'fife'});
    expect(
        roots.every((root) =>
            root.name == 'FiFe' && root.isFolder && root.parentId == null),
        isTrue);
    final after = await fixture.snapshot();
    expect(after['items']!.where((row) => row['id'] == 'fife'), hasLength(1));
    after['items'] =
        after['items']!.where((row) => row['id'] != 'fife').toList();
    expect(after, before);
  });

  test('existing root metadata is left intact on repeated setup', () async {
    final db = await fixture.db;
    await db.insert('items', {
      'id': 'fife',
      'name': 'FiFe',
      'is_folder': 1,
      'updated_at': 123,
      'data': '{"preserve":true}'
    });
    final before = await fixture.snapshot();
    await ModelItem.ensureVaultRoot();
    await ModelItem.ensureVaultRoot();
    expect(await fixture.snapshot(), before);
  });

  test('invalidated work cannot recreate a root after cleanup', () async {
    SessionWork.invalidate('removed-vault');
    await expectLater(
        ModelItem.ensureVaultRoot(), throwsA(isA<SessionInvalidated>()));
    expect(
        await (await fixture.db)
            .query('items', where: 'id = ?', whereArgs: ['fife']),
        isEmpty);
  });
}
