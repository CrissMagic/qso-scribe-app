import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/services/wav_audio.dart';

void main() {
  test('writes a standard PCM WAV header', () {
    final header = wavHeader(dataLength: 3200, sampleRate: 16000, channels: 1);

    expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(header.sublist(12, 16)), 'fmt ');
    expect(String.fromCharCodes(header.sublist(36, 40)), 'data');
    expect(_uint32(header, 4), 3236);
    expect(_uint16(header, 20), 1);
    expect(_uint16(header, 22), 1);
    expect(_uint32(header, 24), 16000);
    expect(_uint32(header, 28), 32000);
    expect(_uint16(header, 32), 2);
    expect(_uint16(header, 34), 16);
    expect(_uint32(header, 40), 3200);
  });

  test('wraps legacy pcm files in a playable wav sidecar', () async {
    final tempDir = await Directory.systemTemp.createTemp('qso_wav_test_');
    addTearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    final pcm = File('${tempDir.path}/qso.pcm');
    await pcm.writeAsBytes([1, 0, 2, 0, 3, 0, 4, 0]);

    final playablePath = await playableAudioPathFor(pcm.path);
    final playable = File(playablePath);
    final bytes = await playable.readAsBytes();

    expect(playablePath.endsWith('.wav'), isTrue);
    expect(bytes.length, 52);
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(_uint32(bytes, 40), 8);
    expect(bytes.sublist(44), [1, 0, 2, 0, 3, 0, 4, 0]);
  });
}

int _uint16(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _uint32(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
