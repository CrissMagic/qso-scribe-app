import 'package:sqflite/sqflite.dart';

import '../domain/app_models.dart';
import 'app_database.dart';
import 'model_codec.dart';

class QsoQuery {
  const QsoQuery({
    this.status,
    this.from,
    this.to,
    this.band,
    this.mode,
    this.search,
  });

  final LogStatus? status;
  final DateTime? from;
  final DateTime? to;
  final String? band;
  final String? mode;
  final String? search;
}

class QsoRepository {
  QsoRepository(this._database);

  final AppDatabase _database;

  Future<List<QsoDraft>> listQsos([QsoQuery query = const QsoQuery()]) async {
    final db = await _database.instance;
    final where = <String>[];
    final args = <Object?>[];

    if (query.status != null) {
      where.add('status = ?');
      args.add(encodeLogStatus(query.status!));
    }
    if (query.from != null) {
      where.add('qso_datetime >= ?');
      args.add(query.from!.toUtc().toIso8601String());
    }
    if (query.to != null) {
      where.add('qso_datetime <= ?');
      args.add(query.to!.toUtc().toIso8601String());
    }
    if (query.band != null && query.band!.trim().isNotEmpty) {
      where.add('band = ? COLLATE NOCASE');
      args.add(query.band!.trim());
    }
    if (query.mode != null && query.mode!.trim().isNotEmpty) {
      where.add('mode = ? COLLATE NOCASE');
      args.add(query.mode!.trim());
    }
    if (query.search != null && query.search!.trim().isNotEmpty) {
      where.add('(callsign LIKE ? OR notes LIKE ? OR qth LIKE ?)');
      final pattern = '%${query.search!.trim()}%';
      args.addAll([pattern, pattern, pattern]);
    }

    final rows = await db.query(
      'qso_logs',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'qso_datetime DESC',
    );

    return rows.map(_decodeQso).toList();
  }

  Future<QsoDraft?> findQso(String id) async {
    final db = await _database.instance;
    final rows = await db.query(
      'qso_logs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _decodeQso(rows.single);
  }

  Future<String> saveQso(QsoDraft qso) async {
    if ((qso.status == LogStatus.confirmed ||
            qso.status == LogStatus.exported) &&
        !qso.hasRequiredFields) {
      throw StateError('required_qso_fields_missing');
    }

    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = qso.id ?? newLocalId('qso');
    final row = _encodeQso(qso, id: id, timestamp: now);

    await db.insert(
      'qso_logs',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return id;
  }

  Future<void> updateStatus(String id, LogStatus status) async {
    final db = await _database.instance;
    await db.update(
      'qso_logs',
      {
        'status': encodeLogStatus(status),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAudioPath(String id) async {
    final db = await _database.instance;
    await db.update(
      'qso_logs',
      {
        'audio_path': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearRawTranscript(String id) async {
    final db = await _database.instance;
    await db.update(
      'qso_logs',
      {
        'raw_transcript': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAllAudioPaths() async {
    final db = await _database.instance;
    await db.update('qso_logs', {
      'audio_path': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'audio_path IS NOT NULL');
  }

  Future<void> clearAllRawTranscripts() async {
    final db = await _database.instance;
    await db.update('qso_logs', {
      'raw_transcript': null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: "raw_transcript IS NOT NULL AND raw_transcript != ''");
  }

  Future<int> countRetainedAudio() async {
    final db = await _database.instance;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM qso_logs WHERE audio_path IS NOT NULL',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> countRawTranscripts() async {
    final db = await _database.instance;
    final result = await db.rawQuery(
      "SELECT COUNT(*) AS count FROM qso_logs WHERE raw_transcript IS NOT NULL AND raw_transcript != ''",
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> appendTranscriptSegments(
    String qsoId,
    List<TranscriptSegment> segments,
  ) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      for (final segment in segments) {
        await txn.insert('transcript_segments', {
          'qso_id': qsoId,
          'speaker': segment.speaker,
          'text': segment.text,
          'is_final': encodeBool(segment.isFinal),
          'created_at': now,
        });
      }
    });
  }

  Future<List<TranscriptSegment>> listTranscriptSegments(String qsoId) async {
    final db = await _database.instance;
    final rows = await db.query(
      'transcript_segments',
      where: 'qso_id = ?',
      whereArgs: [qsoId],
      orderBy: 'id ASC',
    );
    return rows
        .map(
          (row) => TranscriptSegment(
            speaker: row['speaker'] as String,
            text: row['text'] as String,
            isFinal: decodeBool(row['is_final']),
          ),
        )
        .toList();
  }

  Map<String, Object?> _encodeQso(
    QsoDraft qso, {
    required String id,
    required String timestamp,
  }) {
    return {
      'id': id,
      'status': encodeLogStatus(qso.status),
      'callsign': qso.callsign.value.trim().toUpperCase(),
      'callsign_confidence': qso.callsign.confidence,
      'callsign_user_edited': encodeBool(qso.callsign.userEdited),
      'callsign_source_text': qso.callsign.sourceText,
      'qso_datetime': qso.dateTime.value?.toUtc().toIso8601String(),
      'band': qso.band.value.trim(),
      'frequency': qso.frequency.value.trim(),
      'mode': qso.mode.value.trim().toUpperCase(),
      'sent_rst': qso.sentRst.value.trim(),
      'received_rst': qso.receivedRst.value.trim(),
      'name': qso.name?.value.trim(),
      'qth': qso.qth?.value.trim(),
      'qth_confidence': qso.qth?.confidence,
      'notes': qso.notes?.value.trim(),
      'rig': qso.rig?.value.trim(),
      'antenna': qso.antenna?.value.trim(),
      'audio_path': qso.audioPath,
      'raw_transcript': qso.rawTranscript,
      'created_at': timestamp,
      'updated_at': timestamp,
    };
  }

  QsoDraft _decodeQso(Map<String, Object?> row) {
    final dateTimeText = row['qso_datetime'] as String?;
    final dateTime = dateTimeText == null
        ? null
        : DateTime.parse(dateTimeText).toLocal();
    return QsoDraft(
      id: row['id'] as String,
      status: decodeLogStatus(row['status'] as String?),
      callsign: QsoField(
        value: row['callsign'] as String,
        confidence: (row['callsign_confidence'] as num).toDouble(),
        userEdited: decodeBool(row['callsign_user_edited']),
        sourceText: row['callsign_source_text'] as String?,
      ),
      dateTime: QsoField(value: dateTime),
      band: QsoField(value: row['band'] as String),
      frequency: QsoField(value: row['frequency'] as String),
      mode: QsoField(value: row['mode'] as String),
      sentRst: QsoField(value: row['sent_rst'] as String),
      receivedRst: QsoField(value: row['received_rst'] as String),
      name: _optionalField(row['name'] as String?),
      qth: _optionalField(
        row['qth'] as String?,
        confidence: (row['qth_confidence'] as num?)?.toDouble(),
      ),
      notes: _optionalField(row['notes'] as String?),
      rig: _optionalField(row['rig'] as String?),
      antenna: _optionalField(row['antenna'] as String?),
      audioPath: row['audio_path'] as String?,
      rawTranscript: row['raw_transcript'] as String?,
    );
  }

  QsoField<String>? _optionalField(String? value, {double? confidence}) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return QsoField(value: value, confidence: confidence ?? 1);
  }
}
