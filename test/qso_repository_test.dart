import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:qso_scribe_app/src/data/logbook_upload_repository.dart';
import 'package:qso_scribe_app/src/data/qso_repository.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('FMO relay metadata survives saving without radio fields', () async {
    final database = _QsoDatabase();
    final repository = QsoRepository(AppDatabase(database: database));
    final existing = (await repository.findQso('qso-1'))!;
    const missing = QsoField(value: '');
    final fmo = existing.copyWith(
      band: missing,
      frequency: missing,
      mode: missing,
      sentRst: missing,
      receivedRst: missing,
      fmoRelayUid: 'relay-42',
      fmoRelayName: 'Test relay',
    );
    expect(fmo.hasRequiredFields, isTrue);
    await repository.saveQso(fmo);
    final saved = (await repository.findQso('qso-1'))!;
    expect(saved.isFmo, isTrue);
    expect(saved.fmoRelayUid, 'relay-42');
    expect(saved.fmoRelayName, 'Test relay');
    expect(saved.frequency.value, isEmpty);
  });

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

  test('field review metadata survives a repository round trip', () async {
    final database = _QsoDatabase();
    final repository = QsoRepository(AppDatabase(database: database));
    final existing = await repository.findQso('qso-1');

    await repository.saveQso(
      existing!.copyWith(
        status: LogStatus.needsReview,
        callsign: const QsoField(
          value: 'K1ABC',
          confidence: 0.62,
          reviewed: true,
          sourceText: 'kilo one alpha bravo charlie',
        ),
        band: const QsoField(
          value: '20m',
          confidence: 0.7,
          userEdited: true,
          sourceText: 'twenty meters',
        ),
      ),
    );

    final reloaded = await repository.findQso('qso-1');
    expect(reloaded!.callsign.confidence, 0.62);
    expect(reloaded.callsign.reviewed, isTrue);
    expect(reloaded.callsign.sourceText, 'kilo one alpha bravo charlie');
    expect(reloaded.band.confidence, 0.7);
    expect(reloaded.band.userEdited, isTrue);
    expect(reloaded.band.sourceText, 'twenty meters');
  });

  test('legacy review state follows the persisted QSO status', () async {
    final database = _QsoDatabase();
    final repository = QsoRepository(AppDatabase(database: database));
    database.qsoRow['callsign_confidence'] = 0.6;
    database.qsoRow['field_metadata'] = null;

    for (final status in const [
      LogStatus.confirmed,
      LogStatus.exported,
      LogStatus.draft,
      LogStatus.needsReview,
    ]) {
      database.qsoRow['status'] = status.name;
      final qso = await repository.findQso('qso-1');
      final reviewed =
          status == LogStatus.confirmed || status == LogStatus.exported;

      expect(qso!.callsign.reviewed, reviewed, reason: status.name);
      expect(qso.hasUnreviewedFields, !reviewed, reason: status.name);
    }
  });

  test('confirmed QSO rejects unresolved low-confidence fields', () async {
    final database = _QsoDatabase();
    final repository = QsoRepository(AppDatabase(database: database));
    final existing = await repository.findQso('qso-1');

    await expectLater(
      repository.saveQso(
        existing!.copyWith(
          status: LogStatus.confirmed,
          callsign: const QsoField(value: 'K1ABC', confidence: 0.6),
        ),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'unreviewed_qso_fields',
        ),
      ),
    );
  });

  test(
    'transcript timeline survives repository round trip and audio deletion',
    () async {
      await _withRealRepository((repository) async {
        final id = await repository.saveQso(_draftWithTranscriptTimeline());

        var reloaded = await repository.findQso(id);
        expect(reloaded!.transcriptSegments, hasLength(2));
        expect(
          reloaded.transcriptSegments.first.speaker,
          TranscriptSpeaker.other,
        );
        expect(reloaded.transcriptSegments.first.startOffset, Duration.zero);
        expect(
          reloaded.transcriptSegments.first.endOffset,
          const Duration(seconds: 1),
        );
        expect(
          reloaded.transcriptSegments.last.startOffset,
          const Duration(seconds: 1),
        );
        expect(
          reloaded.transcriptSegments.last.endOffset,
          const Duration(milliseconds: 2500),
        );
        expect(
          reloaded.transcriptSegments.map((segment) => segment.audioPath),
          everyElement('/app/audio/qso.wav'),
        );

        await repository.clearAudioPath(id);
        reloaded = await repository.findQso(id);
        expect(reloaded!.audioPath, isNull);
        expect(reloaded.transcriptSegments, hasLength(2));
        expect(
          reloaded.transcriptSegments.map((segment) => segment.audioPath),
          everyElement(isNull),
        );
        expect(
          reloaded.transcriptSegments.last.endOffset,
          const Duration(milliseconds: 2500),
        );
      });
    },
  );

  test(
    'deleting and restoring raw transcript also deletes and restores segments',
    () async {
      await _withRealRepository((repository) async {
        final original = _draftWithTranscriptTimeline();
        final id = await repository.saveQso(original);

        await repository.setRawTranscript(id, null);
        var reloaded = await repository.findQso(id);
        expect(reloaded!.rawTranscript, isNull);
        expect(reloaded.transcriptSegments, isEmpty);
        expect(reloaded.audioPath, '/app/audio/qso.wav');

        await repository.setRawTranscript(
          id,
          original.rawTranscript,
          transcriptSegments: original.transcriptSegments,
        );
        reloaded = await repository.findQso(id);
        expect(reloaded!.rawTranscript, original.rawTranscript);
        expect(reloaded.transcriptSegments, hasLength(2));
        expect(reloaded.transcriptSegments.first.text, 'K1ABC five nine');
      });
    },
  );

  test('clear all raw transcripts removes segments without raw text', () async {
    await _withRealRepository((repository) async {
      final id = await repository.saveQso(
        _draftWithTranscriptTimeline().copyWith(rawTranscript: ''),
      );

      expect(await repository.countRawTranscripts(), 1);

      await repository.clearAllRawTranscripts();

      final reloaded = await repository.findQso(id);
      expect(reloaded!.transcriptSegments, isEmpty);
      expect(await repository.countRawTranscripts(), 0);
    });
  });

  test(
    'incomplete transcript timeline is rejected without replacing data',
    () async {
      await _withRealRepository((repository) async {
        final original = _draftWithTranscriptTimeline();
        final id = await repository.saveQso(original);
        final incomplete = original.copyWith(
          id: id,
          transcriptSegments: const [
            TranscriptSegment(
              speaker: TranscriptSpeaker.other,
              text: 'incomplete',
              isFinal: true,
              startOffset: Duration(seconds: 1),
            ),
          ],
        );

        await expectLater(
          repository.saveQso(incomplete),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'incomplete_transcript_segment_timeline',
            ),
          ),
        );

        final reloaded = await repository.findQso(id);
        expect(reloaded!.transcriptSegments, hasLength(2));
        expect(
          reloaded.transcriptSegments.last.endOffset,
          const Duration(milliseconds: 2500),
        );
      });
    },
  );
}

Future<void> _withRealRepository(
  Future<void> Function(QsoRepository repository) body,
) async {
  final tempDir = await Directory.systemTemp.createTemp(
    'qso_scribe_transcript_repository_',
  );
  final databasePath = p.join(tempDir.path, AppDatabase.databaseName);
  Database? opened;
  try {
    final appDatabase = AppDatabase(databasePath: databasePath);
    opened = await appDatabase.instance;
    await body(QsoRepository(appDatabase));
  } finally {
    await opened?.close();
    await tempDir.delete(recursive: true);
  }
}

QsoDraft _draftWithTranscriptTimeline() => QsoDraft(
  callsign: const QsoField(value: 'K1ABC'),
  dateTime: QsoField(value: DateTime(2026, 7, 22, 10)),
  band: const QsoField(value: '20m'),
  frequency: const QsoField(value: '14.250'),
  mode: const QsoField(value: 'SSB'),
  sentRst: const QsoField(value: '59'),
  receivedRst: const QsoField(value: '57'),
  status: LogStatus.needsReview,
  audioPath: '/app/audio/qso.wav',
  rawTranscript: 'K1ABC five nine\nBA1SELF roger',
  transcriptSegments: const [
    TranscriptSegment(
      speaker: TranscriptSpeaker.other,
      text: 'K1ABC five nine',
      isFinal: true,
      startOffset: Duration.zero,
      endOffset: Duration(seconds: 1),
    ),
    TranscriptSegment(
      speaker: TranscriptSpeaker.self,
      text: 'BA1SELF roger',
      isFinal: true,
      startOffset: Duration(seconds: 1),
      endOffset: Duration(milliseconds: 2500),
    ),
  ],
);

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
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
