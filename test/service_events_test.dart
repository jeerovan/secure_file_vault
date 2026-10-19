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

  test('foreground sync state messages round-trip across isolates', () {
    final running = ForegroundSyncStateMessage.encode(isRunning: true);
    final stopped = ForegroundSyncStateMessage.encode(isRunning: false);

    expect(ForegroundSyncStateMessage.decode(running), isTrue);
    expect(ForegroundSyncStateMessage.decode(stopped), isFalse);
    expect(ForegroundSyncStateMessage.decode({'type': 'unrelated'}), isNull);
    expect(ForegroundSyncStateMessage.decode('invalid'), isNull);
  });

  test('sync activity excludes settings, progress values, and service echoes',
      () {
    for (final key in [EventKey.running, EventKey.stopped]) {
      expect(
          isSyncActivityEvent(AppEvent(
            type: EventType.system,
            id: 'metadata',
            key: key,
          )),
          isTrue);
      expect(
          isSyncActivityEvent(AppEvent(
            type: EventType.system,
            id: 'root',
            key: key,
          )),
          isTrue);
      expect(
          isSyncActivityEvent(AppEvent(
            type: EventType.system,
            id: 'foregroundSync',
            key: key,
          )),
          isFalse);
      expect(
          isSyncActivityEvent(AppEvent(
            type: EventType.settings,
            id: 'metadata',
            key: key,
          )),
          isFalse);
    }
    expect(
        isSyncActivityEvent(AppEvent(
          type: EventType.system,
          id: 'metadata',
          key: EventKey.uploadProgress,
        )),
        isFalse);
  });
}
