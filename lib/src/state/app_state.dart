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

final audioCaptureServiceProvider = Provider<AudioCaptureService>((ref) {
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
    loadSettings: () => ref.read(appSettingsProvider.future),
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

  void prepareStart(TranscriptionMode mode) {
    _timer?.cancel();
    state = RecordingSessionState(
      isRecording: false,
      elapsed: Duration.zero,
      mode: mode,
      isProcessing: true,
    );
  }

  void cancelStart() {
    state = RecordingSessionState(
      isRecording: false,
      elapsed: Duration.zero,
      mode: state.mode,
    );
  }

  Future<void> start(TranscriptionMode mode, {DateTime? startedAt}) async {
    prepareStart(mode);
    try {
      await ref.read(audioCaptureServiceProvider).start();
      final actualStartedAt = startedAt ?? DateTime.now();
      state = RecordingSessionState(
        isRecording: true,
        elapsed: Duration.zero,
        mode: mode,
        startedAt: actualStartedAt,
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

class QsoSessionNotifier extends Notifier<List<QsoDraft>> {
  @override
  List<QsoDraft> build() => const [];

  void record(QsoDraft qso) {
    final id = qso.id;
    if (id == null || id.trim().isEmpty) {
      throw ArgumentError.value(id, 'qso.id', 'session_qso_id_required');
    }
    final existingIndex = state.indexWhere((item) => item.id == id);
    if (existingIndex < 0) {
      state = [...state, qso];
      return;
    }
    state = [
      for (var index = 0; index < state.length; index += 1)
        if (index == existingIndex) qso else state[index],
    ];
  }

  void updateIfPresent(QsoDraft qso) {
    final id = qso.id;
    if (id == null || id.trim().isEmpty) {
      throw ArgumentError.value(id, 'qso.id', 'session_qso_id_required');
    }
    final existingIndex = state.indexWhere((item) => item.id == id);
    if (existingIndex < 0) {
      return;
    }
    state = [
      for (var index = 0; index < state.length; index += 1)
        if (index == existingIndex) qso else state[index],
    ];
  }

  QsoDraft? latestInheritable() {
    for (final qso in state.reversed) {
      if (qso.status == LogStatus.confirmed ||
          qso.status == LogStatus.exported) {
        return qso;
      }
    }
    return null;
  }
}

final qsoSessionProvider = NotifierProvider<QsoSessionNotifier, List<QsoDraft>>(
  QsoSessionNotifier.new,
);

class QsoCaptureNotifier extends AsyncNotifier<QsoCaptureState> {
  QsoCaptureNotifier({
    Future<SpeechTranscriptionProvider?> Function()? streamingProviderResolver,
    Future<QsoDraft> Function(String rawText, DateTime? dateTime)?
    realtimeDraftFactory,
    Future<QsoDraft> Function(String audioPath, DateTime? startedAt)?
    afterQsoDraftFactory,
    Future<QsoDraft> Function(QsoDraft draft)? recognitionRetentionApplier,
  }) : _streamingProviderResolver = streamingProviderResolver,
       _realtimeDraftFactory = realtimeDraftFactory,
       _afterQsoDraftFactory = afterQsoDraftFactory,
       _recognitionRetentionApplier = recognitionRetentionApplier;

  final Future<SpeechTranscriptionProvider?> Function()?
  _streamingProviderResolver;
  final Future<QsoDraft> Function(String rawText, DateTime? dateTime)?
  _realtimeDraftFactory;
  final Future<QsoDraft> Function(String audioPath, DateTime? startedAt)?
  _afterQsoDraftFactory;
  final Future<QsoDraft> Function(QsoDraft draft)? _recognitionRetentionApplier;

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
  Duration _segmentTimelineOffset = Duration.zero;
  int _segmentSeq = 0;
  String? _partial;
  String? _streamingFailure;
  String? _realtimeStructuringFailure;
  Future<void>? _realtimeStructuringTask;
  bool _realtimeStructuringRequested = false;

  Future<bool> startRecordingQso({required TranscriptionMode mode}) async {
    await future;
    await _waitForRealtimeStructuring();
    final currentSession = ref.read(recordingSessionProvider);
    if (currentSession.isRecording || currentSession.isProcessing) {
      return false;
    }
    _resetCapture();

    final recorder = ref.read(recordingSessionProvider.notifier);
    recorder.prepareStart(mode);
    if (mode == TranscriptionMode.streaming) {
      final ready = await _beginStreaming();
      if (!ready) {
        recorder.cancelStart();
        return false;
      }
      if (_streamingFailure != null) {
        await _stopStreaming();
        recorder.cancelStart();
        _updateCapture(
          (state) =>
              state.copyWith(warningMessage: 'streaming_connection_failed'),
        );
        return false;
      }
    }

    final startedAt = DateTime.now();
    final inherited = ref.read(qsoSessionProvider.notifier).latestInheritable();
    _updateCapture(
      (current) => current.copyWith(
        currentDraft: _emptyDraft(
          dateTime: startedAt,
          inheritedFrom: inherited,
        ),
      ),
    );
    await recorder.start(mode, startedAt: startedAt);
    if (!ref.read(recordingSessionProvider).isRecording) {
      if (mode == TranscriptionMode.streaming) {
        await _stopStreaming();
      }
      return false;
    }
    return true;
  }

  void clearCompletedQso() => _resetCapture();

  void _resetCapture() {
    _finalSegments = [];
    _partial = null;
    _streamingFailure = null;
    _realtimeStructuringFailure = null;
    _realtimeStructuringRequested = false;
    _segmentAudio.takeBytes();
    _segmentTimelineOffset = Duration.zero;
    _segmentSeq = 0;
    state = AsyncData(QsoCaptureState(currentDraft: _emptyDraft()));
  }

  // 解析并启动流式转写：仅支持实现了实时传输的供应商（当前为 Qwen）。
  Future<bool> _beginStreaming() async {
    try {
      final resolver = _streamingProviderResolver;
      final provider = resolver == null
          ? await _resolveStreamingProvider()
          : await resolver();
      if (provider == null) {
        _updateCapture(
          (state) => state.copyWith(warningMessage: 'streaming_not_configured'),
        );
        return false;
      }
      _streamingProvider = provider;
      _transcriptSub = provider.transcriptEvents.listen(
        _onTranscript,
        onError: _handleStreamingError,
      );
      await provider.startSession();
      _frameSub = ref
          .read(audioCaptureServiceProvider)
          .frames
          .listen((frame) => _onStreamingAudioFrame(frame, provider));
      if (_streamingFailure == null) {
        _updateCapture((state) => state.copyWith(clearWarning: true));
      }
      return true;
    } catch (_) {
      await _stopStreaming();
      _updateCapture(
        (state) =>
            state.copyWith(warningMessage: 'streaming_connection_failed'),
      );
      return false;
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
    unawaited(_sendStreamingAudioFrame(frame, provider));
  }

  Future<void> _sendStreamingAudioFrame(
    AudioFrame frame,
    SpeechTranscriptionProvider provider,
  ) async {
    try {
      await provider.sendAudioFrame(frame);
    } catch (error) {
      _handleStreamingError(error);
    }
  }

  void _handleStreamingError(Object error) {
    _streamingFailure = error.toString();
    _addUnrecognizedSegment(error.toString());
    if (ref.read(failureHandlingProvider) == FailureHandling.alert &&
        !_finalSegments.any((segment) => segment.hasText)) {
      _updateCapture(
        (state) => state.copyWith(warningMessage: 'no_streaming_transcript'),
      );
    }
  }

  void _onTranscript(TranscriptSegment segment) {
    if (segment.isFinal) {
      _finalSegments = [..._finalSegments, _finalizeTranscriptSegment(segment)];
      _partial = null;
    } else {
      _partial = segment.text;
    }
    _publishTranscriptSegments();
    if (segment.isFinal && segment.hasText) {
      unawaited(_requestRealtimeStructuring());
    }
  }

  Future<void> _requestRealtimeStructuring() {
    _realtimeStructuringRequested = true;
    final running = _realtimeStructuringTask;
    if (running != null) {
      return running;
    }

    late final Future<void> task;
    task = _drainRealtimeStructuring().whenComplete(() {
      if (identical(_realtimeStructuringTask, task)) {
        _realtimeStructuringTask = null;
      }
      if (_realtimeStructuringRequested) {
        unawaited(_requestRealtimeStructuring());
      }
    });
    _realtimeStructuringTask = task;
    return task;
  }

  Future<void> _drainRealtimeStructuring() async {
    _updateCapture((current) => current.copyWith(isStructuring: true));
    try {
      while (_realtimeStructuringRequested) {
        _realtimeStructuringRequested = false;
        await _structureRealtimeSnapshot();
      }
    } finally {
      _updateCapture((current) => current.copyWith(isStructuring: false));
    }
  }

  Future<void> _structureRealtimeSnapshot() async {
    if (_inferUnknownTranscriptSpeakers()) {
      _publishTranscriptSegments(updateDraftTranscript: true);
    }
    var transcriptText = formatTranscriptSegmentsForStructuring(_finalSegments);
    if (transcriptText.trim().isEmpty) {
      return;
    }
    final structuringInput = buildQsoStructuringInput(
      transcriptText,
      ownCallsign: ref.read(callsignProvider),
      ownQth: ref.read(qthProvider),
    );
    final current = await future;
    final dateTime = current.currentDraft.dateTime.value;
    final factory = _realtimeDraftFactory;
    QsoDraft patch;
    try {
      patch = factory == null
          ? await ref
                .read(qsoIntakeServiceProvider)
                .reviewDraftFromText(structuringInput, dateTime: dateTime)
          : await factory(structuringInput, dateTime);
    } catch (error) {
      final message = error.toString();
      _realtimeStructuringFailure = message;
      _updateCapture((latest) {
        final showWarning =
            ref.read(failureHandlingProvider) == FailureHandling.alert;
        return latest.copyWith(
          currentDraft: latest.currentDraft.copyWith(
            rawTranscript: transcriptText,
            status: LogStatus.needsReview,
            errorMessage: message,
          ),
          warningMessage: showWarning ? message : null,
          clearWarning: !showWarning,
        );
      });
      return;
    }

    patch = _removeOwnCallsign(patch);
    _inferUnknownTranscriptSpeakers(otherCallsign: patch.callsign.value);
    final counterpartyFields = _sanitizeCounterpartyFields(patch);
    patch = counterpartyFields.patch;
    transcriptText = formatTranscriptSegmentsForStructuring(_finalSegments);
    _realtimeStructuringFailure = patch.errorMessage;
    _updateCapture((latest) {
      final currentName = latest.currentDraft.name;
      final currentQth = latest.currentDraft.qth;
      final draft = _mergeRealtimeDraft(
        latest.currentDraft,
        patch,
        rawText: transcriptText,
        clearName:
            counterpartyFields.clearName &&
            currentName != null &&
            _counterpartyFieldSource(currentName, isQth: false) ==
                _CounterpartyFieldSource.self,
        clearQth:
            counterpartyFields.clearQth &&
            currentQth != null &&
            _counterpartyFieldSource(currentQth, isQth: true) ==
                _CounterpartyFieldSource.self,
      );
      final showWarning =
          patch.errorMessage != null &&
          ref.read(failureHandlingProvider) == FailureHandling.alert;
      return latest.copyWith(
        currentDraft: draft,
        transcriptSegments: _visibleTranscriptSegments(),
        warningMessage: showWarning ? patch.errorMessage : null,
        clearWarning: !showWarning,
      );
    });
  }

  Future<void> _waitForRealtimeStructuring() async {
    while (true) {
      if (_realtimeStructuringRequested) {
        await _requestRealtimeStructuring();
        continue;
      }
      final running = _realtimeStructuringTask;
      if (running == null) {
        return;
      }
      await running;
    }
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

  // ponytail: Qwen does not return word timestamps, so the final event boundary
  // is approximated from PCM bytes sent since the previous final event.
  TranscriptSegment _finalizeTranscriptSegment(TranscriptSegment segment) {
    final audio = _takeSegmentAudio();
    final id = 'stream_${_segmentSeq++}';
    final duration = audio.duration;
    final startOffset = duration == null ? null : _segmentTimelineOffset;
    final endOffset = duration == null
        ? null
        : _segmentTimelineOffset + duration;
    if (endOffset != null) {
      _segmentTimelineOffset = endOffset;
    }
    return segment.copyWith(
      id: id,
      speaker: TranscriptSpeaker.unknown,
      duration: duration,
      startOffset: startOffset,
      endOffset: endOffset,
    );
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
    unawaited(_requestRealtimeStructuring());
  }

  void editCurrentDraftField(QsoFieldKey key, String value) {
    final trimmed = value.trim();
    _updateCapture((current) {
      final draft = current.currentDraft;
      QsoField<String> edited(QsoField<String> field) =>
          field.copyWith(value: trimmed, userEdited: true, reviewed: true);

      QsoField<String>? editedOptional(QsoField<String>? field) {
        if (trimmed.isEmpty) {
          return null;
        }
        return (field ?? const QsoField(value: '')).copyWith(
          value: trimmed,
          userEdited: true,
          reviewed: true,
        );
      }

      final updated = switch (key) {
        QsoFieldKey.callsign => draft.copyWith(
          callsign: edited(draft.callsign),
        ),
        QsoFieldKey.band => draft.copyWith(band: edited(draft.band)),
        QsoFieldKey.frequency => draft.copyWith(
          frequency: edited(draft.frequency),
        ),
        QsoFieldKey.mode => draft.copyWith(mode: edited(draft.mode)),
        QsoFieldKey.sentRst => draft.copyWith(sentRst: edited(draft.sentRst)),
        QsoFieldKey.receivedRst => draft.copyWith(
          receivedRst: edited(draft.receivedRst),
        ),
        QsoFieldKey.name => draft.copyWith(
          name: editedOptional(draft.name),
          clearName: trimmed.isEmpty,
        ),
        QsoFieldKey.qth => draft.copyWith(
          qth: editedOptional(draft.qth),
          clearQth: trimmed.isEmpty,
        ),
        QsoFieldKey.notes => draft.copyWith(
          notes: editedOptional(draft.notes),
          clearNotes: trimmed.isEmpty,
        ),
        QsoFieldKey.rig => draft.copyWith(
          rig: editedOptional(draft.rig),
          clearRig: trimmed.isEmpty,
        ),
        QsoFieldKey.antenna => draft.copyWith(
          antenna: editedOptional(draft.antenna),
          clearAntenna: trimmed.isEmpty,
        ),
        QsoFieldKey.power => draft.copyWith(
          power: editedOptional(draft.power),
          clearPower: trimmed.isEmpty,
        ),
        QsoFieldKey.dateTime => throw ArgumentError.value(
          key,
          'key',
          'Use editCurrentDraftDateTime for dateTime',
        ),
      };
      return current.copyWith(currentDraft: updated);
    });
  }

  void editCurrentDraftDateTime(DateTime value) {
    _updateCapture((current) {
      final draft = current.currentDraft;
      return current.copyWith(
        currentDraft: draft.copyWith(
          dateTime: draft.dateTime.copyWith(
            value: value,
            userEdited: true,
            reviewed: true,
          ),
        ),
      );
    });
  }

  void reviewCurrentDraftField(QsoFieldKey key) {
    _updateCapture((current) {
      final draft = current.currentDraft;
      QsoField<T> reviewed<T>(QsoField<T> field) =>
          field.copyWith(reviewed: true);

      final updated = switch (key) {
        QsoFieldKey.callsign => draft.copyWith(
          callsign: reviewed(draft.callsign),
        ),
        QsoFieldKey.dateTime => draft.copyWith(
          dateTime: reviewed(draft.dateTime),
        ),
        QsoFieldKey.band => draft.copyWith(band: reviewed(draft.band)),
        QsoFieldKey.frequency => draft.copyWith(
          frequency: reviewed(draft.frequency),
        ),
        QsoFieldKey.mode => draft.copyWith(mode: reviewed(draft.mode)),
        QsoFieldKey.sentRst => draft.copyWith(sentRst: reviewed(draft.sentRst)),
        QsoFieldKey.receivedRst => draft.copyWith(
          receivedRst: reviewed(draft.receivedRst),
        ),
        QsoFieldKey.name =>
          draft.name == null
              ? draft
              : draft.copyWith(name: reviewed(draft.name!)),
        QsoFieldKey.qth =>
          draft.qth == null ? draft : draft.copyWith(qth: reviewed(draft.qth!)),
        QsoFieldKey.notes =>
          draft.notes == null
              ? draft
              : draft.copyWith(notes: reviewed(draft.notes!)),
        QsoFieldKey.rig =>
          draft.rig == null ? draft : draft.copyWith(rig: reviewed(draft.rig!)),
        QsoFieldKey.antenna =>
          draft.antenna == null
              ? draft
              : draft.copyWith(antenna: reviewed(draft.antenna!)),
        QsoFieldKey.power =>
          draft.power == null
              ? draft
              : draft.copyWith(power: reviewed(draft.power!)),
      };
      return current.copyWith(currentDraft: updated);
    });
  }

  void _publishTranscriptSegments({bool updateDraftTranscript = false}) {
    final visibleSegments = _visibleTranscriptSegments();
    _updateCapture((state) {
      if (!updateDraftTranscript) {
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

  List<TranscriptSegment> _visibleTranscriptSegments() => [
    ..._finalSegments,
    if (_partial != null && _partial!.trim().isNotEmpty)
      TranscriptSegment(
        speaker: TranscriptSpeaker.unknown,
        text: _partial!,
        isFinal: false,
      ),
  ];

  bool _inferUnknownTranscriptSpeakers({String? otherCallsign}) {
    final ownCallsign = ref.read(callsignProvider);
    final currentOtherCallsign = state.maybeWhen(
      data: (capture) => capture.currentDraft.callsign.value,
      orElse: () => '',
    );
    final resolvedOtherCallsign = otherCallsign?.trim().isNotEmpty == true
        ? otherCallsign!
        : currentOtherCallsign;
    var changed = false;
    _finalSegments = [
      for (final segment in _finalSegments)
        if (segment.speaker != TranscriptSpeaker.unknown)
          segment
        else
          (() {
            final speaker = _inferTranscriptSpeaker(
              segment.text,
              ownCallsign: ownCallsign,
              otherCallsign: resolvedOtherCallsign,
            );
            changed |= speaker != TranscriptSpeaker.unknown;
            return speaker == TranscriptSpeaker.unknown
                ? segment
                : segment.copyWith(speaker: speaker);
          })(),
    ];
    return changed;
  }

  QsoDraft _removeOwnCallsign(QsoDraft patch) {
    final ownCallsign = ref.read(callsignProvider);
    if (!callsignsMatch(patch.callsign.value, ownCallsign)) {
      return patch;
    }
    return patch.copyWith(callsign: const QsoField(value: '', confidence: 0.2));
  }

  ({QsoDraft patch, bool clearName, bool clearQth}) _sanitizeCounterpartyFields(
    QsoDraft patch,
  ) {
    final name = _sanitizeCounterpartyField(patch.name);
    final qth = _sanitizeCounterpartyField(patch.qth, isQth: true);
    return (
      patch: patch.copyWith(
        name: name.field,
        qth: qth.field,
        clearName: name.discard,
        clearQth: qth.discard,
      ),
      clearName: name.discard,
      clearQth: qth.discard,
    );
  }

  ({QsoField<String>? field, bool discard}) _sanitizeCounterpartyField(
    QsoField<String>? field, {
    bool isQth = false,
  }) {
    if (field == null || field.value.trim().isEmpty) {
      return (field: field, discard: false);
    }
    return switch (_counterpartyFieldSource(field, isQth: isQth)) {
      _CounterpartyFieldSource.self => (field: null, discard: true),
      _CounterpartyFieldSource.other => (field: field, discard: false),
      _CounterpartyFieldSource.uncertain => (
        field: field.copyWith(
          confidence: field.confidence < 0.75 ? field.confidence : 0.74,
          userEdited: false,
          reviewed: false,
        ),
        discard: false,
      ),
    };
  }

  _CounterpartyFieldSource _counterpartyFieldSource(
    QsoField<String> field, {
    required bool isQth,
  }) {
    final sourceText = field.sourceText?.trim();
    if (sourceText == null || sourceText.isEmpty) {
      return _CounterpartyFieldSource.uncertain;
    }

    final explicitSources = <_CounterpartyFieldSource>{
      if (sourceText.contains('[我方资料]') || sourceText.contains('[我方]'))
        _CounterpartyFieldSource.self,
      if (sourceText.contains('[对方]')) _CounterpartyFieldSource.other,
      if (sourceText.contains('[待确认]')) _CounterpartyFieldSource.uncertain,
    };
    if (explicitSources.isNotEmpty) {
      return explicitSources.length == 1
          ? explicitSources.single
          : _CounterpartyFieldSource.uncertain;
    }

    final matchedSpeakers = <TranscriptSpeaker>{
      for (final segment in _finalSegments)
        if (segment.hasText && _sourceMatchesSegment(sourceText, segment.text))
          segment.speaker,
    };
    if (matchedSpeakers.isEmpty &&
        isQth &&
        _matchesOwnQthContext(field.value, sourceText)) {
      matchedSpeakers.add(TranscriptSpeaker.self);
    }
    if (matchedSpeakers.length != 1 ||
        matchedSpeakers.contains(TranscriptSpeaker.unknown)) {
      return _CounterpartyFieldSource.uncertain;
    }
    return matchedSpeakers.single == TranscriptSpeaker.self
        ? _CounterpartyFieldSource.self
        : _CounterpartyFieldSource.other;
  }

  bool _matchesOwnQthContext(String value, String sourceText) {
    final ownQth = ref.read(qthProvider).trim();
    if (ownQth.isEmpty || value.trim().toLowerCase() != ownQth.toLowerCase()) {
      return false;
    }
    return RegExp(r'\bqth\s*=', caseSensitive: false).hasMatch(sourceText);
  }

  bool _sourceMatchesSegment(String sourceText, String segmentText) {
    final source = _normalizeSourceEvidence(sourceText);
    final segment = _normalizeSourceEvidence(segmentText);
    return source.isNotEmpty &&
        segment.isNotEmpty &&
        (segment.contains(source) || source.contains(segment));
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

  /// 停止流式转写，等待最后一轮实时结构化完成后返回可复核草稿。
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
            speaker: TranscriptSpeaker.unknown,
            text: _partial!.trim(),
            isFinal: true,
          ),
        ),
      ];
      _partial = null;
      _publishTranscriptSegments();
      unawaited(_requestRealtimeStructuring());
    }
    if (_segmentAudio.length > 0) {
      _addUnrecognizedSegment();
    }
    final rawText = formatTranscriptSegmentsForStructuring(_finalSegments);
    final hasTranscript = rawText.trim().isNotEmpty;
    if (hasTranscript) {
      await _requestRealtimeStructuring();
      await _waitForRealtimeStructuring();
    }
    final latest = await future;
    final latestRawText = hasTranscript
        ? formatTranscriptSegmentsForStructuring(_finalSegments)
        : null;
    final persistedSegments = [
      for (final segment in _finalSegments)
        if (segment.isFinal)
          segment.copyWith(
            audioPath: audioPath,
            clearAudioPath: audioPath == null,
          ),
    ];
    var draft = latest.currentDraft.copyWith(
      audioPath: audioPath,
      rawTranscript: latestRawText,
      clearRawTranscript: !hasTranscript,
      transcriptSegments: persistedSegments,
      dateTime: latest.currentDraft.dateTime.copyWith(
        value: startedAt ?? latest.currentDraft.dateTime.value,
      ),
      status: hasTranscript ? LogStatus.needsReview : LogStatus.failed,
      errorMessage: hasTranscript
          ? _streamingFailure ?? _realtimeStructuringFailure
          : _streamingFailure ?? 'no_streaming_transcript',
      clearErrorMessage:
          hasTranscript &&
          _streamingFailure == null &&
          _realtimeStructuringFailure == null,
    );
    if (!hasTranscript) {
      final showWarning =
          ref.read(failureHandlingProvider) == FailureHandling.alert;
      state = AsyncData(
        latest.copyWith(
          currentDraft: draft,
          isStructuring: false,
          warningMessage: showWarning ? 'no_streaming_transcript' : null,
          clearWarning: !showWarning,
        ),
      );
      return draft;
    }
    final retentionApplier = _recognitionRetentionApplier;
    draft = retentionApplier == null
        ? await ref
              .read(qsoIntakeServiceProvider)
              .applyRecognitionRetention(draft)
        : await retentionApplier(draft);
    state = AsyncData(
      latest.copyWith(currentDraft: draft, isStructuring: false),
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
        final factory = _afterQsoDraftFactory;
        final recognized = factory == null
            ? await ref
                  .read(qsoIntakeServiceProvider)
                  .reviewDraftFromAudio(
                    audioPath: audioPath,
                    startedAt: startedAt,
                  )
            : await factory(audioPath, startedAt);
        final draft = _mergeStructuredFields(current.currentDraft, recognized)
            .copyWith(
              audioPath: recognized.audioPath,
              clearAudioPath: recognized.audioPath == null,
              originalAudioDeleted: recognized.originalAudioDeleted,
              rawTranscript: recognized.rawTranscript,
              clearRawTranscript: recognized.rawTranscript == null,
              transcriptSegments: recognized.transcriptSegments,
              status: recognized.status,
              errorMessage: recognized.errorMessage,
              clearErrorMessage: recognized.errorMessage == null,
            );
        state = AsyncData(
          QsoCaptureState(
            currentDraft: draft,
            transcriptSegments: draft.transcriptSegments,
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

    // 流式模式的收尾已交由 stopQsoStreaming 负责；
    // 此处委托以消除重复实现与不可达分支。
    return stopQsoStreaming(audioPath: audioPath, startedAt: startedAt);
  }

  QsoDraft _emptyDraft({DateTime? dateTime, QsoDraft? inheritedFrom}) {
    QsoField<String> inheritedRequired(QsoField<String>? field) {
      final value = field?.value.trim() ?? '';
      return QsoField(value: value, confidence: value.isEmpty ? 0.2 : 1);
    }

    QsoField<String>? inheritedOptional(QsoField<String>? field) {
      final value = field?.value.trim() ?? '';
      return value.isEmpty ? null : QsoField(value: value);
    }

    return QsoDraft(
      callsign: const QsoField(value: '', confidence: 0.2),
      dateTime: QsoField(
        value: dateTime,
        confidence: dateTime == null ? 0.2 : 1,
      ),
      band: inheritedRequired(inheritedFrom?.band),
      frequency: inheritedRequired(inheritedFrom?.frequency),
      mode: inheritedRequired(inheritedFrom?.mode),
      sentRst: const QsoField(value: '', confidence: 0.2),
      receivedRst: const QsoField(value: '', confidence: 0.2),
      status: LogStatus.draft,
      rig: inheritedOptional(inheritedFrom?.rig),
      antenna: inheritedOptional(inheritedFrom?.antenna),
      power: inheritedOptional(inheritedFrom?.power),
    );
  }
}

TranscriptSpeaker _inferTranscriptSpeaker(
  String text, {
  required String ownCallsign,
  required String otherCallsign,
}) {
  final claimsOwn = _claimsIdentity(text, ownCallsign);
  final claimsOther = _claimsIdentity(text, otherCallsign);
  if (claimsOwn == claimsOther) {
    return TranscriptSpeaker.unknown;
  }
  return claimsOwn ? TranscriptSpeaker.self : TranscriptSpeaker.other;
}

bool _claimsIdentity(String text, String callsign) {
  final identities = callsignIdentities(callsign);
  if (identities.isEmpty) {
    return false;
  }
  final compactText = text.toUpperCase().replaceAll(
    RegExp(r'[^A-Z0-9/\u4e00-\u9fff]'),
    '',
  );
  return ['THISIS', 'IAM', 'HEREIS', 'FROM', '这里是', '我是', '本台是'].any(
    (marker) =>
        identities.any((identity) => compactText.contains('$marker$identity')),
  );
}

String _normalizeSourceEvidence(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

enum _CounterpartyFieldSource { self, other, uncertain }

final qsoCaptureProvider =
    AsyncNotifierProvider<QsoCaptureNotifier, QsoCaptureState>(
      QsoCaptureNotifier.new,
    );

QsoDraft _mergeRealtimeDraft(
  QsoDraft current,
  QsoDraft patch, {
  required String rawText,
  bool clearName = false,
  bool clearQth = false,
}) {
  final merged = _mergeStructuredFields(current, patch);
  final canClearName =
      clearName &&
      current.name?.userEdited != true &&
      current.name?.reviewed != true;
  final canClearQth =
      clearQth &&
      current.qth?.userEdited != true &&
      current.qth?.reviewed != true;
  return merged.copyWith(
    status: LogStatus.needsReview,
    rawTranscript: rawText,
    errorMessage: patch.errorMessage,
    clearErrorMessage: patch.errorMessage == null,
    clearName: canClearName,
    clearQth: canClearQth,
  );
}

QsoDraft _mergeStructuredFields(QsoDraft current, QsoDraft patch) {
  QsoField<String> mergeRequired(
    QsoField<String> existing,
    QsoField<String> incoming,
  ) => existing.userEdited || existing.reviewed || incoming.value.trim().isEmpty
      ? existing
      : incoming;

  QsoField<String>? mergeOptional(
    QsoField<String>? existing,
    QsoField<String>? incoming,
  ) =>
      existing?.userEdited == true ||
          existing?.reviewed == true ||
          incoming == null ||
          incoming.value.trim().isEmpty
      ? existing
      : incoming;

  return current.copyWith(
    callsign: mergeRequired(current.callsign, patch.callsign),
    dateTime: current.dateTime,
    band: mergeRequired(current.band, patch.band),
    frequency: mergeRequired(current.frequency, patch.frequency),
    mode: mergeRequired(current.mode, patch.mode),
    sentRst: mergeRequired(current.sentRst, patch.sentRst),
    receivedRst: mergeRequired(current.receivedRst, patch.receivedRst),
    name: mergeOptional(current.name, patch.name),
    qth: mergeOptional(current.qth, patch.qth),
    notes: mergeOptional(current.notes, patch.notes),
    rig: mergeOptional(current.rig, patch.rig),
    antenna: mergeOptional(current.antenna, patch.antenna),
    power: mergeOptional(current.power, patch.power),
  );
}

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
    state = await AsyncValue.guard(() async {
      final qsos = await ref.read(qsoRepositoryProvider).listQsos(query);
      final session = ref.read(qsoSessionProvider.notifier);
      for (final qso in qsos) {
        session.updateIfPresent(qso);
      }
      return qsos;
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
    ref
        .read(qsoSessionProvider.notifier)
        .updateIfPresent(qsoToSave.copyWith(id: id));
    await refresh();
    ref.invalidate(localDataSummaryProvider);
    return id;
  }

  Future<String> saveAndRecordInSession(QsoDraft qso) async {
    final id = await save(qso);
    final saved = await ref.read(qsoRepositoryProvider).findQso(id);
    if (saved == null) {
      throw StateError('saved_qso_missing');
    }
    ref.read(qsoSessionProvider.notifier).record(saved);
    return id;
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
    required List<TranscriptSegment> transcriptSegments,
  }) async {
    await ref
        .read(qsoRepositoryProvider)
        .setRawTranscript(
          qsoId,
          rawTranscript,
          transcriptSegments: transcriptSegments,
        );
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
