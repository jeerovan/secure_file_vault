import 'package:file_vault_bb/models/model_item_task.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retry delay grows exponentially and caps at fifteen minutes', () {
    expect(ModelItemTask.retryDelayForAttempt(1), const Duration(seconds: 5));
    expect(ModelItemTask.retryDelayForAttempt(2), const Duration(seconds: 10));
    expect(ModelItemTask.retryDelayForAttempt(9), const Duration(seconds: 900));
    expect(
        ModelItemTask.retryDelayForAttempt(100), const Duration(seconds: 900));
  });

  test('retry jitter is stable and remains capped', () {
    expect(
      ModelItemTask.retryDelayWithJitter(2, 'item'),
      ModelItemTask.retryDelayWithJitter(2, 'item'),
    );
    expect(
      ModelItemTask.retryDelayWithJitter(100, 'item'),
      const Duration(minutes: 15),
    );
  });

  test('retry attempts are bounded', () {
    expect(ModelItemTask.maxRetryAttempts, 10);
  });
}
