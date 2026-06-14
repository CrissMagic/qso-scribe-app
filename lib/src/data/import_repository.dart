import 'package:sqflite/sqflite.dart';

import '../domain/app_models.dart';
import 'app_database.dart';
import 'model_codec.dart';

class ImportRepository {
  ImportRepository(this._database);

  final AppDatabase _database;

  Future<List<ImportJob>> listJobs() async {
    final db = await _database.instance;
    final rows = await db.query('import_jobs', orderBy: 'created_at DESC');
    return rows.map(_decodeJob).toList();
  }

  Future<ImportJob?> findJob(String id) async {
    final db = await _database.instance;
    final rows = await db.query(
      'import_jobs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _decodeJob(rows.single);
  }

  Future<ImportJob> createJob({
    required ImportSourceType sourceType,
    String? sourcePath,
    String? rawText,
  }) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc();
    final job = ImportJob(
      id: newLocalId('import'),
      sourceType: sourceType,
      sourcePath: sourcePath,
      rawText: rawText,
      status: ImportJobStatus.pending,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('import_jobs', _encodeJob(job));
    return job;
  }

  Future<void> updateJob({
    required String id,
    required ImportJobStatus status,
    String? generatedQsoId,
    String? errorMessage,
  }) async {
    final db = await _database.instance;
    await db.update(
      'import_jobs',
      {
        'status': encodeImportJobStatus(status),
        'generated_qso_id': generatedQsoId,
        'error_message': errorMessage,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllRawText() async {
    final db = await _database.instance;
    await db.update('import_jobs', {
      'raw_text': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: "raw_text IS NOT NULL AND raw_text != ''");
  }

  Future<void> clearRawText(String id) async {
    final db = await _database.instance;
    await db.update(
      'import_jobs',
      {
        'raw_text': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setRawText(String id, String? rawText) async {
    final db = await _database.instance;
    await db.update(
      'import_jobs',
      {
        'raw_text': rawText,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> countRawText() async {
    final db = await _database.instance;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM import_jobs WHERE raw_text IS NOT NULL AND raw_text != ''",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Map<String, Object?> _encodeJob(ImportJob job) {
    return {
      'id': job.id,
      'source_type': encodeImportSourceType(job.sourceType),
      'source_path': job.sourcePath,
      'raw_text': job.rawText,
      'status': encodeImportJobStatus(job.status),
      'generated_qso_id': job.generatedQsoId,
      'error_message': job.errorMessage,
      'created_at': job.createdAt.toUtc().toIso8601String(),
      'updated_at': job.updatedAt.toUtc().toIso8601String(),
    };
  }

  ImportJob _decodeJob(Map<String, Object?> row) {
    return ImportJob(
      id: row['id'] as String,
      sourceType: decodeImportSourceType(row['source_type'] as String?),
      sourcePath: row['source_path'] as String?,
      rawText: row['raw_text'] as String?,
      status: decodeImportJobStatus(row['status'] as String?),
      generatedQsoId: row['generated_qso_id'] as String?,
      errorMessage: row['error_message'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
    );
  }
}
