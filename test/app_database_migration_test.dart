import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('真实 SQLite 文件从 v8 升级到 v9 并保留原有 QSO', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'qso_scribe_v8_to_v9_',
    );
    final databasePath = p.join(tempDir.path, AppDatabase.databaseName);
    Database? opened;
    try {
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, version) async {
            await db.execute('''
CREATE TABLE qso_logs (
  id TEXT PRIMARY KEY
)
''');
            await db.insert('qso_logs', {'id': 'legacy-qso'});
          },
        ),
      );
      await legacy.close();

      final database = await AppDatabase(databasePath: databasePath).instance;
      opened = database;

      expect(await database.getVersion(), AppDatabase.databaseVersion);
      expect(
        await database.query(
          'qso_logs',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: ['legacy-qso'],
        ),
        [
          {'id': 'legacy-qso'},
        ],
      );
      expect(
        await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          ['logbook_uploads'],
        ),
        isNotEmpty,
      );
      expect(
        await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
          ['idx_logbook_uploads_qso'],
        ),
        isNotEmpty,
      );
    } finally {
      await opened?.close();
      await tempDir.delete(recursive: true);
    }
  });
}
