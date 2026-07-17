import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/services/heuristic_qso_structuring_service.dart';

void main() {
  const service = HeuristicQsoStructuringService();

  test('启发式提取的每个有值字段都保留来源片段', () {
    final draft = service.createDraftFromText(
      rawText: 'K1ABC on 14.250 SSB, reports 59 and 57',
    );

    expect(draft.callsign.sourceText, isNotEmpty);
    expect(draft.band.sourceText, isNotEmpty);
    expect(draft.frequency.sourceText, isNotEmpty);
    expect(draft.mode.sourceText, isNotEmpty);
    expect(draft.sentRst.sourceText, isNotEmpty);
    expect(draft.receivedRst.sourceText, isNotEmpty);
  });

  test('调用方提供的 QSO 开始时间不伪造转写来源', () {
    final startedAt = DateTime(2026, 7, 17, 9, 30);
    final draft = service.createDraftFromText(
      rawText: 'K1ABC on 20m SSB',
      dateTime: startedAt,
    );

    expect(draft.dateTime.value, startedAt);
    expect(draft.dateTime.confidence, 1);
    expect(draft.dateTime.sourceText, isNull);
  });
}
