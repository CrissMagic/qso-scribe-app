import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/services/qso_processing_service.dart';

void main() {
  const parser = QsoStructuredDraftParser();

  test('按字段读取结构化结果的来源片段', () {
    final draft = parser.parse({
      'callsign': 'K1ABC',
      'dateTime': null,
      'band': '20m',
      'frequency': '14.250',
      'mode': 'SSB',
      'sentRst': '59',
      'receivedRst': '57',
      'name': null,
      'qth': 'Boston',
      'notes': null,
      'rig': null,
      'antenna': null,
      'power': null,
      'confidence': {
        'callsign': 0.62,
        'band': 0.8,
        'frequency': 0.8,
        'mode': 0.9,
        'sentRst': 0.7,
        'receivedRst': 0.7,
        'qth': 0.65,
      },
      'sourceText': {
        'callsign': 'Kilo One Alpha Bravo Charlie',
        'qth': 'my QTH is Boston',
      },
    }, rawText: 'full transcript');

    expect(draft.callsign.sourceText, 'Kilo One Alpha Bravo Charlie');
    expect(draft.qth?.sourceText, 'my QTH is Boston');
    expect(draft.band.sourceText, isNull);
  });

  test('传入的录音开始时间不被 AI dateTime 覆盖', () {
    final startedAt = DateTime(2026, 7, 17, 9, 30);
    final draft = parser.parse(
      {
        'callsign': 'K1ABC',
        'dateTime': '1999-01-01T00:00:00Z',
        'band': '20m',
        'frequency': '14.250',
        'mode': 'SSB',
        'sentRst': '59',
        'receivedRst': '57',
        'confidence': {'dateTime': 0.1},
        'sourceText': {'dateTime': 'January first 1999'},
      },
      rawText: 'full transcript',
      dateTime: startedAt,
    );

    expect(draft.dateTime.value, startedAt);
    expect(draft.dateTime.confidence, 1);
    expect(draft.dateTime.sourceText, isNull);
  });

  test('sourceText 不是字段对象时明确拒绝', () {
    expect(
      () => parser.parse({
        'callsign': 'K1ABC',
        'dateTime': null,
        'band': '20m',
        'frequency': '14.250',
        'mode': 'SSB',
        'sentRst': '59',
        'receivedRst': '57',
        'confidence': <String, Object?>{},
        'sourceText': 'full transcript',
      }, rawText: 'full transcript'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'invalid_structuring_source_text',
        ),
      ),
    );
  });
}
