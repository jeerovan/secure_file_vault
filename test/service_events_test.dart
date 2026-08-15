import 'package:file_vault_bb/services/service_events.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('published events reach stream subscribers', () async {
    final event = AppEvent(
      type: EventType.system,
      id: 'metadata',
      key: EventKey.running,
    );
    final received = EventStream().events.first;

    EventStream().publish(event);

    expect(await received, same(event));
    expect(EventStream().notifier.value, same(event));
  });
}
