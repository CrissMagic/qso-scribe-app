import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

const defaultPcmSampleRate = 16000;
const defaultPcmChannels = 1;
const defaultPcmBitsPerSample = 16;

Uint8List wavHeader({
  required int dataLength,
  required int sampleRate,
  required int channels,
  int bitsPerSample = defaultPcmBitsPerSample,
}) {
  final bytesPerSample = bitsPerSample ~/ 8;
  final blockAlign = channels * bytesPerSample;
  final byteRate = sampleRate * blockAlign;
  final dataSize = _uint32(dataLength);
  final header = ByteData(44);

  _writeAscii(header, 0, 'RIFF');
  header.setUint32(4, _uint32(36 + dataSize), Endian.little);
  _writeAscii(header, 8, 'WAVE');
  _writeAscii(header, 12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, bitsPerSample, Endian.little);
  _writeAscii(header, 36, 'data');
  header.setUint32(40, dataSize, Endian.little);

  return header.buffer.asUint8List();
}

Future<String> playableAudioPathFor(
  String sourcePath, {
  int sampleRate = defaultPcmSampleRate,
  int channels = defaultPcmChannels,
}) async {
  final source = File(sourcePath);
  if (!source.existsSync()) {
    throw StateError('audio_file_missing');
  }

  if (p.extension(source.path).toLowerCase() != '.pcm') {
    return source.path;
  }

  final target = File(p.setExtension(source.path, '.wav'));
  final sourceStat = await source.stat();
  if (await _isFreshWavSidecar(target, sourceStat)) {
    return target.path;
  }

  final sink = target.openWrite();
  sink.add(
    wavHeader(
      dataLength: sourceStat.size,
      sampleRate: sampleRate,
      channels: channels,
    ),
  );
  await source.openRead().pipe(sink);
  return target.path;
}

Future<bool> _isFreshWavSidecar(File target, FileStat sourceStat) async {
  if (!target.existsSync()) {
    return false;
  }
  final targetStat = await target.stat();
  return targetStat.size == sourceStat.size + 44 &&
      !targetStat.modified.isBefore(sourceStat.modified);
}

void _writeAscii(ByteData data, int offset, String value) {
  for (var index = 0; index < value.length; index += 1) {
    data.setUint8(offset + index, value.codeUnitAt(index));
  }
}

int _uint32(int value) => value.clamp(0, 0xFFFFFFFF).toInt();
