import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:qso_scribe_app/src/data/logbook_upload_repository.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  for (final terminalStatus in [
    LogbookUploadStatus.succeeded,
    LogbookUploadStatus.stale,
  ]) {
    test('${terminalStatus.name} upload state rejects later writes', () async {
      final database = _UploadDatabase(_uploadRow(terminalStatus));
      final repository = LogbookUploadRepository(
        AppDatabase(database: database),
      );

      final savedAttempt = await repository.saveUpload(
        qsoId: 'qso-1',
        logbook: ExternalLogbook.qrz,
        status: LogbookUploadStatus.failed,
        errorMessage: 'duplicate',
      );

      final saved = await repository.findUpload(
        qsoId: 'qso-1',
        logbook: ExternalLogbook.qrz,
      );
      expect(savedAttempt, isFalse);
      expect(database.insertCalls, 0);
      expect(saved?.status, terminalStatus);
      expect(saved?.remoteId, 'remote-1');
      expect(saved?.errorMessage, isNull);
    });
  }

  test('pending upload retries only after explicit confirmation', () async {
    final database = _UploadDatabase(_uploadRow(LogbookUploadStatus.pending));
    final repository = LogbookUploadRepository(AppDatabase(database: database));

    final blocked = await repository.saveUpload(
      qsoId: 'qso-1',
      logbook: ExternalLogbook.qrz,
      status: LogbookUploadStatus.pending,
    );
    final confirmed = await repository.saveUpload(
      qsoId: 'qso-1',
      logbook: ExternalLogbook.qrz,
      status: LogbookUploadStatus.pending,
      allowPendingRetry: true,
    );

    expect(blocked, isFalse);
    expect(confirmed, isTrue);
    expect(database.insertCalls, 1);
  });

  for (final qsoChanged in [false, true]) {
    test(
      'successful upload becomes ${qsoChanged ? 'stale' : 'succeeded'} when finalizing',
      () async {
        final database = _UploadDatabase(
          _uploadRow(LogbookUploadStatus.pending),
          qsoRow: _qsoRow(qsoChanged ? 'K1XYZ' : 'K1ABC'),
        );
        final repository = LogbookUploadRepository(
          AppDatabase(database: database),
        );

        final savedAttempt = await repository.saveUpload(
          qsoId: 'qso-1',
          logbook: ExternalLogbook.qrz,
          status: LogbookUploadStatus.succeeded,
          remoteId: 'remote-2',
          uploadedQso: _qso('K1ABC'),
        );
        final saved = await repository.findUpload(
          qsoId: 'qso-1',
          logbook: ExternalLogbook.qrz,
        );

        expect(savedAttempt, isTrue);
        expect(
          saved?.status,
          qsoChanged
              ? LogbookUploadStatus.stale
              : LogbookUploadStatus.succeeded,
        );
        expect(saved?.remoteId, 'remote-2');
        expect(saved?.uploadedAt, isNotNull);
      },
    );
  }
}

class _UploadDatabase implements Database, Transaction {
  _UploadDatabase(this.row, {Map<String, Object?>? qsoRow})
    : qsoRow = qsoRow ?? _qsoRow('K1ABC');

  Map<String, Object?> row;
  final Map<String, Object?> qsoRow;
  int insertCalls = 0;

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
  }) async => [Map<String, Object?>.from(table == 'qso_logs' ? qsoRow : row)];

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    insertCalls += 1;
    row = Map<String, Object?>.from(values);
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _uploadRow(LogbookUploadStatus status) {
  final hasRemote =
      status == LogbookUploadStatus.succeeded ||
      status == LogbookUploadStatus.stale;
  return {
    'id': 'qso-1-qrz',
    'qso_id': 'qso-1',
    'logbook': 'qrz',
    'status': status.name,
    'remote_id': hasRemote ? 'remote-1' : null,
    'error_message': null,
    'uploaded_at': hasRemote ? '2026-07-10T08:00:00.000Z' : null,
    'created_at': '2026-07-10T08:00:00.000Z',
    'updated_at': '2026-07-10T08:00:00.000Z',
  };
}

Map<String, Object?> _qsoRow(String callsign) => {
  'id': 'qso-1',
  'status': 'confirmed',
  'callsign': callsign,
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
};

QsoDraft _qso(String callsign) => QsoDraft(
  id: 'qso-1',
  callsign: QsoField(value: callsign),
  dateTime: QsoField(value: DateTime.utc(2026, 7, 10, 8)),
  band: const QsoField(value: '20m'),
  frequency: const QsoField(value: '14.250'),
  mode: const QsoField(value: 'SSB'),
  sentRst: const QsoField(value: '59'),
  receivedRst: const QsoField(value: '57'),
  status: LogStatus.confirmed,
  updatedAt: DateTime.utc(2026, 7, 10, 8),
);
