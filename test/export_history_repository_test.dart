import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:qso_scribe_app/src/data/export_history_repository.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test('saveExport only updates snapshotted confirmed QSO versions', () async {
    final batch = _RecordingBatch();
    final transaction = _RecordingTransaction(batch);
    final repository = ExportHistoryRepository(
      AppDatabase(database: _RecordingDatabase(transaction)),
    );

    await repository.saveExport(
      format: 'adif',
      filePath: r'C:\exports\logbook.adi',
      qsoCount: 2,
      filterSummary: 'all',
      confirmedQsoVersions: {
        'qso-confirmed': DateTime.parse('2026-07-10T16:00:00+08:00'),
      },
    );

    expect(batch.updates, hasLength(1));
    expect(batch.updates.single.table, 'qso_logs');
    expect(
      batch.updates.single.where,
      'id = ? AND status = ? AND updated_at = ?',
    );
    expect(batch.updates.single.whereArgs, [
      'qso-confirmed',
      'confirmed',
      '2026-07-10T08:00:00.000Z',
    ]);
    expect(batch.committedNoResult, isTrue);
  });
}

class _RecordingDatabase implements Database {
  _RecordingDatabase(this.transactionValue);

  final Transaction transactionValue;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => action(transactionValue);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingTransaction implements Transaction {
  _RecordingTransaction(this.batchValue);

  final Batch batchValue;

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async => 1;

  @override
  Batch batch() => batchValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingBatch implements Batch {
  final updates = <({String table, String? where, List<Object?>? whereArgs})>[];
  bool? committedNoResult;

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    updates.add((table: table, where: where, whereArgs: whereArgs));
  }

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) async {
    committedNoResult = noResult;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
