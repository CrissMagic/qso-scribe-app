import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
}) {
  return ProviderContainer(
    overrides: [
      audioCaptureServiceProvider.overrideWithValue(audio),
      failureHandlingProvider.overrideWithValue(failureHandling),
      qsoCaptureProvider.overrideWith(
        () => QsoCaptureNotifier(
          streamingProviderResolver: () async => streaming,
        ),
      ),
    ],
  );
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
}
