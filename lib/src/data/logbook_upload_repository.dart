import 'package:sqflite/sqflite.dart';

import '../domain/app_models.dart';
import 'adif_codec.dart';
import 'app_database.dart';
import 'model_codec.dart';
import 'qso_repository.dart';

class LogbookUploadRepository {
  LogbookUploadRepository(this._database);

  final AppDatabase _database;

  Future<LogbookUploadEntry?> findUpload({
    required String qsoId,
    required ExternalLogbook logbook,
  }) async {
    final db = await _database.instance;
    return _findUpload(db, qsoId: qsoId, logbook: logbook);
  }

  Future<LogbookUploadEntry?> _findUpload(
    DatabaseExecutor db, {
    required String qsoId,
    required ExternalLogbook logbook,
  }) async {
    final rows = await db.query(
      'logbook_uploads',
      where: 'qso_id = ? AND logbook = ?',
      whereArgs: [qsoId, encodeExternalLogbook(logbook)],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _decode(rows.single);
  }

  Future<bool> saveUpload({
    required String qsoId,
    required ExternalLogbook logbook,
    required LogbookUploadStatus status,
    String? remoteId,
    String? errorMessage,
    bool allowPendingRetry = false,
    QsoDraft? uploadedQso,
  }) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    return db.transaction((txn) async {
      final existing = await _findUpload(txn, qsoId: qsoId, logbook: logbook);
      final terminal =
          existing?.status == LogbookUploadStatus.succeeded ||
          existing?.status == LogbookUploadStatus.stale;
      final pendingRetryBlocked =
          existing?.status == LogbookUploadStatus.pending &&
          status == LogbookUploadStatus.pending &&
          !allowPendingRetry;
      if (terminal || pendingRetryBlocked) {
        return false;
      }
      var storedStatus = status;
      if (status == LogbookUploadStatus.succeeded) {
        if (uploadedQso == null) {
          throw ArgumentError.notNull('uploadedQso');
        }
        final qsoRows = await txn.query(
          'qso_logs',
          where: 'id = ?',
          whereArgs: [qsoId],
          limit: 1,
        );
        if (qsoRows.isEmpty) {
          throw StateError('uploaded_qso_not_found');
        }
        if (toAdifRecord(decodeQsoRow(qsoRows.single)) !=
            toAdifRecord(uploadedQso)) {
          storedStatus = LogbookUploadStatus.stale;
        }
      }
      await txn.insert('logbook_uploads', {
        'id': '$qsoId-${encodeExternalLogbook(logbook)}',
        'qso_id': qsoId,
        'logbook': encodeExternalLogbook(logbook),
        'status': encodeLogbookUploadStatus(storedStatus),
        'remote_id': remoteId,
        'error_message': errorMessage,
        'uploaded_at': status == LogbookUploadStatus.succeeded ? now : null,
        'created_at': now,
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  LogbookUploadEntry _decode(Map<String, Object?> row) {
    final uploadedAt = row['uploaded_at'] as String?;
    return LogbookUploadEntry(
      qsoId: row['qso_id'] as String,
      logbook: decodeExternalLogbook(row['logbook'] as String?),
      status: decodeLogbookUploadStatus(row['status'] as String?),
      remoteId: row['remote_id'] as String?,
      errorMessage: row['error_message'] as String?,
      uploadedAt: uploadedAt == null ? null : DateTime.parse(uploadedAt),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
