import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';
import '../data/export_service.dart';
import '../data/export_history_repository.dart';
import '../data/import_repository.dart';
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
import '../services/qso_processing_service.dart';
import '../services/qwen_realtime_speech_provider.dart';
import '../services/record_audio_capture_service.dart';
import '../services/release_info_service.dart';

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

final tokenUsageRepositoryProvider = Provider<TokenUsageRepository>(
  (ref) => TokenUsageRepository(ref.watch(appDatabaseProvider)),
);

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(qsoRepositoryProvider)),
);

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
      .maybeWhen(
        data: (settings) => settings.callsign,
        orElse: () => '',
      ),
);

final qthProvider = Provider<String>(
  (ref) => ref
      .watch(appSettingsProvider)
      .maybeWhen(
        data: (settings) => settings.qth,
        orElse: () => '',
      ),
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

class WelcomeShownNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() {
    return ref.watch(settingsRepositoryProvider).loadWelcomeShown();
  }

  Future<void> markShown() async {
    state = const AsyncData(true);
    await ref.read(settingsRepositoryProvider).saveWelcomeShown();
  }
}

final welcomeShownProvider =
    AsyncNotifierProvider<WelcomeShownNotifier, bool>(
      WelcomeShownNotifier.new,
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
  List<String> _finalTranscripts = [];
  String? _partial;

  void startQso({
    required TranscriptionMode mode,
    required DateTime startedAt,
  }) {
    _finalTranscripts = [];
    _partial = null;
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
      await provider.startSession(
        const SpeechSessionConfig(
          providerId: '',
          modelId: '',
          mode: TranscriptionMode.streaming,
        ),
      );
      _frameSub = ref
          .read(audioCaptureServiceProvider)
          .frames
          .listen((frame) => unawaited(provider.sendAudioFrame(frame)));
      _transcriptSub = provider.transcriptEvents.listen(
        _onTranscript,
        onError: (Object error) {
          _updateCapture(
            (state) => state.copyWith(warningMessage: 'no_streaming_transcript'),
          );
        },
      );
      _updateCapture((state) => state.copyWith(warningMessage: null));
    } catch (_) {
      await _stopStreaming();
      _updateCapture(
        (state) => state.copyWith(warningMessage: 'streaming_not_configured'),
      );
    }
  }

  Future<SpeechTranscriptionProvider?> _resolveStreamingProvider() async {
    final assignments =
        await ref.read(modelAssignmentRepositoryProvider).listAssignments();
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
    final connection =
        await ref.read(providerRepositoryProvider).findConnection(providerId);
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

  void _onTranscript(TranscriptSegment segment) {
    if (segment.isFinal) {
      if (segment.text.trim().isNotEmpty) {
        _finalTranscripts.add(segment.text.trim());
      }
      _partial = null;
    } else {
      _partial = segment.text;
    }
    final segments = <TranscriptSegment>[
      for (final text in _finalTranscripts)
        TranscriptSegment(speaker: 'RX', text: text, isFinal: true),
      if (_partial != null && _partial!.trim().isNotEmpty)
        TranscriptSegment(speaker: 'RX', text: _partial!, isFinal: false),
    ];
    _updateCapture((state) => state.copyWith(transcriptSegments: segments));
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
  /// 不清空 [_finalTranscripts]，设置 pendingStructuring 标志。
  Future<QsoDraft> stopQsoStreaming({
    required String? audioPath,
    required DateTime? startedAt,
  }) async {
    final current = await future;
    await _stopStreaming();
    final rawText = <String>[
      ..._finalTranscripts,
      if (_partial != null && _partial!.trim().isNotEmpty) _partial!,
    ].join('\n');
    // 将最终 partial 合并进 finalTranscripts，以便 UI 展示完整文本
    if (_partial != null && _partial!.trim().isNotEmpty) {
      _finalTranscripts.add(_partial!.trim());
      _partial = null;
      _updateCapture((s) => s.copyWith(transcriptSegments: [
        for (final text in _finalTranscripts)
          TranscriptSegment(speaker: 'RX', text: text, isFinal: true),
      ]));
    }
    final draft = current.currentDraft.copyWith(
      audioPath: audioPath,
      rawTranscript: rawText.trim().isEmpty ? null : rawText,
      dateTime: QsoField(value: startedAt ?? current.currentDraft.dateTime.value),
      status: LogStatus.draft,
    );
    state = AsyncData(
      current.copyWith(
        currentDraft: draft,
        pendingStructuring: rawText.trim().isNotEmpty,
      ),
    );
    return draft;
  }

  /// 将当前保留的流式转写文本结构化为 QSO 草稿。
  Future<QsoDraft> structureCapturedTranscript() async {
    final current = await future;
    final rawText = <String>[
      ..._finalTranscripts,
      if (_partial != null && _partial!.trim().isNotEmpty) _partial!,
    ].join('\n');
    _finalTranscripts = [];
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
    QsoDraft draft;
    try {
      draft = await ref.read(qsoProcessingServiceProvider).createDraftFromText(
        rawText,
        audioPath: audioPath,
        dateTime: dateTime,
      );
    } catch (_) {
      draft = current.currentDraft.copyWith(
        rawTranscript: rawText,
        status: LogStatus.needsReview,
      );
    }
    final retainedDraft = await _applyRecognitionRetention(draft);
    state = AsyncData(
      current.copyWith(
        currentDraft: retainedDraft,
        pendingStructuring: false,
        clearWarning: true,
      ),
    );
    return retainedDraft;
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
        var draft = await ref
            .read(qsoProcessingServiceProvider)
            .createDraftFromAudio(
              audioPath: audioPath,
              qsoStartedAt: startedAt,
            );
        draft = await _applyRecognitionRetention(draft);
        state = AsyncData(
          QsoCaptureState(
            currentDraft: draft,
            transcriptSegments: [
              if (draft.rawTranscript?.isNotEmpty ?? false)
                TranscriptSegment(
                  speaker: 'RX',
                  text: draft.rawTranscript!,
                  isFinal: true,
                ),
            ],
          ),
        );
        return draft;
      } catch (error) {
        final rawTranscript = error is QsoStructuringException
            ? error.rawTranscript
            : null;
        final draft = current.currentDraft.copyWith(
          audioPath: audioPath,
          rawTranscript: rawTranscript,
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

  Future<QsoDraft> _applyRecognitionRetention(QsoDraft draft) async {
    final settings = await ref.read(appSettingsProvider.future);
    final audioPath = draft.audioPath;
    if (settings.audioRetentionPolicy ==
            AudioRetentionPolicy.deleteAfterRecognition &&
        audioPath != null) {
      await _deleteOwnedAudioFileIfExists(audioPath);
      return draft.copyWith(clearAudioPath: true);
    }
    return draft;
  }
}

final qsoCaptureProvider =
    AsyncNotifierProvider<QsoCaptureNotifier, QsoCaptureState>(
      QsoCaptureNotifier.new,
    );

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
      await _deleteOwnedFileIfExists(qso.audioPath!);
      qsoToSave = qso.copyWith(clearAudioPath: true);
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
    final trashFiles = await _trashOwnedAudioFileIfExists(path);
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
    await _restoreFromTrash(trashFiles);
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
        await _deleteOwnedFileIfExists(audioPath);
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

  Future<void> _deleteOwnedFileIfExists(String path) async {
    await _deleteOwnedAudioFileIfExists(path);
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
          .read(qsoProcessingServiceProvider)
          .createDraftFromText(rawText);
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
    final retainedPath = await _copyAudioImportToAppStorage(sourcePath);
    final job = await repository.createJob(
      sourceType: ImportSourceType.audio,
      sourcePath: retainedPath,
    );
    await repository.updateJob(id: job.id, status: ImportJobStatus.processing);
    try {
      var draft = await ref
          .read(qsoProcessingServiceProvider)
          .createDraftFromAudio(audioPath: retainedPath);
      final settings = await ref.read(appSettingsProvider.future);
      if (settings.audioRetentionPolicy ==
              AudioRetentionPolicy.deleteAfterRecognition &&
          draft.audioPath != null) {
        await _deleteOwnedAudioFileIfExists(draft.audioPath!);
        draft = draft.copyWith(clearAudioPath: true);
      }
      await repository.updateJob(id: job.id, status: ImportJobStatus.completed);
      state = await AsyncValue.guard(repository.listJobs);
      return ImportDraft(jobId: job.id, draft: draft);
    } catch (error) {
      final rawTranscript = error is QsoStructuringException
          ? error.rawTranscript
          : null;
      await repository.updateJob(
        id: job.id,
        status: ImportJobStatus.failed,
        errorMessage: error.toString(),
      );
      state = await AsyncValue.guard(repository.listJobs);
      if (rawTranscript != null) {
        return ImportDraft(
          jobId: job.id,
          draft: _manualAudioReviewDraft(
            audioPath: retainedPath,
            rawTranscript: rawTranscript,
          ),
        );
      }
      return ImportDraft(
        jobId: job.id,
        draft: _manualAudioReviewDraft(audioPath: retainedPath),
      );
    }
  }

  QsoDraft _manualAudioReviewDraft({
    required String audioPath,
    String? rawTranscript,
  }) {
    return QsoDraft(
      callsign: const QsoField(value: '', confidence: 0.2),
      dateTime: const QsoField<DateTime?>(value: null),
      band: const QsoField(value: '', confidence: 0.2),
      frequency: const QsoField(value: '', confidence: 0.2),
      mode: const QsoField(value: '', confidence: 0.2),
      sentRst: const QsoField(value: '', confidence: 0.2),
      receivedRst: const QsoField(value: '', confidence: 0.2),
      status: LogStatus.failed,
      audioPath: audioPath,
      rawTranscript: rawTranscript,
    );
  }

  Future<String> _copyAudioImportToAppStorage(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw StateError('audio_file_missing');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(appDir.path, 'imports', 'audio'));
    if (!audioDir.existsSync()) {
      await audioDir.create(recursive: true);
    }
    final extension = p.extension(source.path);
    final originalName = p.basenameWithoutExtension(source.path);
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final fileName =
        '${timestamp}_$originalName${extension.isEmpty ? '.audio' : extension}';
    final retainedPath = p.join(audioDir.path, fileName);
    return source.copy(retainedPath).then((file) => file.path);
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

Future<List<MapEntry<String, String>>> _trashOwnedAudioFileIfExists(
  String path,
) async {
  final appDir = await getApplicationDocumentsDirectory();
  final appRoot = p.normalize(appDir.path);
  final trashDir = Directory(p.join(appRoot, '.trash'));
  final candidates = [
    File(path),
    if (p.extension(path).toLowerCase() == '.pcm')
      File(p.setExtension(path, '.wav')),
  ];
  final trashFiles = <MapEntry<String, String>>[];
  for (final file in candidates) {
    if (!file.existsSync()) continue;
    final filePath = p.normalize(file.absolute.path);
    if (filePath != appRoot && !p.isWithin(appRoot, filePath)) continue;
    if (!trashDir.existsSync()) {
      await trashDir.create(recursive: true);
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final dest = p.join(trashDir.path, '${stamp}_${p.basename(filePath)}');
    await file.rename(dest);
    trashFiles.add(MapEntry(dest, filePath));
  }
  return trashFiles;
}

Future<void> _restoreFromTrash(
  List<MapEntry<String, String>> trashFiles,
) async {
  if (trashFiles.isEmpty) return;
  final appDir = await getApplicationDocumentsDirectory();
  final appRoot = p.normalize(appDir.path);
  for (final file in trashFiles) {
    final src = File(file.key);
    if (!src.existsSync()) continue;
    final originalPath = p.normalize(file.value);
    if (originalPath != appRoot && !p.isWithin(appRoot, originalPath)) continue;
    await Directory(p.dirname(originalPath)).create(recursive: true);
    await src.rename(originalPath);
  }
}

Future<void> _deleteOwnedAudioFileIfExists(String path) async {
  final appDir = await getApplicationDocumentsDirectory();
  final appRoot = p.normalize(appDir.path);
  final candidates = [
    File(path),
    if (p.extension(path).toLowerCase() == '.pcm')
      File(p.setExtension(path, '.wav')),
  ];

  for (final file in candidates) {
    if (!file.existsSync()) {
      continue;
    }
    final filePath = p.normalize(file.absolute.path);
    if (filePath == appRoot || p.isWithin(appRoot, filePath)) {
      await file.delete();
    }
  }
}

final modelOptionsProvider = FutureProvider<List<AiModelOption>>(
  (ref) => ref.watch(modelRepositoryProvider).listModels(),
);

final tokenUsageListProvider =
    FutureProvider.autoDispose<List<TokenUsageRecord>>(
  (ref) => ref.watch(tokenUsageRepositoryProvider).listRecords(),
);
