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

  test('启发式解析忽略我方资料，只保留真实转写', () {
    final draft = service.createDraftFromText(
      rawText:
          '[我方资料] callsign=BA1SELF; qth=Beijing\n'
          '[待确认] K1ABC on 14.250 SSB',
    );

    expect(draft.callsign.value, 'K1ABC');
    expect(draft.rawTranscript, '[待确认] K1ABC on 14.250 SSB');
    expect(draft.callsign.sourceText, isNot(contains('BA1SELF')));
  });

  test('启发式解析跳过我方呼号并继续提取对方呼号', () {
    final draft = service.createDraftFromText(
      rawText: 'BA1SELF this is K1ABC on 14.250 SSB',
      ignoredCallsigns: const {'BA1SELF'},
    );

    expect(draft.callsign.value, 'K1ABC');
  });
}
