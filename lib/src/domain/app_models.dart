import 'package:flutter/material.dart';

enum AppLocaleMode { system, zh, en }

enum TranscriptionMode { streaming, afterQso }

enum FailureHandling { alert, silent }

enum LogStatus { draft, needsReview, confirmed, exported, failed }

enum ExternalLogbook { qrz }

enum LogbookUploadStatus { pending, succeeded, failed, stale }

enum ModelCapability { speech, streaming, text, structuring }

enum ModelAssignmentTask { transcription, transcriptionStreaming, structuring }

enum TranscriptSpeaker { unknown, other, self }

enum QsoFieldKey {
  callsign,
  dateTime,
  band,
  frequency,
  mode,
  sentRst,
  receivedRst,
  name,
  qth,
  notes,
  rig,
  antenna,
  power,
}

extension AppLocaleModeX on AppLocaleMode {
  Locale? get locale {
    return switch (this) {
      AppLocaleMode.system => null,
      AppLocaleMode.zh => const Locale('zh'),
      AppLocaleMode.en => const Locale('en'),
    };
  }
}

class ProviderProfile {
  const ProviderProfile({
    required this.id,
    required this.name,
    required this.type,
    required this.hasApiKey,
    this.baseUrl,
  });

  final String id;
  final String name;
  final String type;
  final bool hasApiKey;
  final String? baseUrl;
}

class AiModelOption {
  const AiModelOption({
    required this.id,
    required this.providerId,
    required this.providerName,
    required this.name,
    required this.capabilities,
    this.enabled = true,
  });

  final String id;
  final String providerId;
  final String providerName;
  final String name;
  final Set<ModelCapability> capabilities;
  final bool enabled;

  bool supports(ModelCapability capability) =>
      capabilities.contains(capability);
}

class QsoField<T> {
  const QsoField({
    required this.value,
    this.confidence = 1,
    this.userEdited = false,
    this.reviewed = false,
    this.sourceText,
  });

  final T value;
  final double confidence;
  final bool userEdited;
  final bool reviewed;
  final String? sourceText;

  bool get needsReview => confidence < 0.75 && !userEdited && !reviewed;

  QsoField<T> copyWith({
    T? value,
    double? confidence,
    bool? userEdited,
    bool? reviewed,
    String? sourceText,
  }) {
    return QsoField<T>(
      value: value ?? this.value,
      confidence: confidence ?? this.confidence,
      userEdited: userEdited ?? this.userEdited,
      reviewed: reviewed ?? this.reviewed,
      sourceText: sourceText ?? this.sourceText,
    );
  }
}

class QsoDraft {
  const QsoDraft({
    this.id,
    required this.callsign,
    required this.dateTime,
    required this.band,
    required this.frequency,
    required this.mode,
    required this.sentRst,
    required this.receivedRst,
    required this.status,
    this.name,
    this.qth,
    this.notes,
    this.rig,
    this.antenna,
    this.power,
    this.audioPath,
    this.originalAudioDeleted = false,
    this.rawTranscript,
    this.transcriptSegments = const [],
    this.errorMessage,
    this.updatedAt,
    this.fmoRelayUid,
    this.fmoRelayName,
  });

  final String? id;
  final QsoField<String> callsign;
  final QsoField<DateTime?> dateTime;
  final QsoField<String> band;
  final QsoField<String> frequency;
  final QsoField<String> mode;
  final QsoField<String> sentRst;
  final QsoField<String> receivedRst;
  final LogStatus status;
  final QsoField<String>? name;
  final QsoField<String>? qth;
  final QsoField<String>? notes;
  final QsoField<String>? rig;
  final QsoField<String>? antenna;
  final QsoField<String>? power;
  final String? audioPath;
  final bool originalAudioDeleted;
  final String? rawTranscript;
  final List<TranscriptSegment> transcriptSegments;
  final DateTime? updatedAt;
  final String? fmoRelayUid;
  final String? fmoRelayName;

  bool get isFmo => fmoRelayUid != null;

  /// 处理提示（不持久化到数据库）。
  final String? errorMessage;

  bool get hasRequiredFields {
    return callsign.value.trim().isNotEmpty &&
        dateTime.value != null &&
        (isFmo ||
            ((band.value.trim().isNotEmpty ||
                    frequency.value.trim().isNotEmpty) &&
                mode.value.trim().isNotEmpty &&
                sentRst.value.trim().isNotEmpty &&
                receivedRst.value.trim().isNotEmpty));
  }

  bool get hasUnreviewedFields =>
      _stringFieldNeedsReview(callsign) ||
      (dateTime.value != null && dateTime.needsReview) ||
      _stringFieldNeedsReview(band) ||
      _stringFieldNeedsReview(frequency) ||
      _stringFieldNeedsReview(mode) ||
      _stringFieldNeedsReview(sentRst) ||
      _stringFieldNeedsReview(receivedRst) ||
      _optionalFieldNeedsReview(name) ||
      _optionalFieldNeedsReview(qth) ||
      _optionalFieldNeedsReview(notes) ||
      _optionalFieldNeedsReview(rig) ||
      _optionalFieldNeedsReview(antenna) ||
      _optionalFieldNeedsReview(power);

  QsoDraft copyWith({
    String? id,
    QsoField<String>? callsign,
    QsoField<DateTime?>? dateTime,
    QsoField<String>? band,
    QsoField<String>? frequency,
    QsoField<String>? mode,
    QsoField<String>? sentRst,
    QsoField<String>? receivedRst,
    LogStatus? status,
    QsoField<String>? name,
    QsoField<String>? qth,
    QsoField<String>? notes,
    QsoField<String>? rig,
    QsoField<String>? antenna,
    QsoField<String>? power,
    String? audioPath,
    bool? originalAudioDeleted,
    String? rawTranscript,
    List<TranscriptSegment>? transcriptSegments,
    String? errorMessage,
    DateTime? updatedAt,
    String? fmoRelayUid,
    String? fmoRelayName,
    bool clearAudioPath = false,
    bool clearRawTranscript = false,
    bool clearErrorMessage = false,
    bool clearName = false,
    bool clearQth = false,
    bool clearNotes = false,
    bool clearRig = false,
    bool clearAntenna = false,
    bool clearPower = false,
  }) {
    final resolvedAudioPath = clearAudioPath
        ? null
        : audioPath ?? this.audioPath;
    final sourceSegments = clearRawTranscript
        ? const <TranscriptSegment>[]
        : transcriptSegments ?? this.transcriptSegments;
    final resolvedSegments = [
      for (final segment in sourceSegments)
        if (resolvedAudioPath == null)
          segment.copyWith(clearAudioPath: true)
        else
          segment.copyWith(audioPath: resolvedAudioPath),
    ];
    return QsoDraft(
      id: id ?? this.id,
      callsign: callsign ?? this.callsign,
      dateTime: dateTime ?? this.dateTime,
      band: band ?? this.band,
      frequency: frequency ?? this.frequency,
      mode: mode ?? this.mode,
      sentRst: sentRst ?? this.sentRst,
      receivedRst: receivedRst ?? this.receivedRst,
      status: status ?? this.status,
      name: clearName ? null : name ?? this.name,
      qth: clearQth ? null : qth ?? this.qth,
      notes: clearNotes ? null : notes ?? this.notes,
      rig: clearRig ? null : rig ?? this.rig,
      antenna: clearAntenna ? null : antenna ?? this.antenna,
      power: clearPower ? null : power ?? this.power,
      audioPath: resolvedAudioPath,
      originalAudioDeleted: originalAudioDeleted ?? this.originalAudioDeleted,
      rawTranscript: clearRawTranscript
          ? null
          : rawTranscript ?? this.rawTranscript,
      transcriptSegments: resolvedSegments,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
      fmoRelayUid: fmoRelayUid ?? this.fmoRelayUid,
      fmoRelayName: fmoRelayName ?? this.fmoRelayName,
    );
  }

  static bool _stringFieldNeedsReview(QsoField<String> field) {
    return field.value.trim().isNotEmpty && field.needsReview;
  }

  static bool _optionalFieldNeedsReview(QsoField<String>? field) {
    return field != null && _stringFieldNeedsReview(field);
  }
}

class QsoCaptureState {
  const QsoCaptureState({
    required this.currentDraft,
    this.transcriptSegments = const [],
    this.warningMessage,
    this.isStructuring = false,
  });

  final QsoDraft currentDraft;
  final List<TranscriptSegment> transcriptSegments;
  final String? warningMessage;

  final bool isStructuring;

  QsoCaptureState copyWith({
    QsoDraft? currentDraft,
    List<TranscriptSegment>? transcriptSegments,
    String? warningMessage,
    bool? isStructuring,
    bool clearWarning = false,
  }) {
    return QsoCaptureState(
      currentDraft: currentDraft ?? this.currentDraft,
      transcriptSegments: transcriptSegments ?? this.transcriptSegments,
      warningMessage: clearWarning
          ? null
          : warningMessage ?? this.warningMessage,
      isStructuring: isStructuring ?? this.isStructuring,
    );
  }
}

class RecordingSessionState {
  const RecordingSessionState({
    required this.isRecording,
    required this.elapsed,
    required this.mode,
    this.audioPath,
    this.errorMessage,
    this.startedAt,
    this.isProcessing = false,
  });

  final bool isRecording;
  final Duration elapsed;
  final TranscriptionMode mode;
  final String? audioPath;
  final String? errorMessage;
  final DateTime? startedAt;
  final bool isProcessing;

  RecordingSessionState copyWith({
    bool? isRecording,
    Duration? elapsed,
    TranscriptionMode? mode,
    String? audioPath,
    String? errorMessage,
    DateTime? startedAt,
    bool? isProcessing,
    bool clearError = false,
  }) {
    return RecordingSessionState(
      isRecording: isRecording ?? this.isRecording,
      elapsed: elapsed ?? this.elapsed,
      mode: mode ?? this.mode,
      audioPath: audioPath ?? this.audioPath,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      startedAt: startedAt ?? this.startedAt,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

class TranscriptSegment {
  const TranscriptSegment({
    this.id,
    required this.speaker,
    required this.text,
    required this.isFinal,
    this.audioPath,
    this.duration,
    this.startOffset,
    this.endOffset,
    this.errorMessage,
  });

  final String? id;
  final TranscriptSpeaker speaker;
  final String text;
  final bool isFinal;
  final String? audioPath;
  final Duration? duration;
  final Duration? startOffset;
  final Duration? endOffset;
  final String? errorMessage;

  bool get hasText => text.trim().isNotEmpty;

  TranscriptSegment copyWith({
    String? id,
    TranscriptSpeaker? speaker,
    String? text,
    bool? isFinal,
    String? audioPath,
    Duration? duration,
    Duration? startOffset,
    Duration? endOffset,
    String? errorMessage,
    bool clearAudioPath = false,
    bool clearError = false,
  }) {
    return TranscriptSegment(
      id: id ?? this.id,
      speaker: speaker ?? this.speaker,
      text: text ?? this.text,
      isFinal: isFinal ?? this.isFinal,
      audioPath: clearAudioPath ? null : audioPath ?? this.audioPath,
      duration: duration ?? this.duration,
      startOffset: startOffset ?? this.startOffset,
      endOffset: endOffset ?? this.endOffset,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

String formatTranscriptSegmentsForStructuring(
  List<TranscriptSegment> segments,
) {
  return [
    for (final segment in segments)
      if (segment.hasText)
        '[${_transcriptSpeakerAiLabel(segment.speaker)}] ${segment.text.trim()}',
  ].join('\n');
}

String _transcriptSpeakerAiLabel(TranscriptSpeaker speaker) {
  return switch (speaker) {
    TranscriptSpeaker.unknown => '待确认',
    TranscriptSpeaker.other => '对方',
    TranscriptSpeaker.self => '我方',
  };
}

enum AudioRetentionPolicy {
  keep,
  deleteAfterRecognition,
  deleteAfterConfirmation,
}

enum ImportSourceType { audio, text }

enum ImportJobStatus { pending, processing, completed, failed }

class AppSettings {
  const AppSettings({
    required this.localeMode,
    required this.transcriptionMode,
    required this.failureHandling,
    required this.audioRetentionPolicy,
    required this.checkUpdatesOnStartup,
    this.callsign = '',
    this.qth = '',
  });

  const AppSettings.defaults()
    : localeMode = AppLocaleMode.system,
      transcriptionMode = TranscriptionMode.streaming,
      failureHandling = FailureHandling.alert,
      audioRetentionPolicy = AudioRetentionPolicy.keep,
      checkUpdatesOnStartup = true,
      callsign = '',
      qth = '';

  final AppLocaleMode localeMode;
  final TranscriptionMode transcriptionMode;
  final FailureHandling failureHandling;
  final AudioRetentionPolicy audioRetentionPolicy;
  final bool checkUpdatesOnStartup;
  final String callsign;
  final String qth;

  AppSettings copyWith({
    AppLocaleMode? localeMode,
    TranscriptionMode? transcriptionMode,
    FailureHandling? failureHandling,
    AudioRetentionPolicy? audioRetentionPolicy,
    bool? checkUpdatesOnStartup,
    String? callsign,
    String? qth,
  }) {
    return AppSettings(
      localeMode: localeMode ?? this.localeMode,
      transcriptionMode: transcriptionMode ?? this.transcriptionMode,
      failureHandling: failureHandling ?? this.failureHandling,
      audioRetentionPolicy: audioRetentionPolicy ?? this.audioRetentionPolicy,
      checkUpdatesOnStartup:
          checkUpdatesOnStartup ?? this.checkUpdatesOnStartup,
      callsign: callsign ?? this.callsign,
      qth: qth ?? this.qth,
    );
  }
}

/// 单条电台设备配置。
class StationEquipment {
  const StationEquipment({
    required this.name,
    this.antenna = '',
    this.powerOptions = const [],
  });

  final String name;
  final String antenna;
  final List<String> powerOptions;

  StationEquipment copyWith({
    String? name,
    String? antenna,
    List<String>? powerOptions,
  }) {
    return StationEquipment(
      name: name ?? this.name,
      antenna: antenna ?? this.antenna,
      powerOptions: powerOptions ?? this.powerOptions,
    );
  }
}

/// 单次 AI 请求返回的 token 用量（可能为 null，部分接口不返回）。
class TokenUsage {
  const TokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

/// 持久化的 token 消耗记录。
class TokenUsageRecord {
  const TokenUsageRecord({
    required this.id,
    required this.createdAt,
    required this.provider,
    required this.model,
    required this.taskType,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  final String id;
  final DateTime createdAt;
  final String provider;
  final String model;
  final String taskType;
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}

class ModelAssignment {
  const ModelAssignment({
    required this.task,
    required this.providerId,
    required this.modelId,
  });

  final ModelAssignmentTask task;
  final String providerId;
  final String modelId;
}

class ImportJob {
  const ImportJob({
    required this.id,
    required this.sourceType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sourcePath,
    this.rawText,
    this.generatedQsoId,
    this.errorMessage,
  });

  final String id;
  final ImportSourceType sourceType;
  final ImportJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? sourcePath;
  final String? rawText;
  final String? generatedQsoId;
  final String? errorMessage;
}

class ImportDraft {
  const ImportDraft({required this.jobId, required this.draft});

  final String jobId;
  final QsoDraft draft;
}

class ExportFilter {
  const ExportFilter({this.status, this.from, this.to, this.band, this.mode});

  final LogStatus? status;
  final DateTime? from;
  final DateTime? to;
  final String? band;
  final String? mode;
}

class ExportHistoryEntry {
  const ExportHistoryEntry({
    required this.id,
    required this.format,
    required this.filePath,
    required this.qsoCount,
    required this.filterSummary,
    required this.createdAt,
  });

  final String id;
  final String format;
  final String filePath;
  final int qsoCount;
  final String filterSummary;
  final DateTime createdAt;
}

class LogbookUploadEntry {
  const LogbookUploadEntry({
    required this.qsoId,
    required this.logbook,
    required this.status,
    required this.updatedAt,
    this.remoteId,
    this.errorMessage,
    this.uploadedAt,
  });

  final String qsoId;
  final ExternalLogbook logbook;
  final LogbookUploadStatus status;
  final DateTime updatedAt;
  final String? remoteId;
  final String? errorMessage;
  final DateTime? uploadedAt;
}

class LocalDataSummary {
  const LocalDataSummary({
    required this.retainedAudioCount,
    required this.rawTranscriptCount,
  });

  final int retainedAudioCount;
  final int rawTranscriptCount;
}
