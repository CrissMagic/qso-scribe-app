import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';

void main() {
  test('requires date time and either band or frequency', () {
    final base = QsoDraft(
      callsign: const QsoField(value: 'K1ABC'),
      dateTime: QsoField(value: DateTime(2026, 6, 12)),
      band: const QsoField(value: ''),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: '59'),
      status: LogStatus.needsReview,
    );

    expect(base.hasRequiredFields, isTrue);
    expect(
      base.copyWith(frequency: const QsoField(value: '')).hasRequiredFields,
      isFalse,
    );
    expect(
      base
          .copyWith(dateTime: const QsoField<DateTime?>(value: null))
          .hasRequiredFields,
      isFalse,
    );
  });

  test('can clear retained audio path and raw transcript', () {
    final draft = QsoDraft(
      callsign: const QsoField(value: 'K1ABC'),
      dateTime: QsoField(value: DateTime(2026, 6, 12)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: ''),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: '59'),
      status: LogStatus.needsReview,
      audioPath: '/app/audio/qso.pcm',
      rawTranscript: 'K1ABC five nine',
    );

    final cleared = draft.copyWith(
      clearAudioPath: true,
      clearRawTranscript: true,
    );

    expect(cleared.audioPath, isNull);
    expect(cleared.rawTranscript, isNull);
  });

  test('low-confidence fields require review until confirmed or edited', () {
    const uncertain = QsoField(value: 'K1ABC', confidence: 0.6);

    expect(uncertain.needsReview, isTrue);
    expect(uncertain.copyWith(reviewed: true).needsReview, isFalse);
    expect(uncertain.copyWith(userEdited: true).needsReview, isFalse);

    final draft = QsoDraft(
      callsign: uncertain,
      dateTime: QsoField(value: DateTime(2026, 7, 17)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: '57'),
      status: LogStatus.needsReview,
    );

    expect(draft.hasUnreviewedFields, isTrue);
    expect(
      draft
          .copyWith(callsign: uncertain.copyWith(reviewed: true))
          .hasUnreviewedFields,
      isFalse,
    );
  });

  test('空的选填字段和已满足的波段频率二选一不算未复核字段', () {
    final draft = QsoDraft(
      callsign: const QsoField(value: 'K1ABC', confidence: 0.8),
      dateTime: QsoField(value: DateTime(2026, 7, 17)),
      band: const QsoField(value: '20m', confidence: 0.8),
      frequency: const QsoField(value: '', confidence: 0.2),
      mode: const QsoField(value: 'SSB', confidence: 0.8),
      sentRst: const QsoField(value: '59', confidence: 0.8),
      receivedRst: const QsoField(value: '57', confidence: 0.8),
      status: LogStatus.needsReview,
    );

    expect(draft.hasRequiredFields, isTrue);
    expect(draft.hasUnreviewedFields, isFalse);
  });

  test('formats recognized transcript bubbles with speaker labels for AI', () {
    final text = formatTranscriptSegmentsForStructuring([
      const TranscriptSegment(
        speaker: TranscriptSpeaker.other,
        text: 'CQ CQ 这里是 VR2ABC',
        isFinal: true,
      ),
      const TranscriptSegment(
        speaker: TranscriptSpeaker.self,
        text: 'BI1XYZ 回答你，信号五九',
        isFinal: true,
      ),
      const TranscriptSegment(
        speaker: TranscriptSpeaker.other,
        text: '',
        isFinal: true,
        errorMessage: 'transcription_failed',
      ),
    ]);

    expect(text, '[对方] CQ CQ 这里是 VR2ABC\n[我方] BI1XYZ 回答你，信号五九');
  });
}
