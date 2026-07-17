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

  Future<void> dispose();
}

abstract interface class SpeechTranscriptionProvider {
  Stream<TranscriptSegment> get transcriptEvents;

  Future<void> startSession();

  Future<void> sendAudioFrame(AudioFrame frame);

  Future<void> stop();
}
