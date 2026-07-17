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
    return applyRecognitionRetention(draft);
  }

  Future<QsoDraft> applyRecognitionRetention(QsoDraft draft) async {
    final audioPath = draft.audioPath;
    if (audioPath == null) {
      return draft;
    }
    final settings = await _loadSettings();
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
      errorMessage: errorMessage,
    );
  }
}
