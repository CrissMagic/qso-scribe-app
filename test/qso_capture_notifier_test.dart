import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:qso_scribe_app/src/data/qso_repository.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:qso_scribe_app/src/domain/service_contracts.dart';
import 'package:qso_scribe_app/src/state/app_state.dart';

void main() {
  test('实时连接就绪并订阅音频后才启动录音，首帧不会丢失', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    final container = _captureContainer(audio, streaming);
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    final started = await container
        .read(qsoCaptureProvider.notifier)
        .startRecordingQso(mode: TranscriptionMode.streaming);

    final session = container.read(recordingSessionProvider);
    final capture = await container.read(qsoCaptureProvider.future);
    expect(started, isTrue);
    expect(session.isRecording, isTrue);
    expect(capture.currentDraft.dateTime.value, session.startedAt);
    expect(events, [
      'streaming.startSession',
      'audio.start',
      'streaming.sendAudioFrame',
    ]);
  });

  test('final 转写在录音中实时更新当前 QSO 草稿', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    final structuredInputs = <String>[];
    final container = _captureContainer(
      audio,
      streaming,
      realtimeDraftFactory: (rawText, dateTime) async {
        structuredInputs.add(rawText);
        return _structuredDraft(
          callsign: 'K1ABC',
          dateTime: dateTime,
          rawTranscript: rawText,
        );
      },
    );
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    await container
        .read(qsoCaptureProvider.notifier)
        .startRecordingQso(mode: TranscriptionMode.streaming);
    streaming.addFinal('K1ABC five nine');
    await Future<void>.delayed(Duration.zero);

    final capture = await container.read(qsoCaptureProvider.future);
    expect(structuredInputs, ['[对方] K1ABC five nine']);
    expect(capture.currentDraft.callsign.value, 'K1ABC');
    expect(capture.currentDraft.callsign.confidence, 0.6);
    expect(capture.currentDraft.rawTranscript, '[对方] K1ABC five nine');
  });

  test('用户编辑过的实时字段不会被后续 AI patch 覆盖', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    var callCount = 0;
    final container = _captureContainer(
      audio,
      streaming,
      realtimeDraftFactory: (rawText, dateTime) async {
        callCount += 1;
        return _structuredDraft(
          callsign: callCount == 1 ? 'K1ABC' : 'K2XYZ',
          dateTime: dateTime,
          rawTranscript: rawText,
        );
      },
    );
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    final notifier = container.read(qsoCaptureProvider.notifier);
    await notifier.startRecordingQso(mode: TranscriptionMode.streaming);
    streaming.addFinal('K1ABC five nine');
    await _waitUntil(() => callCount == 1);

    notifier.editCurrentDraftField(QsoFieldKey.callsign, 'N0CALL');
    streaming.addFinal('correction K2XYZ');
    await _waitUntil(() => callCount == 2);

    final callsign = (await container.read(
      qsoCaptureProvider.future,
    )).currentDraft.callsign;
    expect(callsign.value, 'N0CALL');
    expect(callsign.confidence, 0.6);
    expect(callsign.userEdited, isTrue);
    expect(callsign.reviewed, isTrue);
  });

  test('明确确认过的实时字段不会被后续 AI patch 覆盖', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    var callCount = 0;
    final container = _captureContainer(
      audio,
      streaming,
      realtimeDraftFactory: (rawText, dateTime) async {
        callCount += 1;
        return _structuredDraft(
          callsign: callCount == 1 ? 'K1ABC' : 'K2XYZ',
          dateTime: dateTime,
          rawTranscript: rawText,
        );
      },
    );
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    final notifier = container.read(qsoCaptureProvider.notifier);
    await notifier.startRecordingQso(mode: TranscriptionMode.streaming);
    streaming.addFinal('K1ABC five nine');
    await _waitUntil(() => callCount == 1);

    notifier.reviewCurrentDraftField(QsoFieldKey.callsign);
    streaming.addFinal('correction K2XYZ');
    await _waitUntil(() => callCount == 2);

    final callsign = (await container.read(
      qsoCaptureProvider.future,
    )).currentDraft.callsign;
    expect(callsign.value, 'K1ABC');
    expect(callsign.confidence, 0.6);
    expect(callsign.userEdited, isFalse);
    expect(callsign.reviewed, isTrue);
  });

  test('实时结构化单飞执行，并把请求期间的新 final 合并到下一轮', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    final inputs = <String>[];
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final firstResult = Completer<QsoDraft>();
    final secondResult = Completer<QsoDraft>();
    final container = _captureContainer(
      audio,
      streaming,
      realtimeDraftFactory: (rawText, dateTime) {
        inputs.add(rawText);
        if (inputs.length == 1) {
          firstStarted.complete();
          return firstResult.future;
        }
        secondStarted.complete();
        return secondResult.future;
      },
    );
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    await container
        .read(qsoCaptureProvider.notifier)
        .startRecordingQso(mode: TranscriptionMode.streaming);
    streaming.addFinal('K1ABC');
    await firstStarted.future;

    streaming.addFinal('five nine');
    await Future<void>.delayed(Duration.zero);
    expect(inputs, ['[对方] K1ABC']);

    firstResult.complete(
      _structuredDraft(
        callsign: 'K1ABC',
        dateTime: null,
        rawTranscript: inputs.first,
      ),
    );
    await secondStarted.future;
    expect(inputs, ['[对方] K1ABC', '[对方] K1ABC\n[对方] five nine']);

    secondResult.complete(
      _structuredDraft(
        callsign: 'K1ABC',
        dateTime: null,
        rawTranscript: inputs.last,
      ),
    );
    await _waitUntil(
      () => container.read(qsoCaptureProvider).value?.isStructuring == false,
    );
  });

  test('停止实时录音会等待最后一轮结构化并直接返回复核草稿', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    final structuringStarted = Completer<void>();
    final structuringResult = Completer<QsoDraft>();
    final container = _captureContainer(
      audio,
      streaming,
      realtimeDraftFactory: (rawText, dateTime) {
        structuringStarted.complete();
        return structuringResult.future;
      },
    );
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    final notifier = container.read(qsoCaptureProvider.notifier);
    await notifier.startRecordingQso(mode: TranscriptionMode.streaming);
    streaming.addFinal('K1ABC five nine');
    await structuringStarted.future;

    final recorder = container.read(recordingSessionProvider.notifier);
    final startedAt = container.read(recordingSessionProvider).startedAt;
    final audioPath = await recorder.stop();
    var stopCompleted = false;
    final stopped = notifier
        .stopQsoStreaming(audioPath: audioPath, startedAt: startedAt)
        .whenComplete(() => stopCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopCompleted, isFalse);

    structuringResult.complete(
      _structuredDraft(
        callsign: 'K1ABC',
        dateTime: startedAt,
        rawTranscript: '[对方] K1ABC five nine',
      ),
    );
    final draft = await stopped;

    expect(draft.callsign.value, 'K1ABC');
    expect(draft.dateTime.value, startedAt);
    expect(draft.audioPath, _FakeAudioCaptureService.outputPath);
    expect(draft.status, LogStatus.needsReview);
    expect(
      (await container.read(qsoCaptureProvider.future)).isStructuring,
      isFalse,
    );
  });

  test('运行期会话按首次保存顺序记录 QSO，重复保存只更新原项', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final session = container.read(qsoSessionProvider.notifier);

    session.record(_sessionDraft(id: 'qso-1', status: LogStatus.confirmed));
    session.record(_sessionDraft(id: 'qso-2', status: LogStatus.needsReview));
    session.record(
      _sessionDraft(id: 'qso-1', status: LogStatus.exported, band: '40m'),
    );

    final qsos = container.read(qsoSessionProvider);
    expect(qsos.map((qso) => qso.id), ['qso-1', 'qso-2']);
    expect(qsos.first.status, LogStatus.exported);
    expect(qsos.first.band.value, '40m');
  });

  test('日志保存只同步本次会话中已有的同一条 QSO', () async {
    final repository = _InMemoryQsoRepository();
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWith(_DefaultAppSettingsNotifier.new),
        qsoRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    await container.read(qsoLogProvider.future);

    final session = container.read(qsoSessionProvider.notifier);
    session.record(_sessionDraft(id: 'qso-1', status: LogStatus.confirmed));

    await container
        .read(qsoLogProvider.notifier)
        .save(
          _sessionDraft(id: 'qso-1', status: LogStatus.exported, band: '40m'),
        );
    await container
        .read(qsoLogProvider.notifier)
        .save(_sessionDraft(id: 'qso-2', status: LogStatus.confirmed));

    final qsos = container.read(qsoSessionProvider);
    expect(qsos, hasLength(1));
    expect(qsos.single.id, 'qso-1');
    expect(qsos.single.status, LogStatus.exported);
    expect(qsos.single.band.value, '40m');
  });

  test('新 QSO 只继承最近 confirmed/exported 的指定字段', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    var structured = false;
    final container = _captureContainer(
      audio,
      streaming,
      realtimeDraftFactory: (rawText, dateTime) async {
        structured = true;
        return _structuredDraft(
          callsign: 'K2XYZ',
          dateTime: dateTime,
          rawTranscript: rawText,
          band: '20m',
          rig: 'AI rig',
        );
      },
    );
    addTearDown(container.dispose);
    addTearDown(audio.dispose);
    final session = container.read(qsoSessionProvider.notifier);
    session.record(
      _sessionDraft(
        id: 'qso-1',
        status: LogStatus.confirmed,
        band: '40m',
        rig: 'IC-7300',
      ),
    );
    session.record(
      _sessionDraft(
        id: 'qso-2',
        status: LogStatus.needsReview,
        band: '15m',
        rig: 'unconfirmed rig',
      ),
    );

    await container.read(qsoCaptureProvider.future);
    final notifier = container.read(qsoCaptureProvider.notifier);
    await notifier.startRecordingQso(mode: TranscriptionMode.streaming);
    var draft = (await container.read(qsoCaptureProvider.future)).currentDraft;

    expect(draft.band.value, '40m');
    expect(draft.frequency.value, '7.050');
    expect(draft.mode.value, 'SSB');
    expect(draft.rig?.value, 'IC-7300');
    expect(draft.antenna?.value, 'EFHW');
    expect(draft.power?.value, '100W');
    expect(draft.callsign.value, isEmpty);
    expect(draft.sentRst.value, isEmpty);
    expect(draft.receivedRst.value, isEmpty);
    expect(draft.name, isNull);
    expect(draft.qth, isNull);
    expect(draft.notes, isNull);
    expect(draft.status, LogStatus.draft);
    expect(draft.band.confidence, 1);
    expect(draft.band.userEdited, isFalse);
    expect(draft.band.reviewed, isFalse);

    notifier.editCurrentDraftField(QsoFieldKey.rig, 'FT-710');
    streaming.addFinal('K2XYZ on twenty meters using AI rig');
    await _waitUntil(() => structured);
    draft = (await container.read(qsoCaptureProvider.future)).currentDraft;

    expect(draft.band.value, '20m');
    expect(draft.rig?.value, 'FT-710');
    expect(draft.rig?.userEdited, isTrue);
  });

  test('后置结构化未返回设备字段时保留会话继承值', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(events);
    final container = _captureContainer(
      audio,
      streaming,
      afterQsoDraftFactory: (audioPath, startedAt) async => QsoDraft(
        callsign: const QsoField(value: 'K2XYZ', confidence: 0.8),
        dateTime: QsoField(value: startedAt),
        band: const QsoField(value: '', confidence: 0.2),
        frequency: const QsoField(value: '', confidence: 0.2),
        mode: const QsoField(value: '', confidence: 0.2),
        sentRst: const QsoField(value: '59', confidence: 0.8),
        receivedRst: const QsoField(value: '57', confidence: 0.8),
        status: LogStatus.needsReview,
        audioPath: audioPath,
        rawTranscript: 'K2XYZ five nine',
      ),
    );
    addTearDown(container.dispose);
    addTearDown(audio.dispose);
    container
        .read(qsoSessionProvider.notifier)
        .record(
          _sessionDraft(
            id: 'qso-1',
            status: LogStatus.confirmed,
            band: '40m',
            rig: 'IC-7300',
          ),
        );

    await container.read(qsoCaptureProvider.future);
    final notifier = container.read(qsoCaptureProvider.notifier);
    expect(
      await notifier.startRecordingQso(mode: TranscriptionMode.afterQso),
      isTrue,
    );
    final recorder = container.read(recordingSessionProvider.notifier);
    final startedAt = container.read(recordingSessionProvider).startedAt;
    final audioPath = await recorder.stop();
    final draft = await notifier.finishQso(
      audioPath: audioPath,
      startedAt: startedAt,
      mode: TranscriptionMode.afterQso,
      failureHandling: FailureHandling.alert,
    );

    expect(draft.callsign.value, 'K2XYZ');
    expect(draft.dateTime.value, startedAt);
    expect(draft.band.value, '40m');
    expect(draft.frequency.value, '7.050');
    expect(draft.mode.value, 'SSB');
    expect(draft.rig?.value, 'IC-7300');
    expect(draft.antenna?.value, 'EFHW');
    expect(draft.power?.value, '100W');
    expect(draft.audioPath, _FakeAudioCaptureService.outputPath);
    expect(draft.rawTranscript, 'K2XYZ five nine');
  });

  test('实时连接失败时不启动录音', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(
      events,
      startError: StateError('connect_failed'),
    );
    final container = _captureContainer(audio, streaming);
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    final started = await container
        .read(qsoCaptureProvider.notifier)
        .startRecordingQso(mode: TranscriptionMode.streaming);

    expect(started, isFalse);
    expect(container.read(recordingSessionProvider).isRecording, isFalse);
    expect(
      (await container.read(qsoCaptureProvider.future)).warningMessage,
      'streaming_connection_failed',
    );
    expect(events, ['streaming.startSession', 'streaming.stop']);
  });

  test('实时流在启动阶段已报错时不启动录音', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(
      events,
      streamErrorDuringStart: StateError('closed_after_ready'),
    );
    final container = _captureContainer(audio, streaming);
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    final started = await container
        .read(qsoCaptureProvider.notifier)
        .startRecordingQso(mode: TranscriptionMode.streaming);

    expect(started, isFalse);
    expect(container.read(recordingSessionProvider).isRecording, isFalse);
    expect(events, ['streaming.startSession', 'streaming.stop']);
  });

  test('实时音频帧发送失败时继续本地录音并记录失败', () async {
    final events = <String>[];
    final audio = _FakeAudioCaptureService(events);
    final streaming = _FakeStreamingProvider(
      events,
      sendError: StateError('send_failed'),
    );
    final container = _captureContainer(audio, streaming);
    addTearDown(container.dispose);
    addTearDown(audio.dispose);

    await container.read(qsoCaptureProvider.future);
    final captureNotifier = container.read(qsoCaptureProvider.notifier);
    expect(
      await captureNotifier.startRecordingQso(
        mode: TranscriptionMode.streaming,
      ),
      isTrue,
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(recordingSessionProvider).isRecording, isTrue);

    final recorder = container.read(recordingSessionProvider.notifier);
    final startedAt = container.read(recordingSessionProvider).startedAt;
    final audioPath = await recorder.stop();
    final draft = await captureNotifier.stopQsoStreaming(
      audioPath: audioPath,
      startedAt: startedAt,
    );

    expect(draft.status, LogStatus.failed);
    expect(draft.audioPath, _FakeAudioCaptureService.outputPath);
    expect(draft.errorMessage, contains('send_failed'));
  });

  for (final failureHandling in FailureHandling.values) {
    test('实时中途失败在 ${failureHandling.name} 下继续录音且最终返回 failed', () async {
      final events = <String>[];
      final audio = _FakeAudioCaptureService(events);
      final streaming = _FakeStreamingProvider(events);
      final container = _captureContainer(
        audio,
        streaming,
        failureHandling: failureHandling,
      );
      addTearDown(container.dispose);
      addTearDown(audio.dispose);

      await container.read(qsoCaptureProvider.future);
      final captureNotifier = container.read(qsoCaptureProvider.notifier);
      expect(
        await captureNotifier.startRecordingQso(
          mode: TranscriptionMode.streaming,
        ),
        isTrue,
      );

      streaming.fail(StateError('socket_closed'));
      await Future<void>.delayed(Duration.zero);
      expect(container.read(recordingSessionProvider).isRecording, isTrue);
      expect(
        (await container.read(qsoCaptureProvider.future)).warningMessage,
        failureHandling == FailureHandling.alert
            ? 'no_streaming_transcript'
            : isNull,
      );

      final recorder = container.read(recordingSessionProvider.notifier);
      final startedAt = container.read(recordingSessionProvider).startedAt;
      final audioPath = await recorder.stop();
      final draft = await captureNotifier.stopQsoStreaming(
        audioPath: audioPath,
        startedAt: startedAt,
      );

      expect(draft.status, LogStatus.failed);
      expect(draft.audioPath, _FakeAudioCaptureService.outputPath);
      expect(draft.rawTranscript, isNull);
      expect(draft.errorMessage, contains('socket_closed'));
      expect(events, containsAllInOrder(['audio.start', 'audio.stop']));
    });
  }
}

ProviderContainer _captureContainer(
  _FakeAudioCaptureService audio,
  _FakeStreamingProvider streaming, {
  FailureHandling failureHandling = FailureHandling.alert,
  Future<QsoDraft> Function(String rawText, DateTime? dateTime)?
  realtimeDraftFactory,
  Future<QsoDraft> Function(String audioPath, DateTime? startedAt)?
  afterQsoDraftFactory,
}) {
  return ProviderContainer(
    overrides: [
      audioCaptureServiceProvider.overrideWithValue(audio),
      failureHandlingProvider.overrideWithValue(failureHandling),
      qsoCaptureProvider.overrideWith(
        () => QsoCaptureNotifier(
          streamingProviderResolver: () async => streaming,
          realtimeDraftFactory: realtimeDraftFactory,
          afterQsoDraftFactory: afterQsoDraftFactory,
          recognitionRetentionApplier: (draft) async => draft,
        ),
      ),
    ],
  );
}

class _DefaultAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings.defaults();
}

class _InMemoryQsoRepository extends QsoRepository {
  _InMemoryQsoRepository() : super(AppDatabase());

  final Map<String, QsoDraft> _qsos = {};

  @override
  Future<String> saveQso(QsoDraft qso) async {
    final id = qso.id ?? 'qso-${_qsos.length + 1}';
    _qsos[id] = qso.copyWith(id: id);
    return id;
  }

  @override
  Future<List<QsoDraft>> listQsos([QsoQuery query = const QsoQuery()]) async =>
      _qsos.values.toList();
}

class _FakeAudioCaptureService implements AudioCaptureService {
  _FakeAudioCaptureService(this.events);

  static const outputPath = 'test-output.wav';

  final List<String> events;
  final _frames = StreamController<AudioFrame>.broadcast(sync: true);

  @override
  Stream<AudioFrame> get frames => _frames.stream;

  @override
  Future<void> start() async {
    events.add('audio.start');
    _frames.add(
      AudioFrame(
        bytes: const [1, 2, 3, 4],
        sampleRate: 16000,
        channels: 1,
        timestamp: DateTime(2026, 7, 17),
      ),
    );
  }

  @override
  Future<String?> stop() async {
    events.add('audio.stop');
    return outputPath;
  }

  @override
  Future<void> dispose() => _frames.close();
}

class _FakeStreamingProvider implements SpeechTranscriptionProvider {
  _FakeStreamingProvider(
    this.events, {
    this.startError,
    this.streamErrorDuringStart,
    this.sendError,
  });

  final List<String> events;
  final Object? startError;
  final Object? streamErrorDuringStart;
  final Object? sendError;
  final _transcripts = StreamController<TranscriptSegment>.broadcast(
    sync: true,
  );

  @override
  Stream<TranscriptSegment> get transcriptEvents => _transcripts.stream;

  @override
  Future<void> startSession() async {
    events.add('streaming.startSession');
    final error = startError;
    if (error != null) {
      throw error;
    }
    final streamError = streamErrorDuringStart;
    if (streamError != null) {
      _transcripts.addError(streamError);
    }
  }

  @override
  Future<void> sendAudioFrame(AudioFrame frame) async {
    events.add('streaming.sendAudioFrame');
    final error = sendError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> stop() async {
    events.add('streaming.stop');
  }

  void fail(Object error) => _transcripts.addError(error);

  void addFinal(String text) {
    _transcripts.add(
      TranscriptSegment(
        speaker: TranscriptSpeaker.other,
        text: text,
        isFinal: true,
      ),
    );
  }
}

QsoDraft _structuredDraft({
  required String callsign,
  required DateTime? dateTime,
  required String rawTranscript,
  String band = '20m',
  String? rig,
}) {
  return QsoDraft(
    callsign: QsoField(value: callsign, confidence: 0.6, sourceText: callsign),
    dateTime: QsoField(value: dateTime),
    band: QsoField(value: band, confidence: 0.8),
    frequency: const QsoField(value: '14.250', confidence: 0.8),
    mode: const QsoField(value: 'SSB', confidence: 0.8),
    sentRst: const QsoField(value: '59', confidence: 0.8),
    receivedRst: const QsoField(value: '57', confidence: 0.8),
    rig: rig == null ? null : QsoField(value: rig, confidence: 0.8),
    status: LogStatus.needsReview,
    rawTranscript: rawTranscript,
  );
}

QsoDraft _sessionDraft({
  required String id,
  required LogStatus status,
  String band = '20m',
  String rig = 'IC-7300',
}) {
  return QsoDraft(
    id: id,
    callsign: const QsoField(value: 'K1ABC', reviewed: true),
    dateTime: QsoField(value: DateTime(2026, 7, 17), reviewed: true),
    band: QsoField(value: band, confidence: 0.7, reviewed: true),
    frequency: const QsoField(value: '7.050', reviewed: true),
    mode: const QsoField(value: 'SSB', reviewed: true),
    sentRst: const QsoField(value: '59', reviewed: true),
    receivedRst: const QsoField(value: '57', reviewed: true),
    status: status,
    name: const QsoField(value: 'Alex', reviewed: true),
    qth: const QsoField(value: 'Boston', reviewed: true),
    notes: const QsoField(value: 'Do not inherit', reviewed: true),
    rig: QsoField(value: rig, reviewed: true),
    antenna: const QsoField(value: 'EFHW', reviewed: true),
    power: const QsoField(value: '100W', reviewed: true),
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  fail('condition_not_met');
}
