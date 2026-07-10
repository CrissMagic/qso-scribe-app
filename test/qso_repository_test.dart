import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:qso_scribe_app/src/data/logbook_upload_repository.dart';
import 'package:qso_scribe_app/src/data/qso_repository.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  test('editing a saved QSO updates in place and marks QRZ stale', () async {
    final database = _QsoDatabase();
    final qsoRepository = QsoRepository(AppDatabase(database: database));
    final uploadRepository = LogbookUploadRepository(
      AppDatabase(database: database),
    );
    final existing = await qsoRepository.findQso('qso-1');

    await qsoRepository.saveQso(
      existing!.copyWith(callsign: const QsoField(value: 'K1XYZ')),
    );

    final upload = await uploadRepository.findUpload(
      qsoId: 'qso-1',
      logbook: ExternalLogbook.qrz,
    );
    expect(database.qsoInsertCalls, 0);
    expect(database.qsoUpdateCalls, 1);
    expect(upload?.status.name, 'stale');
    expect(upload?.remoteId, 'remote-1');
  });

  test(
    'editing fields outside the QRZ ADIF payload keeps success current',
    () async {
      final database = _QsoDatabase();
      final qsoRepository = QsoRepository(AppDatabase(database: database));
      final uploadRepository = LogbookUploadRepository(
        AppDatabase(database: database),
      );
      final existing = await qsoRepository.findQso('qso-1');

      await qsoRepository.saveQso(
        existing!.copyWith(antenna: const QsoField(value: 'EFHW')),
      );

      final upload = await uploadRepository.findUpload(
        qsoId: 'qso-1',
        logbook: ExternalLogbook.qrz,
      );
      expect(database.qsoInsertCalls, 0);
      expect(database.qsoUpdateCalls, 1);
      expect(database.uploadUpdateCalls, 0);
      expect(upload?.status, LogbookUploadStatus.succeeded);
      expect(upload?.remoteId, 'remote-1');
    },
  );

  test('stale comparison uses the persisted ADIF representation', () async {
    final database = _QsoDatabase();
    final qsoRepository = QsoRepository(AppDatabase(database: database));
    final existing = await qsoRepository.findQso('qso-1');

    await qsoRepository.saveQso(
      existing!.copyWith(
        callsign: const QsoField(value: ' k1abc '),
        dateTime: QsoField(
          value: DateTime.parse('2026-07-10T08:00:00.500Z').toLocal(),
        ),
      ),
    );

    expect(database.uploadUpdateCalls, 0);
    expect(database.uploadRow['status'], LogbookUploadStatus.succeeded.name);
  });
}

class _QsoDatabase implements Database, Transaction {
  _QsoDatabase()
    : qsoRow = {
        'id': 'qso-1',
        'status': 'exported',
        'callsign': 'K1ABC',
        'callsign_confidence': 1.0,
        'callsign_user_edited': 0,
        'callsign_source_text': null,
        'qso_datetime': '2026-07-10T08:00:00.000Z',
        'band': '20m',
        'frequency': '14.250',
        'mode': 'SSB',
        'sent_rst': '59',
        'received_rst': '57',
        'name': null,
        'qth': null,
        'qth_confidence': null,
        'notes': null,
        'rig': null,
        'antenna': null,
        'power': null,
        'audio_path': null,
        'original_audio_deleted': 0,
        'raw_transcript': null,
        'created_at': '2026-07-10T08:00:00.000Z',
        'updated_at': '2026-07-10T08:00:00.000Z',
      },
      uploadRow = {
        'id': 'qso-1-qrz',
        'qso_id': 'qso-1',
        'logbook': 'qrz',
        'status': 'succeeded',
        'remote_id': 'remote-1',
        'error_message': null,
        'uploaded_at': '2026-07-10T08:05:00.000Z',
        'created_at': '2026-07-10T08:05:00.000Z',
        'updated_at': '2026-07-10T08:05:00.000Z',
      };

  Map<String, Object?> qsoRow;
  Map<String, Object?> uploadRow;
  int qsoInsertCalls = 0;
  int qsoUpdateCalls = 0;
  int uploadUpdateCalls = 0;

  @override
  Database get database => this;

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => action(this);

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    return switch (table) {
      'qso_logs' => [Map<String, Object?>.from(qsoRow)],
      'logbook_uploads' => [Map<String, Object?>.from(uploadRow)],
      _ => <Map<String, Object?>>[],
    };
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'qso_logs') {
      qsoInsertCalls += 1;
      qsoRow = Map<String, Object?>.from(values);
    }
    return 1;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    if (table == 'qso_logs') {
      qsoUpdateCalls += 1;
      qsoRow = {...qsoRow, ...values};
    } else if (table == 'logbook_uploads') {
      uploadUpdateCalls += 1;
      uploadRow = {...uploadRow, ...values};
    }
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
