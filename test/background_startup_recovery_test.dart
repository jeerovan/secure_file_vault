import 'package:file_vault_bb/main.dart' as application;
import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/services/service_background_execution.dart';
import 'package:file_vault_bb/storage/storage_secure.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/sync_fixture.dart';

class _Scheduler implements IosBackgroundScheduler {
  int initialized = 0;
  bool pending = false;

  @override
  Future<void> initialize(Function callbackDispatcher) async => initialized++;

  @override
  Future<void> schedule() async => pending = true;

  @override
  Future<void> cancel() async => pending = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SyncFixture fixture;
  setUp(() async {
    fixture = await SyncFixture.create();
    await ModelSetting.set(AppString.onboarding.string, 'yes');
    await ModelSetting.set(AppString.signedIn.string, 'yes');
  });
  tearDown(() => fixture.dispose());

  test('pending-reset startup initializes iOS without reading private keys',
      () async {
    await SecureStorage().write(
        key: AppString.recoveryResetStage.string, value: 'pending fixture');
    fixture.beforeRead = (key) async {
      if (key == AppString.masterKey.string) {
        fail('Pending reset must not read the retired master key');
      }
    };
    final scheduler = _Scheduler();
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.iosRefresh,
        iosScheduler: scheduler,
        iosSessionReady: isIosBackgroundSyncReady);

    await application.initializeBackgroundExecution(execution: service);

    expect(scheduler.initialized, 1);
    expect(scheduler.pending, isFalse);
  });

  test('iOS setup can schedule after startup with a pending reset', () async {
    await SecureStorage().write(
        key: AppString.recoveryResetStage.string, value: 'pending fixture');
    final scheduler = _Scheduler();
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.iosRefresh,
        iosScheduler: scheduler,
        iosSessionReady: isIosBackgroundSyncReady);
    // Use the actual application startup policy. Do not initialize the service
    // in the fixture: that supplied the prerequisite missed by earlier tests.
    await application.initializeBackgroundExecution(execution: service);
    expect(scheduler.pending, isFalse);
    await SecureStorage().delete(key: AppString.recoveryResetStage.string);

    expect(await service.setEnabled(true), isTrue);
    expect(scheduler.pending, isTrue);
    expect(scheduler.initialized, 1);
    await service.cancelIosWork();
    expect(scheduler.pending, isFalse);
  });

  test('pending reset still defers non-iOS background startup', () async {
    await SecureStorage().write(
        key: AppString.recoveryResetStage.string, value: 'pending fixture');
    final scheduler = _Scheduler();
    final service = BackgroundExecutionService.test(
        kind: BackgroundExecutionKind.desktopTimer, iosScheduler: scheduler);

    await application.initializeBackgroundExecution(execution: service);

    expect(scheduler.initialized, 0);
    expect(scheduler.pending, isFalse);
  });
}
