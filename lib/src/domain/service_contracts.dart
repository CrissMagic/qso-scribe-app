import 'dart:async';

import 'app_models.dart';

class AudioFrame {
  const AudioFrame({
    required this.bytes,
    required this.sampleRate,
    required this.channels,
    required this.timestamp,
  });

  final List<int> bytes;
  final int sampleRate;
  final int channels;
  final DateTime timestamp;
}

abstract interface class AudioCaptureService {
  Stream<AudioFrame> get frames;

  Future<void> start();

  Future<String?> stop();
}

class SpeechProviderCapabilities {
  const SpeechProviderCapabilities({
    required this.supportsStreaming,
    required this.supportsPartialResult,
    required this.supportsFinalSegment,
    required this.preferredSampleRate,
    required this.acceptedEncoding,
    required this.requiresManualCommit,
  });

  final bool supportsStreaming;
  final bool supportsPartialResult;
  final bool supportsFinalSegment;
  final int preferredSampleRate;
  final String acceptedEncoding;
  final bool requiresManualCommit;
}

class SpeechSessionConfig {
  const SpeechSessionConfig({
    required this.providerId,
    required this.modelId,
    required this.mode,
  });

  final String providerId;
  final String modelId;
  final TranscriptionMode mode;
}

abstract interface class SpeechTranscriptionProvider {
  SpeechProviderCapabilities get capabilities;

  Stream<TranscriptSegment> get transcriptEvents;

  Future<void> startSession(SpeechSessionConfig config);

  Future<void> sendAudioFrame(AudioFrame frame);

  Future<void> commit();

  Future<void> stop();
}

class QsoDraftPatch {
  const QsoDraftPatch({
    required this.updatedFields,
    required this.sourceSegment,
  });

  final Map<String, Object?> updatedFields;
  final TranscriptSegment sourceSegment;
}

abstract interface class QsoStructuringService {
  Future<QsoDraftPatch> applyTranscript(
    TranscriptSegment segment,
    QsoDraft currentDraft,
  );
}
