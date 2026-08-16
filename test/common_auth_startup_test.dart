import 'package:file_vault_bb/models/model_setting.dart';
import 'package:file_vault_bb/utils/common.dart';
import 'package:file_vault_bb/utils/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(ModelSetting.clear);

  test('test-account startup skips Neon Auth before configuration access',
      () async {
    ModelSetting.settingJson[AppString.simulateTesting.string] = 'yes';

    await expectLater(refreshNeonAuth(), completes);
  });
}
