import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/services/local_audio_playback_service.dart';

void main() {
  test('rejects an inverted transcript segment range', () async {
    final service = LocalAudioPlaybackService();

    await expectLater(
      service.play(
        'C:\\audio\\qso.wav',
        startOffset: const Duration(seconds: 2),
        endOffset: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
  });
}
