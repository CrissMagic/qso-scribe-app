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
