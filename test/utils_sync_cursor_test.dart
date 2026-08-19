import 'package:file_vault_bb/utils/utils_sync_cursor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cursor advances through rows sharing a server timestamp', () {
    final cursor = SyncCursor(timestamp: 100, rowId: 7);

    cursor.advance(100, 8);

    expect(cursor.timestamp, 100);
    expect(cursor.rowId, 8);
  });

  test('cursor ignores rows that are not after the current tuple', () {
    final cursor = SyncCursor(timestamp: 100, rowId: 7);

    cursor.advance(99, 100);
    cursor.advance(100, 6);

    expect(cursor.timestamp, 100);
    expect(cursor.rowId, 7);
  });

  test('newer timestamp resets the row-id position', () {
    final cursor = SyncCursor(timestamp: 100, rowId: 99);

    cursor.advance(101, 2);

    expect(cursor.timestamp, 101);
    expect(cursor.rowId, 2);
  });
}
