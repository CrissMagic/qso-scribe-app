import '../domain/app_models.dart';
import 'app_database.dart';
import 'model_codec.dart';

class ExportHistoryRepository {
  ExportHistoryRepository(this._database);

  final AppDatabase _database;

  Future<List<ExportHistoryEntry>> listExports({int limit = 20}) async {
    final db = await _database.instance;
    final rows = await db.query(
      'export_history',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_decodeEntry).toList();
  }

  Future<void> saveExport({
    required String format,
    required String filePath,
    required int qsoCount,
    required String filterSummary,
  }) async {
    final db = await _database.instance;
    await db.insert('export_history', {
      'id': newLocalId('export'),
      'format': format,
      'file_path': filePath,
      'qso_count': qsoCount,
      'filter_summary': filterSummary,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  ExportHistoryEntry _decodeEntry(Map<String, Object?> row) {
    return ExportHistoryEntry(
      id: row['id'] as String,
      format: row['format'] as String,
      filePath: row['file_path'] as String,
      qsoCount: row['qso_count'] as int,
      filterSummary: row['filter_summary'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}
