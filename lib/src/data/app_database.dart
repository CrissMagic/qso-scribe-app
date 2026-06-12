import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase({Database? database}) : _database = database;

  static const databaseName = 'qso_scribe.db';
  static const databaseVersion = 4;

  Database? _database;

  Future<Database> get instance async {
    final existing = _database;
    if (existing != null) {
      return existing;
    }

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, databaseName);
    final opened = await openDatabase(
      dbPath,
      version: databaseVersion,
      onCreate: _create,
      onUpgrade: _upgrade,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
    _database = opened;
    return opened;
  }

  static Future<void> _create(Database db, int version) async {
    await _createCoreTables(db);
    await _seedSettings(db);
  }

  static Future<void> _upgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await _migrateToV2(db);
    }
    if (oldVersion < 3) {
      await _migrateToV3(db);
    }
    if (oldVersion < 4) {
      await _migrateToV4(db);
    }
  }

  static Future<void> _createCoreTables(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS app_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS provider_profiles (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  base_url TEXT,
  api_key TEXT,
  user_configured INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS model_assignments (
  task TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  model_id TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(provider_id) REFERENCES provider_profiles(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS qso_logs (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  callsign TEXT NOT NULL,
  callsign_confidence REAL NOT NULL,
  callsign_user_edited INTEGER NOT NULL,
  callsign_source_text TEXT,
  qso_datetime TEXT,
  band TEXT NOT NULL,
  frequency TEXT NOT NULL,
  mode TEXT NOT NULL,
  sent_rst TEXT NOT NULL,
  received_rst TEXT NOT NULL,
  name TEXT,
  qth TEXT,
  qth_confidence REAL,
  notes TEXT,
  rig TEXT,
  antenna TEXT,
  audio_path TEXT,
  raw_transcript TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_status ON qso_logs(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_datetime ON qso_logs(qso_datetime)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_band ON qso_logs(band)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_mode ON qso_logs(mode)',
    );

    await db.execute('''
CREATE TABLE IF NOT EXISTS transcript_segments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  qso_id TEXT NOT NULL,
  speaker TEXT NOT NULL,
  text TEXT NOT NULL,
  is_final INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(qso_id) REFERENCES qso_logs(id) ON DELETE CASCADE
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS import_jobs (
  id TEXT PRIMARY KEY,
  source_type TEXT NOT NULL,
  source_path TEXT,
  raw_text TEXT,
  status TEXT NOT NULL,
  generated_qso_id TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(generated_qso_id) REFERENCES qso_logs(id) ON DELETE SET NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS export_history (
  id TEXT PRIMARY KEY,
  format TEXT NOT NULL,
  file_path TEXT NOT NULL,
  qso_count INTEGER NOT NULL,
  filter_summary TEXT NOT NULL,
  created_at TEXT NOT NULL
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS ai_model_options (
  id TEXT PRIMARY KEY,
  provider_id TEXT NOT NULL,
  name TEXT NOT NULL,
  capabilities TEXT NOT NULL,
  enabled INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(provider_id) REFERENCES provider_profiles(id) ON DELETE CASCADE
)
''');
  }

  static Future<void> _migrateToV2(Database db) async {
    await db.transaction((txn) async {
      await _migrateQsoLogsDateTimeNullable(txn);
      await _createCoreTables(txn);
    });
  }

  static Future<void> _migrateToV3(Database db) async {
    await db.transaction((txn) async {
      final columns = await txn.rawQuery(
        'PRAGMA table_info(provider_profiles)',
      );
      final hasUserConfigured = columns.any(
        (row) => row['name'] == 'user_configured',
      );
      if (!hasUserConfigured) {
        await txn.execute(
          'ALTER TABLE provider_profiles ADD COLUMN user_configured INTEGER NOT NULL DEFAULT 0',
        );
      }
      await txn.update(
        'provider_profiles',
        {'user_configured': 1},
        where:
            "id NOT IN (?, ?, ?, ?, ?, ?, ?) OR (api_key IS NOT NULL AND api_key != '')",
        whereArgs: [
          'openai',
          'local-openai-compatible',
          'openai-compatible',
          'deepseek',
          'qwen',
          'zhipu',
          'gemini',
        ],
      );
    });
  }

  static Future<void> _migrateToV4(Database db) async {
    await db.transaction((txn) async {
      await txn.delete(
        'provider_profiles',
        where:
            "user_configured = 0 AND id IN ('openai', 'local-openai-compatible', 'openai-compatible', 'deepseek', 'qwen', 'zhipu', 'gemini')",
      );
      await txn.delete(
        'ai_model_options',
        where:
            "id IN ('openai:gpt-realtime', 'openai:whisper-1', 'openai:gpt-4.1-mini', 'local-openai-compatible:whisper-large-v3', 'local-openai-compatible:local-chat', 'deepseek:deepseek-chat', 'qwen:qwen-plus', 'zhipu:glm-4-plus', 'gemini:gemini-pro', 'gemini:gemini-speech')",
      );
      await txn.delete(
        'model_assignments',
        where:
            'provider_id NOT IN (SELECT id FROM provider_profiles) OR model_id NOT IN (SELECT id FROM ai_model_options)',
      );
      await txn.delete(
        'ai_model_options',
        where: 'provider_id NOT IN (SELECT id FROM provider_profiles)',
      );
    });
  }

  static Future<void> _migrateQsoLogsDateTimeNullable(
    DatabaseExecutor db,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info(qso_logs)');
    Map<String, Object?>? dateTimeColumn;
    for (final row in columns) {
      if (row['name'] == 'qso_datetime') {
        dateTimeColumn = row;
        break;
      }
    }
    if (dateTimeColumn == null || dateTimeColumn['notnull'] != 1) {
      return;
    }

    await db.execute('ALTER TABLE qso_logs RENAME TO qso_logs_v1');
    await db.execute('''
CREATE TABLE qso_logs (
  id TEXT PRIMARY KEY,
  status TEXT NOT NULL,
  callsign TEXT NOT NULL,
  callsign_confidence REAL NOT NULL,
  callsign_user_edited INTEGER NOT NULL,
  callsign_source_text TEXT,
  qso_datetime TEXT,
  band TEXT NOT NULL,
  frequency TEXT NOT NULL,
  mode TEXT NOT NULL,
  sent_rst TEXT NOT NULL,
  received_rst TEXT NOT NULL,
  name TEXT,
  qth TEXT,
  qth_confidence REAL,
  notes TEXT,
  rig TEXT,
  antenna TEXT,
  audio_path TEXT,
  raw_transcript TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
    await db.execute('''
INSERT INTO qso_logs (
  id,
  status,
  callsign,
  callsign_confidence,
  callsign_user_edited,
  callsign_source_text,
  qso_datetime,
  band,
  frequency,
  mode,
  sent_rst,
  received_rst,
  name,
  qth,
  qth_confidence,
  notes,
  rig,
  antenna,
  audio_path,
  raw_transcript,
  created_at,
  updated_at
)
SELECT
  id,
  status,
  callsign,
  callsign_confidence,
  callsign_user_edited,
  callsign_source_text,
  qso_datetime,
  band,
  frequency,
  mode,
  sent_rst,
  received_rst,
  name,
  qth,
  qth_confidence,
  notes,
  rig,
  antenna,
  audio_path,
  raw_transcript,
  created_at,
  updated_at
FROM qso_logs_v1
''');
    await _rebuildTranscriptSegments(db);
    await _rebuildImportJobs(db);
    await db.execute('DROP TABLE qso_logs_v1');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_status ON qso_logs(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_datetime ON qso_logs(qso_datetime)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_band ON qso_logs(band)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_qso_logs_mode ON qso_logs(mode)',
    );
  }

  static Future<void> _rebuildTranscriptSegments(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'transcript_segments'",
    );
    if (tables.isEmpty) {
      return;
    }
    await db.execute(
      'ALTER TABLE transcript_segments RENAME TO transcript_segments_v1',
    );
    await db.execute('''
CREATE TABLE transcript_segments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  qso_id TEXT NOT NULL,
  speaker TEXT NOT NULL,
  text TEXT NOT NULL,
  is_final INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(qso_id) REFERENCES qso_logs(id) ON DELETE CASCADE
)
''');
    await db.execute('''
INSERT INTO transcript_segments (
  id,
  qso_id,
  speaker,
  text,
  is_final,
  created_at
)
SELECT
  id,
  qso_id,
  speaker,
  text,
  is_final,
  created_at
FROM transcript_segments_v1
''');
    await db.execute('DROP TABLE transcript_segments_v1');
  }

  static Future<void> _rebuildImportJobs(DatabaseExecutor db) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'import_jobs'",
    );
    if (tables.isEmpty) {
      return;
    }

    final columns = await db.rawQuery('PRAGMA table_info(import_jobs)');
    final hasGeneratedQsoId = columns.any(
      (row) => row['name'] == 'generated_qso_id',
    );
    final hasErrorMessage = columns.any(
      (row) => row['name'] == 'error_message',
    );

    await db.execute('ALTER TABLE import_jobs RENAME TO import_jobs_v1');
    await db.execute('''
CREATE TABLE import_jobs (
  id TEXT PRIMARY KEY,
  source_type TEXT NOT NULL,
  source_path TEXT,
  raw_text TEXT,
  status TEXT NOT NULL,
  generated_qso_id TEXT,
  error_message TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(generated_qso_id) REFERENCES qso_logs(id) ON DELETE SET NULL
)
''');
    await db.execute('''
INSERT INTO import_jobs (
  id,
  source_type,
  source_path,
  raw_text,
  status,
  generated_qso_id,
  error_message,
  created_at,
  updated_at
)
SELECT
  id,
  source_type,
  source_path,
  raw_text,
  status,
  ${hasGeneratedQsoId ? 'generated_qso_id' : 'NULL'},
  ${hasErrorMessage ? 'error_message' : 'NULL'},
  created_at,
  updated_at
FROM import_jobs_v1
''');
    await db.execute('DROP TABLE import_jobs_v1');
  }

  static Future<void> _seedSettings(DatabaseExecutor db) async {
    final defaults = <String, String>{
      'localeMode': 'system',
      'transcriptionMode': 'streaming',
      'failureHandling': 'alert',
      'audioRetentionPolicy': 'keep',
      'setupCompleted': 'false',
    };

    for (final entry in defaults.entries) {
      await db.insert('app_settings', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }
}
