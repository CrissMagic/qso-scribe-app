import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../data/app_database.dart';
import '../data/export_service.dart';
import '../data/export_history_repository.dart';
import '../data/import_repository.dart';
import '../data/logbook_upload_repository.dart';
import '../data/model_assignment_repository.dart';
import '../data/model_repository.dart';
import '../data/provider_repository.dart';
import '../data/token_usage_repository.dart';
import '../data/qso_repository.dart';
import '../data/settings_repository.dart';
import '../domain/app_models.dart';
import '../domain/provider_catalog.dart';
import '../domain/service_contracts.dart';
import '../services/ai_provider_clients.dart';
import '../services/app_update_service.dart';
import '../services/heuristic_qso_structuring_service.dart';
import '../services/local_audio_playback_service.dart';
import '../services/qso_artifact_service.dart';
import '../services/qso_intake_service.dart';
import '../services/qso_processing_service.dart';
import '../services/qrz_logbook_upload_service.dart';
import '../services/qwen_realtime_speech_provider.dart';
import '../services/record_audio_capture_service.dart';
import '../services/release_info_service.dart';
import '../services/wav_audio.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) => AppDatabase());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(appDatabaseProvider)),
);

final qsoRepositoryProvider = Provider<QsoRepository>(
  (ref) => QsoRepository(ref.watch(appDatabaseProvider)),
);

final providerRepositoryProvider = Provider<ProviderRepository>(
  (ref) => ProviderRepository(ref.watch(appDatabaseProvider)),
);

final modelAssignmentRepositoryProvider = Provider<ModelAssignmentRepository>(
  (ref) => ModelAssignmentRepository(ref.watch(appDatabaseProvider)),
);

final modelRepositoryProvider = Provider<ModelRepository>(
  (ref) => ModelRepository(ref.watch(appDatabaseProvider)),
);

final importRepositoryProvider = Provider<ImportRepository>(
  (ref) => ImportRepository(ref.watch(appDatabaseProvider)),
);

final exportHistoryRepositoryProvider = Provider<ExportHistoryRepository>(
  (ref) => ExportHistoryRepository(ref.watch(appDatabaseProvider)),
);

final logbookUploadRepositoryProvider = Provider<LogbookUploadRepository>(
  (ref) => LogbookUploadRepository(ref.watch(appDatabaseProvider)),
);

final tokenUsageRepositoryProvider = Provider<TokenUsageRepository>(
  (ref) => TokenUsageRepository(ref.watch(appDatabaseProvider)),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(qsoRepositoryProvider)),
);

final qrzLogbookUploadServiceProvider = Provider<QrzLogbookUploadService>((
  ref,
) {
  final service = QrzLogbookUploadService();
  ref.onDispose(service.close);
  return service;
});

final providerStructuringClientProvider = Provider<ProviderStructuringClient>(
  (ref) => ProviderStructuringClient(http.Client()),
);

final releaseInfoServiceProvider = Provider<ReleaseInfoService>((ref) {
  final service = ReleaseInfoService();
  ref.onDispose(service.close);
  return service;
});

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  final service = AppUpdateService();
  ref.onDispose(service.close);
  return service;
});

enum AppUpdateStatus {
  idle,
  checking,
  updateAvailable,
  upToDate,
  noRelease,
  downloading,
  downloaded,
  installing,
  failed,
}

class AppUpdateState {
  const AppUpdateState({
    this.status = AppUpdateStatus.idle,
    this.currentVersion,
    this.release,
    this.receivedBytes = 0,
    this.totalBytes,
    this.localApkPath,
    this.errorCode,
    this.openInstallerWhenDone = false,
  });

  final AppUpdateStatus status;
  final String? currentVersion;
  final AppRelease? release;
  final int receivedBytes;
  final int? totalBytes;
  final String? localApkPath;
  final String? errorCode;
  final bool openInstallerWhenDone;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (receivedBytes / total).clamp(0, 1).toDouble();
  }

  bool get isBusy =>
      status == AppUpdateStatus.checking ||
      status == AppUpdateStatus.downloading ||
      status == AppUpdateStatus.installing;

  AppUpdateState copyWith({
    AppUpdateStatus? status,
    String? currentVersion,
    AppRelease? release,
    int? receivedBytes,
    int? totalBytes,
    String? localApkPath,
    String? errorCode,
    bool? openInstallerWhenDone,
    bool clearRelease = false,
    bool clearProgress = false,
    bool clearLocalApkPath = false,
    bool clearError = false,
  }) {
    return AppUpdateState(
      status: status ?? this.status,
      currentVersion: currentVersion ?? this.currentVersion,
      release: clearRelease ? null : release ?? this.release,
      receivedBytes: clearProgress ? 0 : receivedBytes ?? this.receivedBytes,
      totalBytes: clearProgress ? null : totalBytes ?? this.totalBytes,
      localApkPath: clearLocalApkPath
          ? null
          : localApkPath ?? this.localApkPath,
      errorCode: clearError ? null : errorCode ?? this.errorCode,
      openInstallerWhenDone:
          openInstallerWhenDone ?? this.openInstallerWhenDone,
    );
  }
}

class AppUpdateNotifier extends Notifier<AppUpdateState> {
  Future<void>? _downloadTask;

  @override
  AppUpdateState build() {
    return const AppUpdateState();
  }

  Future<AppUpdateState> checkForUpdate({
    required String currentVersion,
    bool silent = false,
  }) async {
    if (state.status == AppUpdateStatus.checking) {
      return state;
    }

    state = state.copyWith(
      status: AppUpdateStatus.checking,
      currentVersion: currentVersion,
      clearError: true,
      clearLocalApkPath: true,
      clearProgress: true,
    );

    try {
      final release = await ref
          .read(releaseInfoServiceProvider)
          .fetchLatestRelease();
      final hasUpdate = compareVersions(release.version, currentVersion) > 0;
      state = AppUpdateState(
        status: hasUpdate
            ? AppUpdateStatus.updateAvailable
            : AppUpdateStatus.upToDate,
        currentVersion: currentVersion,
        release: release,
      );
    } on ReleaseInfoException catch (error) {
      if (silent) {
        state = AppUpdateState(currentVersion: currentVersion);
      } else {
        state = AppUpdateState(
          status: error.reason == ReleaseInfoFailureReason.noRelease
              ? AppUpdateStatus.noRelease
              : AppUpdateStatus.failed,
          currentVersion: currentVersion,
          errorCode: error.reason.name,
        );
      }
    }
    return state;
  }

  Future<void> downloadLatest({required bool openInstallerWhenDone}) {
    final currentTask = _downloadTask;
    if (currentTask != null) {
      return currentTask;
    }

    final release = state.release;
    if (release == null) {
      state = state.copyWith(
        status: AppUpdateStatus.failed,
        errorCode: 'release_missing',
      );
      return Future<void>.value();
    }

    final task = _download(
      release,
      openInstallerWhenDone: openInstallerWhenDone,
    );
    _downloadTask = task;
    return task.whenComplete(() => _downloadTask = null);
  }

  Future<void> openInstaller() async {
    final apkPath = state.localApkPath;
    if (apkPath == null || apkPath.trim().isEmpty) {
      state = state.copyWith(
        status: AppUpdateStatus.failed,
        errorCode: 'invalid_apk_path',
      );
      return;
    }

    state = state.copyWith(
      status: AppUpdateStatus.installing,
      clearError: true,
    );
    try {
      await ref.read(appUpdateServiceProvider).openInstaller(apkPath);
      state = state.copyWith(
        status: AppUpdateStatus.downloaded,
        clearError: true,
      );
    } on AppUpdateException catch (error) {
      state = state.copyWith(
        status: AppUpdateStatus.failed,
        errorCode: error.reason.name,
      );
    }
  }

  Future<void> _download(
    AppRelease release, {
    required bool openInstallerWhenDone,
  }) async {
    state = AppUpdateState(
      status: AppUpdateStatus.downloading,
      currentVersion: state.currentVersion,
      release: release,
      totalBytes: release.apkAsset.size,
      openInstallerWhenDone: openInstallerWhenDone,
    );

    try {
      final path = await ref
          .read(appUpdateServiceProvider)
          .downloadApk(
            release,
            onProgress: (receivedBytes, totalBytes) {
              state = state.copyWith(
                status: AppUpdateStatus.downloading,
                receivedBytes: receivedBytes,
                totalBytes: totalBytes ?? release.apkAsset.size,
                clearError: true,
              );
            },
          );
      state = state.copyWith(
        status: AppUpdateStatus.downloaded,
        localApkPath: path,
        clearError: true,
      );
      if (openInstallerWhenDone) {
        await openInstaller();
      }
    } on AppUpdateException catch (error) {
      state = state.copyWith(
        status: AppUpdateStatus.failed,
        errorCode: error.reason.name,
      );
    }
  }
}

final appUpdateProvider = NotifierProvider<AppUpdateNotifier, AppUpdateState>(
  AppUpdateNotifier.new,
);

final exportHistoryProvider = FutureProvider<List<ExportHistoryEntry>>(
  (ref) => ref.watch(exportHistoryRepositoryProvider).listExports(),
);

final qrzUploadProvider = FutureProvider.family<LogbookUploadEntry?, String>((
  ref,
  qsoId,
) {
  return ref
      .watch(logbookUploadRepositoryProvider)
      .findUpload(qsoId: qsoId, logbook: ExternalLogbook.qrz);
});

final localDataSummaryProvider = FutureProvider<LocalDataSummary>((ref) async {
  final retainedAudioCount = await ref
      .watch(qsoRepositoryProvider)
      .countRetainedAudio();
  final qsoRawTranscriptCount = await ref
      .watch(qsoRepositoryProvider)
      .countRawTranscripts();
  final importRawTextCount = await ref
      .watch(importRepositoryProvider)
      .countRawText();
  return LocalDataSummary(
    retainedAudioCount: retainedAudioCount,
    rawTranscriptCount: qsoRawTranscriptCount + importRawTextCount,
  );
});

final audioCaptureServiceProvider = Provider<RecordAudioCaptureService>((ref) {
  final service = RecordAudioCaptureService();
  ref.onDispose(service.dispose);
  return service;
});

final audioPlaybackServiceProvider = Provider<LocalAudioPlaybackService>((ref) {
  final service = LocalAudioPlaybackService();
  ref.onDispose(() => unawaited(service.stop()));
  return service;
});

final qsoStructuringServiceProvider = Provider<HeuristicQsoStructuringService>(
  (ref) => const HeuristicQsoStructuringService(),
);

final qsoProcessingServiceProvider = Provider<QsoProcessingService>(
  (ref) => QsoProcessingService(
    providerRepository: ref.watch(providerRepositoryProvider),
    modelAssignmentRepository: ref.watch(modelAssignmentRepositoryProvider),
    modelRepository: ref.watch(modelRepositoryProvider),
    heuristicStructuringService: ref.watch(qsoStructuringServiceProvider),
    tokenUsageRepository: ref.watch(tokenUsageRepositoryProvider),
  ),
);

final qsoArtifactServiceProvider = Provider<QsoArtifactService>(
  (ref) => QsoArtifactService(),
);

final qsoIntakeServiceProvider = Provider<QsoIntakeService>((ref) {
  final processing = ref.watch(qsoProcessingServiceProvider);
  return QsoIntakeService(
    createDraftFromText: processing.createDraftFromText,
    createDraftFromAudio: processing.createDraftFromAudio,
    loadSettings: () => ref.read(appSettingsProvider.future),
    artifactService: ref.watch(qsoArtifactServiceProvider),
  );
});

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() {
    return ref.watch(settingsRepositoryProvider).loadSettings();
  }

  Future<void> updateSettings(AppSettings settings) async {
    state = AsyncData(settings);
    await ref.read(settingsRepositoryProvider).saveSettings(settings);
  }

  Future<void> setLocaleMode(AppLocaleMode value) async {
    final current = await future;
    await updateSettings(current.copyWith(localeMode: value));
  }

  Future<void> setTranscriptionMode(TranscriptionMode value) async {
    final current = await future;
    await updateSettings(current.copyWith(transcriptionMode: value));
  }

  Future<void> setFailureHandling(FailureHandling value) async {
    final current = await future;
    await updateSettings(current.copyWith(failureHandling: value));
  }

  Future<void> setAudioRetentionPolicy(AudioRetentionPolicy value) async {
    final current = await future;
    await updateSettings(current.copyWith(audioRetentionPolicy: value));
  }

  Future<void> setCheckUpdatesOnStartup(bool value) async {
    final current = await future;
    await updateSettings(current.copyWith(checkUpdatesOnStartup: value));
  }

  Future<void> setCallsign(String value) async {
    final current = await future;
    await updateSettings(current.copyWith(callsign: value));
  }

  Future<void> setQth(String value) async {
    final current = await future;
    await updateSettings(current.copyWith(qth: value));
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
      AppSettingsNotifier.new,
    );

final localeModeProvider = Provider<AppLocaleMode>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(
        data: (settings) => settings.localeMode,
        orElse: () => AppLocaleMode.system,
      ),
);

final transcriptionModeProvider = Provider<TranscriptionMode>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(
        data: (settings) => settings.transcriptionMode,
        orElse: () => TranscriptionMode.streaming,
      ),
);

final failureHandlingProvider = Provider<FailureHandling>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(
        data: (settings) => settings.failureHandling,
        orElse: () => FailureHandling.alert,
      ),
);

final audioRetentionPolicyProvider = Provider<AudioRetentionPolicy>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(
        data: (settings) => settings.audioRetentionPolicy,
        orElse: () => AudioRetentionPolicy.keep,
      ),
);

final checkUpdatesOnStartupProvider = Provider<bool>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(
        data: (settings) => settings.checkUpdatesOnStartup,
        orElse: () => true,
      ),
);

final callsignProvider = Provider<String>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(data: (settings) => settings.callsign, orElse: () => ''),
);

final qthProvider = Provider<String>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(data: (settings) => settings.qth, orElse: () => ''),
);

class StationEquipmentNotifier extends AsyncNotifier<List<StationEquipment>> {
  @override
  Future<List<StationEquipment>> build() {
    return ref.watch(settingsRepositoryProvider).loadEquipment();
  }

  Future<void> save(List<StationEquipment> equipment) async {
    state = AsyncData(equipment);
    await ref.read(settingsRepositoryProvider).saveEquipment(equipment);
  }
}

final stationEquipmentProvider =
    AsyncNotifierProvider<StationEquipmentNotifier, List<StationEquipment>>(
      StationEquipmentNotifier.new,
    );

class SetupCompletedNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(settingsRepositoryProvider).loadSetupCompleted();
  }

  Future<void> complete() async {
    state = const AsyncData(true);
    await ref.read(settingsRepositoryProvider).saveSetupCompleted(true);
  }
}

final setupCompletedProvider =
    AsyncNotifierProvider<SetupCompletedNotifier, bool>(
      SetupCompletedNotifier.new,
    );

class RecordingSessionNotifier extends Notifier<RecordingSessionState> {
  Timer? _timer;

  @override
  RecordingSessionState build() {
    ref.onDispose(() => _timer?.cancel());
    return const RecordingSessionState(
      isRecording: false,
      elapsed: Duration.zero,
      mode: TranscriptionMode.streaming,
    );
  }

  void setSession(RecordingSessionState value) => state = value;

  Future<void> start(TranscriptionMode mode) async {
    state = RecordingSessionState(
      isRecording: false,
      elapsed: Duration.zero,
      mode: mode,
      isProcessing: true,
    );
    try {
      await ref.read(audioCaptureServiceProvider).start();
      final startedAt = DateTime.now();
      state = RecordingSessionState(
        isRecording: true,
        elapsed: Duration.zero,
        mode: mode,
        startedAt: startedAt,
      );
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        final currentStartedAt = state.startedAt;
        if (currentStartedAt == null || !state.isRecording) {
          return;
        }
        state = state.copyWith(
          elapsed: DateTime.now().difference(currentStartedAt),
        );
      });
    } catch (error) {
      state = RecordingSessionState(
        isRecording: false,
        elapsed: Duration.zero,
        mode: mode,
        errorMessage: error.toString(),
      );
    }
  }

  Future<String?> stop() async {
    _timer?.cancel();
    state = state.copyWith(isProcessing: true);
    try {
      final audioPath = await ref.read(audioCaptureServiceProvider).stop();
      state = state.copyWith(
        isRecording: false,
        isProcessing: false,
        audioPath: audioPath,
        clearError: true,
      );
      return audioPath;
    } catch (error) {
      state = state.copyWith(
        isRecording: false,
        isProcessing: false,
        errorMessage: error.toString(),
      );
      return null;
    }
  }
}

final recordingSessionProvider =
    NotifierProvider<RecordingSessionNotifier, RecordingSessionState>(
      RecordingSessionNotifier.new,
    );

class QsoCaptureNotifier extends AsyncNotifier<QsoCaptureState> {
  @override
  Future<QsoCaptureState> build() async {
    // 释放时清理流式资源（WebSocket + 订阅），避免泄漏。
    ref.onDispose(() {
      unawaited(_stopStreaming());
    });
    return QsoCaptureState(currentDraft: _emptyDraft());
  }

  SpeechTranscriptionProvider? _streamingProvider;
  StreamSubscription<AudioFrame>? _frameSub;
  StreamSubscription<TranscriptSegment>? _transcriptSub;
  List<TranscriptSegment> _finalSegments = [];
  final BytesBuilder _segmentAudio = BytesBuilder(copy: false);
  int _segmentSampleRate = defaultPcmSampleRate;
  int _segmentChannels = defaultPcmChannels;
  int _segmentSeq = 0;
  String? _partial;

  void startQso({
    required TranscriptionMode mode,
    required DateTime startedAt,
  }) {
    _finalSegments = [];
    _partial = null;
    _segmentAudio.takeBytes();
    _segmentSeq = 0;
    state = AsyncData(
      QsoCaptureState(currentDraft: _emptyDraft(dateTime: startedAt)),
    );
    if (mode == TranscriptionMode.streaming) {
      _beginStreaming();
    }
  }

  // 解析并启动流式转写：仅支持实现了实时传输的供应商（当前为 Qwen）。
  Future<void> _beginStreaming() async {
    try {
      final provider = await _resolveStreamingProvider();
      if (provider == null) {
        _updateCapture(
          (state) => state.copyWith(warningMessage: 'streaming_not_configured'),
        );
        return;
      }
      _streamingProvider = provider;
      await provider.startSession();
      _frameSub = ref
          .read(audioCaptureServiceProvider)
          .frames
          .listen((frame) => _onStreamingAudioFrame(frame, provider));
      _transcriptSub = provider.transcriptEvents.listen(
        _onTranscript,
        onError: (Object error) {
          _addUnrecognizedSegment(error.toString());
          if (!_finalSegments.any((segment) => segment.hasText)) {
            _updateCapture(
              (state) =>
                  state.copyWith(warningMessage: 'no_streaming_transcript'),
            );
          }
        },
      );
      _updateCapture((state) => state.copyWith(clearWarning: true));
    } catch (_) {
      await _stopStreaming();
      _updateCapture(
        (state) => state.copyWith(warningMessage: 'streaming_not_configured'),
      );
    }
  }

  Future<SpeechTranscriptionProvider?> _resolveStreamingProvider() async {
    final assignments = await ref
        .read(modelAssignmentRepositoryProvider)
        .listAssignments();
    String? providerId;
    String? modelId;
    for (final assignment in assignments) {
      if (assignment.task == ModelAssignmentTask.transcriptionStreaming) {
        providerId = assignment.providerId;
        modelId = assignment.modelId;
        break;
      }
    }
    // 向后兼容：未单独配置实时转写时回退到后置转写配置
    if (providerId == null || modelId == null) {
      for (final assignment in assignments) {
        if (assignment.task == ModelAssignmentTask.transcription) {
          providerId = providerId ?? assignment.providerId;
          modelId = modelId ?? assignment.modelId;
          break;
        }
      }
    }
    if (providerId == null || modelId == null) {
      return null;
    }
    final connection = await ref
        .read(providerRepositoryProvider)
        .findConnection(providerId);
    if (connection == null ||
        connection.apiKey == null ||
        connection.apiKey!.isEmpty) {
      return null;
    }
    final descriptor = descriptorFor(AiProvider.fromKey(connection.type));
    if (!descriptor.streamingCapable) {
      return null;
    }
    // 当前仅实现了 Qwen 实时传输。
    if (descriptor.provider != AiProvider.qwen) {
      return null;
    }
    final models = await ref.read(modelRepositoryProvider).listModels();
    AiModelOption? model;
    for (final option in models) {
      if (option.id == modelId) {
        model = option;
        break;
      }
    }
    if (model == null || !model.supports(ModelCapability.streaming)) {
      return null;
    }
    return QwenRealtimeSpeechProvider(
      apiKey: connection.apiKey!,
      modelName: model.name,
    );
  }

  void _onStreamingAudioFrame(
    AudioFrame frame,
    SpeechTranscriptionProvider provider,
  ) {
    _segmentSampleRate = frame.sampleRate;
    _segmentChannels = frame.channels;
    _segmentAudio.add(frame.bytes);
    unawaited(provider.sendAudioFrame(frame));
  }

  void _onTranscript(TranscriptSegment segment) {
    if (segment.isFinal) {
      _finalSegments = [..._finalSegments, _finalizeTranscriptSegment(segment)];
      _partial = null;
    } else {
      _partial = segment.text;
    }
    _publishTranscriptSegments();
  }

  void _addUnrecognizedSegment([String? errorMessage]) {
    _finalSegments = [
      ..._finalSegments,
      _finalizeTranscriptSegment(
        TranscriptSegment(
          speaker: TranscriptSpeaker.other,
          text: '',
          isFinal: true,
          errorMessage: errorMessage,
        ),
      ),
    ];
    _partial = null;
    _publishTranscriptSegments();
  }

  // ponytail: ASR final events are v1's approximate audio boundaries;
  // persisted bubble timelines can replace this when history replay matters.
  TranscriptSegment _finalizeTranscriptSegment(TranscriptSegment segment) {
    final audio = _takeSegmentAudio();
    final id = 'stream_${_segmentSeq++}';
    return segment.copyWith(id: id, duration: audio.duration);
  }

  _CapturedSegmentAudio _takeSegmentAudio() {
    final bytes = _segmentAudio.takeBytes();
    return _CapturedSegmentAudio(
      bytes: bytes,
      sampleRate: _segmentSampleRate,
      channels: _segmentChannels,
    );
  }

  void updateTranscriptSpeaker(int index, TranscriptSpeaker speaker) {
    if (index < 0 || index >= _finalSegments.length) {
      return;
    }
    _finalSegments = [
      for (var i = 0; i < _finalSegments.length; i += 1)
        if (i == index)
          _finalSegments[i].copyWith(speaker: speaker)
        else
          _finalSegments[i],
    ];
    _publishTranscriptSegments(updateDraftTranscript: true);
  }

  void _publishTranscriptSegments({bool updateDraftTranscript = false}) {
    final visibleSegments = [
      ..._finalSegments,
      if (_partial != null && _partial!.trim().isNotEmpty)
        TranscriptSegment(
          speaker: TranscriptSpeaker.other,
          text: _partial!,
          isFinal: false,
        ),
    ];
    _updateCapture((state) {
      if (!updateDraftTranscript || !state.pendingStructuring) {
        return state.copyWith(transcriptSegments: visibleSegments);
      }
      final rawText = formatTranscriptSegmentsForStructuring(_finalSegments);
      final draft = rawText.trim().isEmpty
          ? state.currentDraft.copyWith(clearRawTranscript: true)
          : state.currentDraft.copyWith(rawTranscript: rawText);
      return state.copyWith(
        currentDraft: draft,
        transcriptSegments: visibleSegments,
      );
    });
  }

  Future<void> _stopStreaming() async {
    await _frameSub?.cancel();
    _frameSub = null;
    final provider = _streamingProvider;
    _streamingProvider = null;
    // 先停帧上传，再让 provider 收尾（等待最后一句的 completed 与 session.finished）。
    // 期间转写订阅保持有效，确保最后一句的最终结果不被丢弃。
    await provider?.stop();
    await _transcriptSub?.cancel();
    _transcriptSub = null;
  }

  /// 停止流式转写但保留转写文本，等待用户点击 AI 处理再结构化。
  /// 不清空 [_finalSegments]，设置 pendingStructuring 标志。
  Future<QsoDraft> stopQsoStreaming({
    required String? audioPath,
    required DateTime? startedAt,
  }) async {
    await future;
    await _stopStreaming();
    if (_partial != null && _partial!.trim().isNotEmpty) {
      _finalSegments = [
        ..._finalSegments,
        _finalizeTranscriptSegment(
          TranscriptSegment(
            speaker: TranscriptSpeaker.other,
            text: _partial!.trim(),
            isFinal: true,
          ),
        ),
      ];
      _partial = null;
      _publishTranscriptSegments();
    }
    if (_segmentAudio.length > 0) {
      _addUnrecognizedSegment();
    }
    final rawText = formatTranscriptSegmentsForStructuring(_finalSegments);
    final latest = await future;
    var draft = latest.currentDraft.copyWith(
      audioPath: audioPath,
      rawTranscript: rawText.trim().isEmpty ? null : rawText,
      dateTime: QsoField(
        value: startedAt ?? latest.currentDraft.dateTime.value,
      ),
      status: LogStatus.draft,
    );
    draft = await ref
        .read(qsoIntakeServiceProvider)
        .applyRecognitionRetention(draft);
    state = AsyncData(
      latest.copyWith(
        currentDraft: draft,
        pendingStructuring: rawText.trim().isNotEmpty,
      ),
    );
    return draft;
  }

  /// 将当前保留的流式转写文本结构化为 QSO 草稿。
  Future<QsoDraft> structureCapturedTranscript() async {
    final current = await future;
    final rawText = formatTranscriptSegmentsForStructuring(_finalSegments);
    _partial = null;

    if (rawText.trim().isEmpty) {
      final draft = current.currentDraft.copyWith(
        status: LogStatus.needsReview,
        rawTranscript: null,
      );
      state = AsyncData(
        current.copyWith(
          currentDraft: draft,
          pendingStructuring: false,
          warningMessage: 'no_streaming_transcript',
        ),
      );
      return draft;
    }

    final audioPath = current.currentDraft.audioPath;
    final dateTime = current.currentDraft.dateTime.value;
    final draft = await ref
        .read(qsoIntakeServiceProvider)
        .reviewDraftFromText(
          rawText,
          audioPath: audioPath,
          dateTime: dateTime,
          originalAudioDeleted: current.currentDraft.originalAudioDeleted,
        );
    _finalSegments = [];
    _segmentAudio.takeBytes();
    state = AsyncData(
      current.copyWith(
        currentDraft: draft,
        transcriptSegments: const [],
        pendingStructuring: false,
        clearWarning: true,
      ),
    );
    return draft;
  }

  void _updateCapture(QsoCaptureState Function(QsoCaptureState) updater) {
    state = state.maybeWhen(
      data: (current) => AsyncData(updater(current)),
      orElse: () => state,
    );
  }

  Future<QsoDraft> finishQso({
    required String? audioPath,
    required DateTime? startedAt,
    required TranscriptionMode mode,
    required FailureHandling failureHandling,
  }) async {
    final current = await future;
    if (audioPath == null) {
      final draft = current.currentDraft.copyWith(
        status: LogStatus.needsReview,
      );
      state = AsyncData(current.copyWith(currentDraft: draft));
      return draft;
    }

    if (mode == TranscriptionMode.afterQso) {
      try {
        final draft = await ref
            .read(qsoIntakeServiceProvider)
            .reviewDraftFromAudio(audioPath: audioPath, startedAt: startedAt);
        state = AsyncData(
          QsoCaptureState(
            currentDraft: draft,
            transcriptSegments: [
              if (draft.rawTranscript?.isNotEmpty ?? false)
                TranscriptSegment(
                  speaker: TranscriptSpeaker.other,
                  text: draft.rawTranscript!,
                  isFinal: true,
                ),
            ],
          ),
        );
        return draft;
      } catch (error) {
        final draft = current.currentDraft.copyWith(
          audioPath: audioPath,
          status: LogStatus.failed,
          errorMessage: error.toString(),
        );
        state = AsyncData(
          current.copyWith(
            currentDraft: draft,
            warningMessage: failureHandling == FailureHandling.alert
                ? error.toString()
                : null,
          ),
        );
        return draft;
      }
    }

    // 流式模式的收尾已交由 stopQsoStreaming + structureCapturedTranscript 负责；
    // 此处委托以消除重复实现与不可达分支。
    return stopQsoStreaming(audioPath: audioPath, startedAt: startedAt);
  }

  QsoDraft _emptyDraft({DateTime? dateTime}) {
    return QsoDraft(
      callsign: const QsoField(value: '', confidence: 0.2),
      dateTime: QsoField(value: dateTime),
      band: const QsoField(value: '', confidence: 0.2),
      frequency: const QsoField(value: '', confidence: 0.2),
      mode: const QsoField(value: '', confidence: 0.2),
      sentRst: const QsoField(value: '', confidence: 0.2),
      receivedRst: const QsoField(value: '', confidence: 0.2),
      status: LogStatus.draft,
    );
  }
}

final qsoCaptureProvider =
    AsyncNotifierProvider<QsoCaptureNotifier, QsoCaptureState>(
      QsoCaptureNotifier.new,
    );

class _CapturedSegmentAudio {
  const _CapturedSegmentAudio({
    required this.bytes,
    required this.sampleRate,
    required this.channels,
  });

  final Uint8List bytes;
  final int sampleRate;
  final int channels;

  Duration? get duration {
    if (bytes.isEmpty) {
      return null;
    }
    final bytesPerSecond = sampleRate * channels * 2;
    return Duration(
      microseconds:
          bytes.length * Duration.microsecondsPerSecond ~/ bytesPerSecond,
    );
  }
}

class QsoLogNotifier extends AsyncNotifier<List<QsoDraft>> {
  @override
  Future<List<QsoDraft>> build() {
    return ref.watch(qsoRepositoryProvider).listQsos();
  }

  Future<void> refresh([QsoQuery query = const QsoQuery()]) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() {
      return ref.read(qsoRepositoryProvider).listQsos(query);
    });
  }

  Future<String> save(QsoDraft qso) async {
    var qsoToSave = qso;
    final settings = await ref.read(appSettingsProvider.future);
    if (settings.audioRetentionPolicy ==
            AudioRetentionPolicy.deleteAfterConfirmation &&
        (qso.status == LogStatus.confirmed ||
            qso.status == LogStatus.exported) &&
        qso.audioPath != null) {
      await ref
          .read(qsoArtifactServiceProvider)
          .deleteOwnedAudioFileIfExists(qso.audioPath!);
      qsoToSave = qso.copyWith(
        clearAudioPath: true,
        originalAudioDeleted: true,
      );
    }
    final id = await ref.read(qsoRepositoryProvider).saveQso(qsoToSave);
    await refresh();
    ref.invalidate(localDataSummaryProvider);
    return id;
  }

  Future<void> updateStatus(String id, LogStatus status) async {
    await ref.read(qsoRepositoryProvider).updateStatus(id, status);
    await refresh();
  }

  Future<List<MapEntry<String, String>>> deleteRetainedAudio({
    required String? qsoId,
    required String path,
  }) async {
    final trashFiles = await ref
        .read(qsoArtifactServiceProvider)
        .trashOwnedAudioFileIfExists(path);
    if (qsoId != null) {
      await ref.read(qsoRepositoryProvider).clearAudioPath(qsoId);
      await refresh();
    }
    ref.invalidate(localDataSummaryProvider);
    return trashFiles;
  }

  Future<void> restoreRetainedAudio({
    required String? qsoId,
    required String path,
    required List<MapEntry<String, String>> trashFiles,
  }) async {
    await ref.read(qsoArtifactServiceProvider).restoreFromTrash(trashFiles);
    if (qsoId != null) {
      await ref.read(qsoRepositoryProvider).setAudioPath(qsoId, path);
      await refresh();
    }
    ref.invalidate(localDataSummaryProvider);
  }

  Future<void> clearRawTranscript(String? qsoId) async {
    if (qsoId != null) {
      await ref.read(qsoRepositoryProvider).clearRawTranscript(qsoId);
      await refresh();
    }
    ref.invalidate(localDataSummaryProvider);
  }

  Future<void> restoreRawTranscript({
    required String qsoId,
    required String? rawTranscript,
  }) async {
    await ref
        .read(qsoRepositoryProvider)
        .setRawTranscript(qsoId, rawTranscript);
    await refresh();
    ref.invalidate(localDataSummaryProvider);
  }

  Future<void> deleteAllRetainedAudio() async {
    final logs = await ref.read(qsoRepositoryProvider).listQsos();
    for (final log in logs) {
      final audioPath = log.audioPath;
      if (audioPath != null) {
        await ref
            .read(qsoArtifactServiceProvider)
            .deleteOwnedAudioFileIfExists(audioPath);
      }
    }
    await ref.read(qsoRepositoryProvider).clearAllAudioPaths();
    await refresh();
    ref.invalidate(localDataSummaryProvider);
  }

  Future<void> clearAllRawContent() async {
    await ref.read(qsoRepositoryProvider).clearAllRawTranscripts();
    await ref.read(importRepositoryProvider).clearAllRawText();
    await refresh();
    ref.invalidate(importJobsProvider);
    ref.invalidate(localDataSummaryProvider);
  }
}

final qsoLogProvider = AsyncNotifierProvider<QsoLogNotifier, List<QsoDraft>>(
  QsoLogNotifier.new,
);

final providerProfilesProvider = FutureProvider<List<ProviderProfile>>(
  (ref) => ref.watch(providerRepositoryProvider).listProviders(),
);

class ModelAssignmentsNotifier extends AsyncNotifier<List<ModelAssignment>> {
  @override
  Future<List<ModelAssignment>> build() {
    return ref.watch(modelAssignmentRepositoryProvider).listAssignments();
  }

  Future<void> save(ModelAssignment assignment) async {
    await ref
        .read(modelAssignmentRepositoryProvider)
        .saveAssignment(assignment);
    state = await AsyncValue.guard(
      () => ref.read(modelAssignmentRepositoryProvider).listAssignments(),
    );
  }
}

final modelAssignmentsProvider =
    AsyncNotifierProvider<ModelAssignmentsNotifier, List<ModelAssignment>>(
      ModelAssignmentsNotifier.new,
    );

class ImportJobsNotifier extends AsyncNotifier<List<ImportJob>> {
  @override
  Future<List<ImportJob>> build() {
    return ref.watch(importRepositoryProvider).listJobs();
  }

  Future<ImportDraft> prepareTextImport(String rawText) async {
    final repository = ref.read(importRepositoryProvider);
    final job = await repository.createJob(
      sourceType: ImportSourceType.text,
      rawText: rawText,
    );
    await repository.updateJob(id: job.id, status: ImportJobStatus.processing);
    try {
      final draft = await ref
          .read(qsoIntakeServiceProvider)
          .reviewDraftFromText(rawText);
      await repository.updateJob(id: job.id, status: ImportJobStatus.completed);
      state = await AsyncValue.guard(repository.listJobs);
      return ImportDraft(jobId: job.id, draft: draft);
    } catch (error) {
      await repository.updateJob(
        id: job.id,
        status: ImportJobStatus.failed,
        errorMessage: error.toString(),
      );
      state = await AsyncValue.guard(repository.listJobs);
      rethrow;
    }
  }

  Future<ImportDraft> prepareAudioImport(String sourcePath) async {
    final repository = ref.read(importRepositoryProvider);
    final retainedPath = await ref
        .read(qsoArtifactServiceProvider)
        .copyAudioImportToAppStorage(sourcePath);
    final job = await repository.createJob(
      sourceType: ImportSourceType.audio,
      sourcePath: retainedPath,
    );
    await repository.updateJob(id: job.id, status: ImportJobStatus.processing);
    try {
      final draft = await ref
          .read(qsoIntakeServiceProvider)
          .reviewDraftFromAudio(audioPath: retainedPath);
      await repository.updateJob(id: job.id, status: ImportJobStatus.completed);
      state = await AsyncValue.guard(repository.listJobs);
      return ImportDraft(jobId: job.id, draft: draft);
    } catch (error) {
      await repository.updateJob(
        id: job.id,
        status: ImportJobStatus.failed,
        errorMessage: error.toString(),
      );
      state = await AsyncValue.guard(repository.listJobs);
      return ImportDraft(
        jobId: job.id,
        draft: ref
            .read(qsoIntakeServiceProvider)
            .manualReviewDraft(
              audioPath: retainedPath,
              status: LogStatus.failed,
              errorMessage: error.toString(),
            ),
      );
    }
  }

  Future<void> attachGeneratedQso({
    required String importJobId,
    required String qsoId,
  }) async {
    await ref
        .read(importRepositoryProvider)
        .updateJob(
          id: importJobId,
          status: ImportJobStatus.completed,
          generatedQsoId: qsoId,
        );
    state = await AsyncValue.guard(ref.read(importRepositoryProvider).listJobs);
  }

  Future<void> clearRawText(String importJobId) async {
    await ref.read(importRepositoryProvider).clearRawText(importJobId);
    state = await AsyncValue.guard(ref.read(importRepositoryProvider).listJobs);
    ref.invalidate(localDataSummaryProvider);
  }

  Future<String?> rawTextForJob(String importJobId) async {
    final job = await ref.read(importRepositoryProvider).findJob(importJobId);
    return job?.rawText;
  }

  Future<void> restoreRawText(String importJobId, String? rawText) async {
    await ref.read(importRepositoryProvider).setRawText(importJobId, rawText);
    state = await AsyncValue.guard(ref.read(importRepositoryProvider).listJobs);
    ref.invalidate(localDataSummaryProvider);
  }
}

final importJobsProvider =
    AsyncNotifierProvider<ImportJobsNotifier, List<ImportJob>>(
      ImportJobsNotifier.new,
    );

final modelOptionsProvider = FutureProvider<List<AiModelOption>>(
  (ref) => ref.watch(modelRepositoryProvider).listModels(),
);

final tokenUsageListProvider =
    FutureProvider.autoDispose<List<TokenUsageRecord>>(
      (ref) => ref.watch(tokenUsageRepositoryProvider).listRecords(),
    );
