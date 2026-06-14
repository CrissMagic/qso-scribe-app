import 'package:flutter/services.dart';

import 'wav_audio.dart';

class LocalAudioPlaybackService {
  LocalAudioPlaybackService({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const _channelName = 'qso_scribe/audio_playback';

  final MethodChannel _channel;

  Future<void> play(String sourcePath) async {
    final playablePath = await playableAudioPathFor(sourcePath);
    await _channel.invokeMethod<void>('play', {'path': playablePath});
  }

  Future<void> stop() {
    return _channel.invokeMethod<void>('stop');
  }
}
