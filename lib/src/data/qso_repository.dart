import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/app_models.dart';
import 'adif_codec.dart';
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

    final segmentsByQso = await _loadTranscriptSegments(db, rows);
    return [
      for (final row in rows)
        decodeQsoRow(
          row,
          transcriptSegments: segmentsByQso[row['id'] as String] ?? const [],
        ),
    ];
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
    final segmentsByQso = await _loadTranscriptSegments(db, rows);
    return decodeQsoRow(
      rows.single,
      transcriptSegments:
          segmentsByQso[rows.single['id'] as String] ?? const [],
    );
  }

  Future<String> saveQso(QsoDraft qso) async {
    if ((qso.status == LogStatus.confirmed ||
            qso.status == LogStatus.exported) &&
        !qso.hasRequiredFields) {
      throw StateError('required_qso_fields_missing');
    }
    if ((qso.status == LogStatus.confirmed ||
            qso.status == LogStatus.exported) &&
        qso.hasUnreviewedFields) {
      throw StateError('unreviewed_qso_fields');
    }

    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = qso.id ?? newLocalId('qso');
    await db.transaction((txn) async {
      if (qso.id == null) {
        await txn.insert('qso_logs', _encodeQso(qso, id: id, timestamp: now));
        await _replaceTranscriptSegments(
          txn,
          qsoId: id,
          segments: qso.transcriptSegments,
          timestamp: now,
        );
        return;
      }

      final rows = await txn.query(
        'qso_logs',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('qso_logs', _encodeQso(qso, id: id, timestamp: now));
        await _replaceTranscriptSegments(
          txn,
          qsoId: id,
          segments: qso.transcriptSegments,
          timestamp: now,
        );
        return;
      }

      final existing = decodeQsoRow(rows.single);
      final encoded = _encodeQso(
        qso,
        id: id,
        timestamp: now,
        createdAt: rows.single['created_at'] as String,
      );
      await txn.update('qso_logs', encoded, where: 'id = ?', whereArgs: [id]);
      await _replaceTranscriptSegments(
        txn,
        qsoId: id,
        segments: qso.transcriptSegments,
        timestamp: now,
      );
      if (toAdifRecord(existing) != toAdifRecord(decodeQsoRow(encoded))) {
        await txn.update(
          'logbook_uploads',
          {
            'status': encodeLogbookUploadStatus(LogbookUploadStatus.stale),
            'updated_at': now,
          },
          where: 'qso_id = ? AND status = ?',
          whereArgs: [
            id,
            encodeLogbookUploadStatus(LogbookUploadStatus.succeeded),
          ],
        );
      }
    });
    return id;
  }

  Future<void> clearAudioPath(String id) async {
    final db = await _database.instance;
    await db.update(
      'qso_logs',
      {
        'audio_path': null,
        'original_audio_deleted': encodeBool(true),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> setAudioPath(String id, String path) async {
    final db = await _database.instance;
    await db.update(
      'qso_logs',
      {
        'audio_path': path,
        'original_audio_deleted': encodeBool(false),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearRawTranscript(String id) async {
    await setRawTranscript(id, null);
  }

  Future<void> setRawTranscript(
    String id,
    String? rawTranscript, {
    List<TranscriptSegment>? transcriptSegments,
  }) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final updated = await txn.update(
        'qso_logs',
        {'raw_transcript': rawTranscript, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (updated == 0) {
        return;
      }
      if (rawTranscript == null) {
        await txn.delete(
          'transcript_segments',
          where: 'qso_id = ?',
          whereArgs: [id],
        );
      } else if (transcriptSegments != null) {
        await _replaceTranscriptSegments(
          txn,
          qsoId: id,
          segments: transcriptSegments,
          timestamp: now,
        );
      }
    });
  }

  Future<void> clearAllAudioPaths() async {
    final db = await _database.instance;
    await db.update('qso_logs', {
      'audio_path': null,
      'original_audio_deleted': encodeBool(true),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, where: 'audio_path IS NOT NULL');
  }

  Future<void> clearAllRawTranscripts() async {
    final db = await _database.instance;
    const where = "raw_transcript IS NOT NULL AND raw_transcript != ''";
    await db.transaction((txn) async {
      await txn.delete('transcript_segments');
      await txn.update('qso_logs', {
        'raw_transcript': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, where: where);
    });
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
    final result = await db.rawQuery('''
SELECT COUNT(*) AS count
FROM qso_logs q
WHERE (q.raw_transcript IS NOT NULL AND q.raw_transcript != '')
   OR EXISTS (
     SELECT 1 FROM transcript_segments segment WHERE segment.qso_id = q.id
   )
''');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<Map<String, List<TranscriptSegment>>> _loadTranscriptSegments(
    DatabaseExecutor db,
    List<Map<String, Object?>> qsoRows,
  ) async {
    if (qsoRows.isEmpty) {
      return const {};
    }
    final audioPathByQso = <String, String?>{
      for (final row in qsoRows)
        row['id'] as String: row['audio_path'] as String?,
    };
    final qsoIds = audioPathByQso.keys.toList(growable: false);
    final result = <String, List<TranscriptSegment>>{};
    const batchSize = 500;
    for (var start = 0; start < qsoIds.length; start += batchSize) {
      final end = start + batchSize < qsoIds.length
          ? start + batchSize
          : qsoIds.length;
      final batch = qsoIds.sublist(start, end);
      final placeholders = List.filled(batch.length, '?').join(', ');
      final rows = await db.query(
        'transcript_segments',
        where: 'qso_id IN ($placeholders)',
        whereArgs: batch,
        orderBy: 'qso_id ASC, id ASC',
      );
      for (final row in rows) {
        final qsoId = row['qso_id'] as String;
        (result[qsoId] ??= []).add(
          _decodeTranscriptSegment(row, audioPath: audioPathByQso[qsoId]),
        );
      }
    }
    return result;
  }

  Future<void> _replaceTranscriptSegments(
    DatabaseExecutor db, {
    required String qsoId,
    required List<TranscriptSegment> segments,
    required String timestamp,
  }) async {
    for (final segment in segments) {
      final startOffset = segment.startOffset;
      final endOffset = segment.endOffset;
      if ((startOffset == null) != (endOffset == null)) {
        throw StateError('incomplete_transcript_segment_timeline');
      }
      if (startOffset?.isNegative == true ||
          endOffset?.isNegative == true ||
          (startOffset != null &&
              endOffset != null &&
              endOffset < startOffset)) {
        throw StateError('invalid_transcript_segment_timeline');
      }
    }
    await db.delete(
      'transcript_segments',
      where: 'qso_id = ?',
      whereArgs: [qsoId],
    );
    for (final segment in segments) {
      final startOffset = segment.startOffset;
      final endOffset = segment.endOffset;
      await db.insert('transcript_segments', {
        'qso_id': qsoId,
        'speaker': segment.speaker.name,
        'text': segment.text,
        'is_final': encodeBool(segment.isFinal),
        'start_offset_ms': startOffset?.inMilliseconds,
        'end_offset_ms': endOffset?.inMilliseconds,
        'created_at': timestamp,
      });
    }
  }

  Map<String, Object?> _encodeQso(
    QsoDraft qso, {
    required String id,
    required String timestamp,
    String? createdAt,
  }) {
    return {
      'id': id,
      'status': encodeLogStatus(qso.status),
      'callsign': qso.callsign.value.trim().toUpperCase(),
      'callsign_confidence': qso.callsign.confidence,
      'callsign_user_edited': encodeBool(qso.callsign.userEdited),
      'callsign_source_text': qso.callsign.sourceText,
      'qso_datetime': qso.dateTime.value?.toUtc().toIso8601String(),
      'fmo_relay_uid': qso.fmoRelayUid,
      'fmo_relay_name': qso.fmoRelayName,
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
      'power': qso.power?.value.trim(),
      'audio_path': qso.audioPath,
      'original_audio_deleted': encodeBool(qso.originalAudioDeleted),
      'raw_transcript': qso.rawTranscript,
      'field_metadata': jsonEncode({
        'callsign': _encodeFieldMetadata(qso.callsign),
        'dateTime': _encodeFieldMetadata(qso.dateTime),
        'band': _encodeFieldMetadata(qso.band),
        'frequency': _encodeFieldMetadata(qso.frequency),
        'mode': _encodeFieldMetadata(qso.mode),
        'sentRst': _encodeFieldMetadata(qso.sentRst),
        'receivedRst': _encodeFieldMetadata(qso.receivedRst),
        if (qso.name != null) 'name': _encodeFieldMetadata(qso.name!),
        if (qso.qth != null) 'qth': _encodeFieldMetadata(qso.qth!),
        if (qso.notes != null) 'notes': _encodeFieldMetadata(qso.notes!),
        if (qso.rig != null) 'rig': _encodeFieldMetadata(qso.rig!),
        if (qso.antenna != null) 'antenna': _encodeFieldMetadata(qso.antenna!),
        if (qso.power != null) 'power': _encodeFieldMetadata(qso.power!),
      }),
      'created_at': createdAt ?? timestamp,
      'updated_at': timestamp,
    };
  }
}

QsoDraft decodeQsoRow(
  Map<String, Object?> row, {
  List<TranscriptSegment> transcriptSegments = const [],
}) {
  final status = decodeLogStatus(row['status'] as String?);
  final metadata = _decodeFieldMetadata(row['field_metadata'] as String?);
  final legacyReviewed =
      metadata == null &&
      (status == LogStatus.confirmed || status == LogStatus.exported);
  final dateTimeText = row['qso_datetime'] as String?;
  final dateTime = dateTimeText == null
      ? null
      : DateTime.parse(dateTimeText).toLocal();
  return QsoDraft(
    id: row['id'] as String,
    status: status,
    fmoRelayUid: row['fmo_relay_uid'] as String?,
    fmoRelayName: row['fmo_relay_name'] as String?,
    callsign: _decodeQsoField(
      value: row['callsign'] as String,
      metadata: _metadataFor(metadata, 'callsign'),
      fallbackConfidence: (row['callsign_confidence'] as num).toDouble(),
      fallbackUserEdited: decodeBool(row['callsign_user_edited']),
      fallbackReviewed: legacyReviewed,
      fallbackSourceText: row['callsign_source_text'] as String?,
    ),
    dateTime: _decodeQsoField(
      value: dateTime,
      metadata: _metadataFor(metadata, 'dateTime'),
      fallbackReviewed: legacyReviewed,
    ),
    band: _decodeQsoField(
      value: row['band'] as String,
      metadata: _metadataFor(metadata, 'band'),
      fallbackReviewed: legacyReviewed,
    ),
    frequency: _decodeQsoField(
      value: row['frequency'] as String,
      metadata: _metadataFor(metadata, 'frequency'),
      fallbackReviewed: legacyReviewed,
    ),
    mode: _decodeQsoField(
      value: row['mode'] as String,
      metadata: _metadataFor(metadata, 'mode'),
      fallbackReviewed: legacyReviewed,
    ),
    sentRst: _decodeQsoField(
      value: row['sent_rst'] as String,
      metadata: _metadataFor(metadata, 'sentRst'),
      fallbackReviewed: legacyReviewed,
    ),
    receivedRst: _decodeQsoField(
      value: row['received_rst'] as String,
      metadata: _metadataFor(metadata, 'receivedRst'),
      fallbackReviewed: legacyReviewed,
    ),
    name: _optionalQsoField(
      row['name'] as String?,
      metadata: _metadataFor(metadata, 'name'),
      fallbackReviewed: legacyReviewed,
    ),
    qth: _optionalQsoField(
      row['qth'] as String?,
      metadata: _metadataFor(metadata, 'qth'),
      fallbackConfidence: (row['qth_confidence'] as num?)?.toDouble(),
      fallbackReviewed: legacyReviewed,
    ),
    notes: _optionalQsoField(
      row['notes'] as String?,
      metadata: _metadataFor(metadata, 'notes'),
      fallbackReviewed: legacyReviewed,
    ),
    rig: _optionalQsoField(
      row['rig'] as String?,
      metadata: _metadataFor(metadata, 'rig'),
      fallbackReviewed: legacyReviewed,
    ),
    antenna: _optionalQsoField(
      row['antenna'] as String?,
      metadata: _metadataFor(metadata, 'antenna'),
      fallbackReviewed: legacyReviewed,
    ),
    power: _optionalQsoField(
      row['power'] as String?,
      metadata: _metadataFor(metadata, 'power'),
      fallbackReviewed: legacyReviewed,
    ),
    audioPath: row['audio_path'] as String?,
    originalAudioDeleted: decodeBool(row['original_audio_deleted']),
    rawTranscript: row['raw_transcript'] as String?,
    transcriptSegments: transcriptSegments,
    updatedAt: DateTime.parse(row['updated_at'] as String).toUtc(),
  );
}

TranscriptSegment _decodeTranscriptSegment(
  Map<String, Object?> row, {
  required String? audioPath,
}) {
  final speakerName = row['speaker'] as String?;
  TranscriptSpeaker? speaker;
  for (final candidate in TranscriptSpeaker.values) {
    if (candidate.name == speakerName) {
      speaker = candidate;
      break;
    }
  }
  if (speaker == null) {
    throw const FormatException('invalid_transcript_segment_speaker');
  }

  final startMs = (row['start_offset_ms'] as num?)?.toInt();
  final endMs = (row['end_offset_ms'] as num?)?.toInt();
  if ((startMs == null) != (endMs == null)) {
    throw const FormatException('incomplete_transcript_segment_timeline');
  }
  if ((startMs != null && startMs < 0) ||
      (endMs != null && endMs < 0) ||
      (startMs != null && endMs != null && endMs < startMs)) {
    throw const FormatException('invalid_transcript_segment_timeline');
  }
  final startOffset = startMs == null ? null : Duration(milliseconds: startMs);
  final endOffset = endMs == null ? null : Duration(milliseconds: endMs);
  return TranscriptSegment(
    id: row['id'].toString(),
    speaker: speaker,
    text: row['text'] as String,
    isFinal: decodeBool(row['is_final']),
    audioPath: audioPath,
    duration: startOffset == null || endOffset == null
        ? null
        : endOffset - startOffset,
    startOffset: startOffset,
    endOffset: endOffset,
  );
}

Map<String, Object?> _encodeFieldMetadata<T>(QsoField<T> field) => {
  'confidence': field.confidence,
  'userEdited': field.userEdited,
  'reviewed': field.reviewed,
  'sourceText': field.sourceText,
};

Map<String, Object?>? _decodeFieldMetadata(String? value) {
  if (value == null) {
    return null;
  }
  final decoded = jsonDecode(value);
  if (decoded is! Map) {
    throw const FormatException('invalid_qso_field_metadata');
  }
  return Map<String, Object?>.from(decoded);
}

Map<String, Object?>? _metadataFor(Map<String, Object?>? metadata, String key) {
  final value = metadata?[key];
  if (value == null) {
    return null;
  }
  if (value is! Map) {
    throw const FormatException('invalid_qso_field_metadata');
  }
  return Map<String, Object?>.from(value);
}

QsoField<T> _decodeQsoField<T>({
  required T value,
  Map<String, Object?>? metadata,
  double fallbackConfidence = 1,
  bool fallbackUserEdited = false,
  bool fallbackReviewed = false,
  String? fallbackSourceText,
}) {
  return QsoField<T>(
    value: value,
    confidence:
        (metadata?['confidence'] as num?)?.toDouble() ?? fallbackConfidence,
    userEdited: metadata == null
        ? fallbackUserEdited
        : decodeBool(metadata['userEdited']),
    reviewed: metadata == null
        ? fallbackReviewed
        : decodeBool(metadata['reviewed']),
    sourceText: metadata == null
        ? fallbackSourceText
        : metadata['sourceText'] as String?,
  );
}

QsoField<String>? _optionalQsoField(
  String? value, {
  Map<String, Object?>? metadata,
  double? fallbackConfidence,
  bool fallbackReviewed = false,
}) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return _decodeQsoField(
    value: value,
    metadata: metadata,
    fallbackConfidence: fallbackConfidence ?? 1,
    fallbackReviewed: fallbackReviewed,
  );
}
