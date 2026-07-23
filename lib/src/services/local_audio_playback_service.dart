import 'package:flutter/services.dart';

import 'wav_audio.dart';

class LocalAudioPlaybackService {
  LocalAudioPlaybackService({
    MethodChannel channel = const MethodChannel(_channelName),
  }) : _channel = channel;

  static const _channelName = 'qso_scribe/audio_playback';

  final MethodChannel _channel;

  Future<void> play(
    String sourcePath, {
    Duration? startOffset,
    Duration? endOffset,
  }) async {
    if (startOffset?.isNegative == true || endOffset?.isNegative == true) {
      throw ArgumentError('audio offsets cannot be negative');
    }
    if (startOffset != null && endOffset != null && endOffset <= startOffset) {
      throw ArgumentError('audio end offset must be after start offset');
    }
    final playablePath = await playableAudioPathFor(sourcePath);
    await _channel.invokeMethod<void>('play', {
      'path': playablePath,
      if (startOffset != null) 'startMs': startOffset.inMilliseconds,
      if (endOffset != null) 'endMs': endOffset.inMilliseconds,
    });
  }

  Future<void> stop() {
    return _channel.invokeMethod<void>('stop');
  }
}
