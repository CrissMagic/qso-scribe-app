import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../domain/service_contracts.dart';
import 'wav_audio.dart';

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
  RandomAccessFile? _audioFile;
  String? _audioPath;
  int _audioByteCount = 0;
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
    _audioPath = p.join(audioDir.path, 'qso_$timestamp.wav');
    _audioByteCount = 0;
    _audioFile = await File(_audioPath!).open(mode: FileMode.write);
    await _audioFile!.writeFrom(
      wavHeader(dataLength: 0, sampleRate: sampleRate, channels: channels),
    );

    late final Stream<Uint8List> stream;
    try {
      stream = await _recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: channels,
          streamBufferSize: 4096,
        ),
      );
    } catch (_) {
      await _audioFile?.close();
      _audioFile = null;
      rethrow;
    }

    _subscription = stream.listen((bytes) {
      _audioFile?.writeFromSync(bytes);
      _audioByteCount += bytes.length;
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
    final audioFile = _audioFile;
    if (audioFile != null) {
      await audioFile.setPosition(0);
      await audioFile.writeFrom(
        wavHeader(
          dataLength: _audioByteCount,
          sampleRate: sampleRate,
          channels: channels,
        ),
      );
      await audioFile.flush();
      await audioFile.close();
    }
    _audioFile = null;
    _isRecording = false;
    return _audioPath;
  }

  Future<void> dispose() async {
    await stop();
    await _frames.close();
    await _recorder.dispose();
  }
}
