import 'package:flutter/material.dart';

enum AppLocaleMode { system, zh, en }

enum TranscriptionMode { streaming, afterQso }

enum FailureHandling { alert, silent }

enum LogStatus { draft, needsReview, confirmed, exported, failed }

enum ModelCapability { speech, streaming, text, structuring }

enum ModelAssignmentTask { transcription, transcriptionStreaming, structuring }

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
    this.sourceText,
  });

  final T value;
  final double confidence;
  final bool userEdited;
  final String? sourceText;

  bool get needsReview => confidence < 0.75;

  QsoField<T> copyWith({
    T? value,
    double? confidence,
    bool? userEdited,
    String? sourceText,
  }) {
    return QsoField<T>(
      value: value ?? this.value,
      confidence: confidence ?? this.confidence,
      userEdited: userEdited ?? this.userEdited,
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
    this.rawTranscript,
    this.errorMessage,
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
  final String? rawTranscript;

  /// 失败原因（仅 failed 状态，不持久化到数据库）。
  final String? errorMessage;

  bool get hasRequiredFields {
    return callsign.value.trim().isNotEmpty &&
        dateTime.value != null &&
        (band.value.trim().isNotEmpty || frequency.value.trim().isNotEmpty) &&
        mode.value.trim().isNotEmpty &&
        sentRst.value.trim().isNotEmpty &&
        receivedRst.value.trim().isNotEmpty;
  }

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
    String? rawTranscript,
    String? errorMessage,
    bool clearAudioPath = false,
    bool clearRawTranscript = false,
  }) {
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
      name: name ?? this.name,
      qth: qth ?? this.qth,
      notes: notes ?? this.notes,
      rig: rig ?? this.rig,
      antenna: antenna ?? this.antenna,
      power: power ?? this.power,
      audioPath: clearAudioPath ? null : audioPath ?? this.audioPath,
      rawTranscript: clearRawTranscript
          ? null
          : rawTranscript ?? this.rawTranscript,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class QsoCaptureState {
  const QsoCaptureState({
    required this.currentDraft,
    this.transcriptSegments = const [],
    this.warningMessage,
    this.pendingStructuring = false,
  });

  final QsoDraft currentDraft;
  final List<TranscriptSegment> transcriptSegments;
  final String? warningMessage;

  /// 流式录音已停止，转写文本待用户点击 AI 处理进行结构化。
  final bool pendingStructuring;

  QsoCaptureState copyWith({
    QsoDraft? currentDraft,
    List<TranscriptSegment>? transcriptSegments,
    String? warningMessage,
    bool? pendingStructuring,
    bool clearWarning = false,
  }) {
    return QsoCaptureState(
      currentDraft: currentDraft ?? this.currentDraft,
      transcriptSegments: transcriptSegments ?? this.transcriptSegments,
      warningMessage: clearWarning
          ? null
          : warningMessage ?? this.warningMessage,
      pendingStructuring: pendingStructuring ?? this.pendingStructuring,
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
    required this.speaker,
    required this.text,
    required this.isFinal,
  });

  final String speaker;
  final String text;
  final bool isFinal;
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
  const TokenUsage({this.promptTokens, this.completionTokens, this.totalTokens});

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

class LocalDataSummary {
  const LocalDataSummary({
    required this.retainedAudioCount,
    required this.rawTranscriptCount,
  });

  final int retainedAudioCount;
  final int rawTranscriptCount;
}
