import '../domain/app_models.dart';
import 'qso_artifact_service.dart';
import 'qso_processing_service.dart';

typedef TextDraftFactory =
    Future<QsoDraft> Function(
      String rawText, {
      DateTime? dateTime,
      String? audioPath,
    });

typedef AudioDraftFactory =
    Future<QsoDraft> Function({
      required String audioPath,
      DateTime? qsoStartedAt,
    });

class QsoIntakeService {
  const QsoIntakeService({
    required TextDraftFactory createDraftFromText,
    required AudioDraftFactory createDraftFromAudio,
    required Future<AppSettings> Function() loadSettings,
    required QsoArtifactService artifactService,
  }) : _createDraftFromText = createDraftFromText,
       _createDraftFromAudio = createDraftFromAudio,
       _loadSettings = loadSettings,
       _artifactService = artifactService;

  final TextDraftFactory _createDraftFromText;
  final AudioDraftFactory _createDraftFromAudio;
  final Future<AppSettings> Function() _loadSettings;
  final QsoArtifactService _artifactService;

  Future<QsoDraft> reviewDraftFromText(
    String rawText, {
    DateTime? dateTime,
    String? audioPath,
    bool originalAudioDeleted = false,
  }) async {
    QsoDraft draft;
    try {
      draft = await _createDraftFromText(
        rawText,
        dateTime: dateTime,
        audioPath: audioPath,
      );
    } catch (error) {
      draft = manualReviewDraft(
        audioPath: audioPath,
        rawTranscript: rawText,
        dateTime: dateTime,
        errorMessage: error.toString(),
        originalAudioDeleted: originalAudioDeleted,
      );
    }
    final retainedDraft = await applyRecognitionRetention(draft);
    return originalAudioDeleted
        ? retainedDraft.copyWith(originalAudioDeleted: true)
        : retainedDraft;
  }

  Future<QsoDraft> reviewDraftFromAudio({
    required String audioPath,
    DateTime? startedAt,
  }) async {
    QsoDraft draft;
    try {
      draft = await _createDraftFromAudio(
        audioPath: audioPath,
        qsoStartedAt: startedAt,
      );
    } on QsoStructuringException catch (error) {
      draft = manualReviewDraft(
        audioPath: audioPath,
        rawTranscript: error.rawTranscript,
        dateTime: startedAt,
        errorMessage: error.message,
      );
    }
    final settings = await _loadSettings();
    return _applyRecognitionRetention(
      _removeOwnStationFields(draft, settings),
      settings,
    );
  }

  // Existing FMO logs can still be reprocessed from their saved recording.
  Future<QsoDraft> reviewLegacyFmoAudio({
    required String? audioPath,
    required DateTime? startedAt,
    required String relayUid,
    required String relayName,
  }) async {
    QsoDraft draft;
    try {
      draft = audioPath == null
          ? manualReviewDraft(dateTime: startedAt)
          : await reviewDraftFromAudio(
              audioPath: audioPath,
              startedAt: startedAt,
            );
    } catch (error) {
      draft = manualReviewDraft(
        audioPath: audioPath,
        dateTime: startedAt,
        status: LogStatus.failed,
        errorMessage: error.toString(),
      );
    }
    return draft.copyWith(
      callsign: draft.callsign.confidence < 0.75
          ? draft.callsign
          : draft.callsign.copyWith(confidence: 0.74),
      dateTime: QsoField<DateTime?>(value: startedAt ?? draft.dateTime.value),
      fmoRelayUid: relayUid,
      fmoRelayName: relayName,
    );
  }

  Future<QsoDraft> applyRecognitionRetention(QsoDraft draft) async {
    if (draft.audioPath == null) {
      return draft;
    }
    return _applyRecognitionRetention(draft, await _loadSettings());
  }

  Future<QsoDraft> _applyRecognitionRetention(
    QsoDraft draft,
    AppSettings settings,
  ) async {
    final audioPath = draft.audioPath;
    if (audioPath == null) {
      return draft;
    }
    if (settings.audioRetentionPolicy !=
        AudioRetentionPolicy.deleteAfterRecognition) {
      return draft;
    }
    await _artifactService.deleteOwnedAudioFileIfExists(audioPath);
    return draft.copyWith(clearAudioPath: true, originalAudioDeleted: true);
  }

  QsoDraft manualReviewDraft({
    String? audioPath,
    String? rawTranscript,
    DateTime? dateTime,
    LogStatus status = LogStatus.needsReview,
    String? errorMessage,
    bool originalAudioDeleted = false,
  }) {
    return QsoDraft(
      callsign: const QsoField(value: '', confidence: 0.2),
      dateTime: QsoField<DateTime?>(
        value: dateTime,
        confidence: dateTime == null ? 0.2 : 1,
      ),
      band: const QsoField(value: '', confidence: 0.2),
      frequency: const QsoField(value: '', confidence: 0.2),
      mode: const QsoField(value: '', confidence: 0.2),
      sentRst: const QsoField(value: '', confidence: 0.2),
      receivedRst: const QsoField(value: '', confidence: 0.2),
      status: status,
      audioPath: audioPath,
      originalAudioDeleted: originalAudioDeleted,
      rawTranscript: rawTranscript,
      transcriptSegments:
          audioPath != null && rawTranscript?.trim().isNotEmpty == true
          ? [
              TranscriptSegment(
                speaker: TranscriptSpeaker.unknown,
                text: rawTranscript!,
                isFinal: true,
                audioPath: audioPath,
              ),
            ]
          : const [],
      errorMessage: errorMessage,
    );
  }

  QsoDraft _removeOwnStationFields(QsoDraft draft, AppSettings settings) {
    final qth = draft.qth;
    final sourceText = qth?.sourceText ?? '';
    final ownQth = settings.qth.trim();
    final marksSelf =
        sourceText.contains('[我方]') || sourceText.contains('[我方资料]');
    final marksOther = sourceText.contains('[对方]');
    final isOwnQth = marksSelf && !marksOther;
    final sameQthNeedsReview =
        (qth != null &&
        ownQth.isNotEmpty &&
        qth.value.trim().toLowerCase() == ownQth.toLowerCase() &&
        !marksOther &&
        !isOwnQth);
    return draft.copyWith(
      callsign: callsignsMatch(draft.callsign.value, settings.callsign)
          ? const QsoField(value: '', confidence: 0.2)
          : draft.callsign,
      qth: sameQthNeedsReview
          ? qth.copyWith(
              confidence: qth.confidence < 0.75 ? qth.confidence : 0.74,
              userEdited: false,
              reviewed: false,
            )
          : qth,
      clearQth: isOwnQth,
    );
  }
}
