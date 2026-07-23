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

  test('真实 SQLite 文件从 v8 升级到当前版本并保留原有 QSO', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'qso_scribe_v8_to_v10_',
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
          "SELECT name FROM pragma_table_info('qso_logs') WHERE name = ?",
          ['field_metadata'],
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

  test('v10 原始转写升级为单个待确认分段并增加时间轴列', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'qso_scribe_v10_to_v11_',
    );
    final databasePath = p.join(tempDir.path, AppDatabase.databaseName);
    Database? opened;
    try {
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 10,
          onCreate: (db, version) async {
            await db.execute('''
CREATE TABLE qso_logs (
  id TEXT PRIMARY KEY,
  raw_transcript TEXT,
  updated_at TEXT NOT NULL
)
''');
            await db.execute('''
CREATE TABLE transcript_segments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  qso_id TEXT NOT NULL,
  speaker TEXT NOT NULL,
  text TEXT NOT NULL,
  is_final INTEGER NOT NULL,
  created_at TEXT NOT NULL
)
''');
            await db.insert('qso_logs', {
              'id': 'legacy-qso',
              'raw_transcript': 'K1ABC five nine',
              'updated_at': '2026-07-22T08:00:00.000Z',
            });
          },
        ),
      );
      await legacy.close();

      final database = await AppDatabase(databasePath: databasePath).instance;
      opened = database;

      final columns = await database.rawQuery(
        "SELECT name FROM pragma_table_info('transcript_segments')",
      );
      expect(
        columns.map((row) => row['name']),
        containsAll(['start_offset_ms', 'end_offset_ms']),
      );
      expect(
        await database.query(
          'transcript_segments',
          columns: [
            'qso_id',
            'speaker',
            'text',
            'is_final',
            'start_offset_ms',
            'end_offset_ms',
          ],
        ),
        [
          {
            'qso_id': 'legacy-qso',
            'speaker': 'unknown',
            'text': 'K1ABC five nine',
            'is_final': 1,
            'start_offset_ms': null,
            'end_offset_ms': null,
          },
        ],
      );
    } finally {
      await opened?.close();
      await tempDir.delete(recursive: true);
    }
  });
}
