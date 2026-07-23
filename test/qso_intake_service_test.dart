import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:qso_scribe_app/src/services/qso_artifact_service.dart';
import 'package:qso_scribe_app/src/services/qso_intake_service.dart';
import 'package:qso_scribe_app/src/services/qso_processing_service.dart';

void main() {
  test('text structuring failure keeps transcript for review', () async {
    final service = _service(
      createDraftFromText:
          (rawText, {DateTime? dateTime, String? audioPath}) async {
            throw StateError('structuring_failed');
          },
    );

    final startedAt = DateTime(2026, 7, 6, 9, 30);
    final draft = await service.reviewDraftFromText(
      'CQ CQ this is K1ABC',
      dateTime: startedAt,
      audioPath: '/app/audio/qso.wav',
    );

    expect(draft.status, LogStatus.needsReview);
    expect(draft.dateTime.value, startedAt);
    expect(draft.rawTranscript, 'CQ CQ this is K1ABC');
    expect(draft.audioPath, '/app/audio/qso.wav');
    expect(draft.transcriptSegments, hasLength(1));
    expect(draft.transcriptSegments.single.speaker, TranscriptSpeaker.unknown);
    expect(draft.originalAudioDeleted, isFalse);
    expect(draft.errorMessage, contains('structuring_failed'));
  });

  test(
    'deleteAfterRecognition removes original audio from successful draft',
    () async {
      final deleted = <String>[];
      final service = _service(
        settings: const AppSettings.defaults().copyWith(
          audioRetentionPolicy: AudioRetentionPolicy.deleteAfterRecognition,
        ),
        artifactService: _FakeArtifactService(deleted),
        createDraftFromAudio:
            ({required String audioPath, DateTime? qsoStartedAt}) async =>
                _draft(
                  audioPath: audioPath,
                  dateTime: qsoStartedAt,
                  rawTranscript: 'K1ABC five nine',
                ),
      );

      final startedAt = DateTime(2026, 7, 6, 10);
      final draft = await service.reviewDraftFromAudio(
        audioPath: '/app/audio/qso.wav',
        startedAt: startedAt,
      );

      expect(deleted, ['/app/audio/qso.wav']);
      expect(draft.audioPath, isNull);
      expect(draft.originalAudioDeleted, isTrue);
      expect(draft.rawTranscript, 'K1ABC five nine');
      expect(draft.transcriptSegments, hasLength(1));
      expect(draft.transcriptSegments.single.audioPath, isNull);
    },
  );

  test('text structuring preserves deleted original audio marker', () async {
    final service = _service();

    final draft = await service.reviewDraftFromText(
      'K1ABC five nine',
      originalAudioDeleted: true,
    );

    expect(draft.audioPath, isNull);
    expect(draft.originalAudioDeleted, isTrue);
  });

  test(
    'audio structuring failure becomes needsReview when transcript exists',
    () async {
      final deleted = <String>[];
      final service = _service(
        settings: const AppSettings.defaults().copyWith(
          audioRetentionPolicy: AudioRetentionPolicy.deleteAfterRecognition,
        ),
        artifactService: _FakeArtifactService(deleted),
        createDraftFromAudio:
            ({required String audioPath, DateTime? qsoStartedAt}) async {
              throw const QsoStructuringException(
                message: 'json_failed',
                rawTranscript: 'K1ABC five nine',
              );
            },
      );

      final draft = await service.reviewDraftFromAudio(
        audioPath: '/app/audio/qso.wav',
        startedAt: DateTime(2026, 7, 6, 10),
      );

      expect(draft.status, LogStatus.needsReview);
      expect(draft.rawTranscript, 'K1ABC five nine');
      expect(draft.audioPath, isNull);
      expect(draft.originalAudioDeleted, isTrue);
      expect(draft.transcriptSegments, hasLength(1));
      expect(
        draft.transcriptSegments.single.speaker,
        TranscriptSpeaker.unknown,
      );
      expect(draft.transcriptSegments.single.audioPath, isNull);
      expect(deleted, ['/app/audio/qso.wav']);
    },
  );

  test('audio transcription failure remains a visible failure', () async {
    final service = _service(
      createDraftFromAudio:
          ({required String audioPath, DateTime? qsoStartedAt}) async {
            throw StateError('no_transcription_model_assigned');
          },
    );

    expect(
      service.reviewDraftFromAudio(audioPath: '/app/audio/qso.wav'),
      throwsA(isA<StateError>()),
    );
  });

  test('after-QSO only drops explicitly self QTH', () async {
    var callCount = 0;
    final service = _service(
      settings: const AppSettings.defaults().copyWith(
        callsign: 'BA1SELF',
        qth: 'Beijing',
      ),
      createDraftFromAudio:
          ({required String audioPath, DateTime? qsoStartedAt}) async {
            callCount += 1;
            return _draft(
              audioPath: audioPath,
              dateTime: qsoStartedAt,
            ).copyWith(
              callsign: const QsoField(value: 'BA1SELF'),
              qth: QsoField(
                value: 'Beijing',
                sourceText: switch (callCount) {
                  1 => 'QTH Beijing',
                  2 => '[我方] QTH Beijing',
                  _ => '[对方] QTH Beijing',
                },
              ),
            );
          },
    );

    final uncertain = await service.reviewDraftFromAudio(
      audioPath: '/app/audio/first.wav',
    );
    final ownStation = await service.reviewDraftFromAudio(
      audioPath: '/app/audio/second.wav',
    );
    final explicitOther = await service.reviewDraftFromAudio(
      audioPath: '/app/audio/third.wav',
    );

    expect(uncertain.qth?.value, 'Beijing');
    expect(uncertain.qth?.needsReview, isTrue);
    expect(ownStation.callsign.value, isEmpty);
    expect(ownStation.qth, isNull);
    expect(explicitOther.qth?.value, 'Beijing');
  });
}

QsoIntakeService _service({
  AppSettings settings = const AppSettings.defaults(),
  TextDraftFactory? createDraftFromText,
  AudioDraftFactory? createDraftFromAudio,
  QsoArtifactService? artifactService,
}) {
  return QsoIntakeService(
    createDraftFromText:
        createDraftFromText ??
        (rawText, {DateTime? dateTime, String? audioPath}) async => _draft(
          audioPath: audioPath,
          dateTime: dateTime,
          rawTranscript: rawText,
        ),
    createDraftFromAudio:
        createDraftFromAudio ??
        ({required String audioPath, DateTime? qsoStartedAt}) async =>
            _draft(audioPath: audioPath, dateTime: qsoStartedAt),
    loadSettings: () async => settings,
    artifactService: artifactService ?? _FakeArtifactService(),
  );
}

QsoDraft _draft({
  String? audioPath,
  DateTime? dateTime,
  String? rawTranscript,
}) {
  return QsoDraft(
    callsign: const QsoField(value: 'K1ABC'),
    dateTime: QsoField(value: dateTime ?? DateTime(2026, 7, 6)),
    band: const QsoField(value: '20m'),
    frequency: const QsoField(value: ''),
    mode: const QsoField(value: 'SSB'),
    sentRst: const QsoField(value: '59'),
    receivedRst: const QsoField(value: '59'),
    status: LogStatus.needsReview,
    audioPath: audioPath,
    rawTranscript: rawTranscript,
    transcriptSegments: audioPath != null && rawTranscript != null
        ? [
            TranscriptSegment(
              speaker: TranscriptSpeaker.unknown,
              text: rawTranscript,
              isFinal: true,
              audioPath: audioPath,
            ),
          ]
        : const [],
  );
}

class _FakeArtifactService extends QsoArtifactService {
  _FakeArtifactService([List<String>? deleted]) : deleted = deleted ?? [];

  final List<String> deleted;

  @override
  Future<void> deleteOwnedAudioFileIfExists(String path) async {
    deleted.add(path);
  }
}
