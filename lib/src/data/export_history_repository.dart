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
    required Map<String, DateTime> confirmedQsoVersions,
  }) async {
    final db = await _database.instance;
    final timestamp = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      await txn.insert('export_history', {
        'id': newLocalId('export'),
        'format': format,
        'file_path': filePath,
        'qso_count': qsoCount,
        'filter_summary': filterSummary,
        'created_at': timestamp,
      });

      final batch = txn.batch();
      for (final entry in confirmedQsoVersions.entries) {
        batch.update(
          'qso_logs',
          {
            'status': encodeLogStatus(LogStatus.exported),
            'updated_at': timestamp,
          },
          where: 'id = ? AND status = ? AND updated_at = ?',
          whereArgs: [
            entry.key,
            encodeLogStatus(LogStatus.confirmed),
            entry.value.toUtc().toIso8601String(),
          ],
        );
      }
      await batch.commit(noResult: true);
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
