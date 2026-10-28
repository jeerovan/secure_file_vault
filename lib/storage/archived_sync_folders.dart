import 'dart:convert';

import 'package:path/path.dart' as p;

import '../models/model_item.dart';
import '../models/model_state.dart';
import 'storage_sqlite.dart';

/// Explicit Archive is a source-path exclusion, distinct from an item that a
/// scan temporarily cannot find. It survives a changed/missing source subtree.
class ArchivedSyncFolders {
  static String _key(String id) => 'archived_sync_folder:$id';

  static Future<void> mark(ModelItem folder, ModelItem root) async {
    if (folder.id == root.id) return;
    final rows = await ModelItem.getPathRowsForItem(folder.id);
    final index = rows.indexWhere((row) => row['id'] == root.id);
    if (index < 0) throw StateError('Archive root changed');
    final names =
        rows.skip(index + 1).map((row) => row['name'] as String).toList();
    await ModelState.set(_key(folder.id),
        jsonEncode({'root': root.id, 'item': folder.id, 'names': names}));
  }

  static Future<void> clear(String id) => ModelState.delete(_key(id));

  static Future<ArchivedFolderExclusions> load(String rootId) async {
    final db = await StorageSqlite.instance.executor;
    final rows = await db.query('states',
        where: 'id GLOB ?',
        whereArgs: ['archived_sync_folder:*'],
        orderBy: 'id');
    final records = <Map<String, dynamic>>[];
    for (final row in rows) {
      final value = jsonDecode(row['value'] as String) as Map<String, dynamic>;
      if (value['root'] != rootId) continue;
      final item = await ModelItem.get(value['item'] as String);
      // A legacy Restore may only clear archived_at. A permanently removed
      // backup keeps its path excluded rather than silently re-uploading it.
      if (item != null && item.archivedAt == 0) continue;
      records.add(value);
    }
    return ArchivedFolderExclusions(records);
  }
}

class ArchivedFolderExclusions {
  ArchivedFolderExclusions(this._records);
  final List<Map<String, dynamic>> _records;
  String get signature => jsonEncode(_records);

  Set<String> paths(String rootPath) => _records.map((record) {
        final names = List<String>.from(record['names'] as List);
        if (names.isEmpty ||
            names.any((name) =>
                name.isEmpty ||
                name == '.' ||
                name == '..' ||
                name.contains('/') ||
                name.contains('\\') ||
                name.contains('\u0000'))) {
          throw StateError('Invalid archived folder path');
        }
        return p.normalize(p.joinAll([rootPath, ...names]));
      }).toSet();

  Future<void> retainScanState() async {
    final db = await StorageSqlite.instance.executor;
    for (final record in _records) {
      // Mark without ModelItem.setScanState, which intentionally unarchives
      // ordinary rediscovered items. Excluded rows must not enter move matching.
      await db.rawUpdate('''
        WITH RECURSIVE subtree(id) AS (
          SELECT id FROM items WHERE id = ?
          UNION SELECT items.id FROM items JOIN subtree ON items.parent_id = subtree.id
        ) UPDATE items SET scan_state = 1 WHERE id IN (SELECT id FROM subtree)
      ''', [record['item']]);
    }
  }
}
