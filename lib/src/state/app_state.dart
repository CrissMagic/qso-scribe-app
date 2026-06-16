import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/app_database.dart';
import '../data/export_service.dart';
import '../data/export_history_repository.dart';
import '../data/import_repository.dart';
import '../data/model_assignment_repository.dart';
import '../data/model_repository.dart';
import '../data/provider_repository.dart';
import '../data/qso_repository.dart';
import '../data/settings_repository.dart';
import '../domain/app_models.dart';
import '../services/app_update_service.dart';
import '../services/heuristic_qso_structuring_service.dart';
import '../services/local_audio_playback_service.dart';
import '../services/provider_model_fetch_service.dart';
import '../services/qso_processing_service.dart';
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

final exportServiceProvider = Provider<ExportService>(
  (ref) => ExportService(ref.watch(qsoRepositoryProvider)),
);

final providerModelFetchServiceProvider = Provider<ProviderModelFetchService>(
  (ref) => ProviderModelFetchService(),
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
    return QsoCaptureState(currentDraft: _emptyDraft());
  }

  void startQso({
    required TranscriptionMode mode,
    required DateTime startedAt,
  }) {
    final warning = mode == TranscriptionMode.streaming
        ? 'streaming_not_configured'
        : null;
    state = AsyncData(
      QsoCaptureState(
        currentDraft: _emptyDraft(dateTime: startedAt),
        warningMessage: warning,
      ),
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

    final rawText = current.transcriptSegments
        .where((segment) => segment.text.trim().isNotEmpty)
        .map((segment) => segment.text.trim())
        .join('\n');
    final draft = rawText.isEmpty
        ? current.currentDraft.copyWith(
            audioPath: audioPath,
            status: LogStatus.needsReview,
          )
        : ref
              .read(qsoStructuringServiceProvider)
              .createDraftFromText(
                rawText: rawText,
                audioPath: audioPath,
                dateTime: startedAt,
              );
    final retainedDraft = await _applyRecognitionRetention(draft);
    state = AsyncData(
      current.copyWith(
        currentDraft: retainedDraft,
        warningMessage: rawText.isEmpty ? 'no_streaming_transcript' : null,
      ),
    );
    return retainedDraft;
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
