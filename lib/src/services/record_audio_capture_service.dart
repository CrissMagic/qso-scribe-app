import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../domain/service_contracts.dart';

class RecordAudioCaptureService implements AudioCaptureService {
  RecordAudioCaptureService({
    AudioRecorder? recorder,
    this.sampleRate = 16000,
    this.channels = 1,
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final int sampleRate;
  final int channels;
  final _frames = StreamController<AudioFrame>.broadcast();

  StreamSubscription<Uint8List>? _subscription;
  IOSink? _audioSink;
  String? _audioPath;
  bool _isRecording = false;

  @override
  Stream<AudioFrame> get frames => _frames.stream;

  String? get currentAudioPath => _audioPath;

  @override
  Future<void> start() async {
    if (_isRecording) {
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('microphone_permission_denied');
    }

    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(dir.path, 'audio'));
    if (!audioDir.existsSync()) {
      await audioDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
    _audioPath = p.join(audioDir.path, 'qso_$timestamp.pcm');
    _audioSink = File(_audioPath!).openWrite();

    final stream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: channels,
        streamBufferSize: 4096,
      ),
    );

    _subscription = stream.listen((bytes) {
      _audioSink?.add(bytes);
      _frames.add(
        AudioFrame(
          bytes: bytes,
          sampleRate: sampleRate,
          channels: channels,
          timestamp: DateTime.now(),
        ),
      );
    }, onError: _frames.addError);
    _isRecording = true;
  }

  @override
  Future<String?> stop() async {
    if (!_isRecording) {
      return _audioPath;
    }

    await _recorder.stop();
    await _subscription?.cancel();
    _subscription = null;
    await _audioSink?.flush();
    await _audioSink?.close();
    _audioSink = null;
    _isRecording = false;
    return _audioPath;
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
    await _recorder.dispose();
  }
}
