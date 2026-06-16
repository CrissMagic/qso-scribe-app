// MiMo 语音识别（mimo-v2.5-asr）独立连通性测试脚本。
//
// 用途：脱离 app，直接按官方文档调用 MiMo ASR，验证 API Key、音频格式、
// 识别结果是否正常；并附带诊断，直接复现 app 打包后录音识别报 404 的根因。
//
// 官方文档：https://mimo.mi.com/docs/zh-CN/quick-start/usage-guide/audio/Speech-Recognition
//
// 运行（在项目根目录执行）：
//   dart run tool/mimo_asr_smoke.dart [音频文件路径]
//
// 环境变量：
//   MIMO_API_KEY    必填，你的 MiMo API Key
//   MIMO_AUDIO_PATH 可选，音频文件路径（wav 或 mp3，Base64 后需 < 10MB）；
//                   不传则用内置合成正弦波做接口可达性探测
//                   （仅能验证 200/格式，真实识别效果需真人语音）
//   MIMO_BASE_URL   可选，默认 https://api.xiaomimimo.com/v1
//   MIMO_ASR_LANG   可选，auto / zh / en，默认 auto
//   MIMO_VERBOSE    可选，任意非空值时打印完整请求/响应原文
//
// Windows 设置 API Key：
//   cmd        :  set MIMO_API_KEY=你的key
//   PowerShell :  $env:MIMO_API_KEY="你的key"

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

const _defaultBaseUrl = 'https://api.xiaomimimo.com/v1';
const _asrModel = 'mimo-v2.5-asr';
const _structuringModel = 'mimo-v2.5-pro';

Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final apiKey = env['MIMO_API_KEY']?.trim();
  final baseUrl = (env['MIMO_BASE_URL'] ?? _defaultBaseUrl).trim();
  final asrLang = (env['MIMO_ASR_LANG'] ?? 'auto').trim();
  final verbose = (env['MIMO_VERBOSE'] ?? '').isNotEmpty;

  stdout.writeln('=== MiMo 语音识别独立测试 ===');
  stdout.writeln('Base URL  : $baseUrl');
  stdout.writeln('ASR 模型  : $_asrModel');
  stdout.writeln('整理模型  : $_structuringModel');
  stdout.writeln('语种      : $asrLang');
  stdout.writeln(
    'API Key   : ${apiKey == null ? "(未设置 MIMO_API_KEY)" : "${_maskKey(apiKey)} (${apiKey.length} 字符)"}',
  );

  if (apiKey == null || apiKey.isEmpty) {
    stdout.writeln('\n✗ 未检测到 API Key，请先设置环境变量 MIMO_API_KEY 后重试。');
    exit(1);
  }

  final audioArg = (args.isNotEmpty ? args.first : env['MIMO_AUDIO_PATH'])?.trim();
  final audio = await _loadAudio(audioArg);

  final client = http.Client();
  try {
    final asrOk = await _safe(
      () => _probeAsrChatCompletions(
        client,
        baseUrl,
        apiKey,
        asrLang,
        audio.mimeType,
        audio.base64,
        verbose,
      ),
    );
    final whisperOk = await _safe(
      () => _probeWhisperEndpoint(client, baseUrl, apiKey, audioArg, audio.bytes, verbose),
    );
    final structOk = await _safe(
      () => _probeStructuring(client, baseUrl, apiKey, verbose),
    );
    _verdict(asrOk, whisperOk, structOk);
  } finally {
    client.close();
  }
}

// ① 正确方式：按官方文档走 chat/completions，input_audio + asr_options + api-key 头。
Future<bool> _probeAsrChatCompletions(
  http.Client client,
  String baseUrl,
  String apiKey,
  String language,
  String mimeType,
  String base64Audio,
  bool verbose,
) async {
  stdout.writeln(
    '\n① [正确] POST $baseUrl/chat/completions  '
    '(按官方文档: input_audio data URL + asr_options，头 api-key)',
  );
  final body = jsonEncode({
    'model': _asrModel,
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'input_audio',
            'input_audio': {'data': 'data:$mimeType;base64,$base64Audio'},
          },
        ],
      },
    ],
    'asr_options': {'language': language},
  });
  final response = await client
      .post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {'Content-Type': 'application/json', 'api-key': apiKey},
        body: body,
      )
      .timeout(const Duration(seconds: 60));
  final text = _extractChatText(response.body);
  _printResponse('①', response, verbose, extra: text == null ? null : '识别文本: $text');
  return response.statusCode >= 200 && response.statusCode < 300;
}

// ② 诊断：模拟 app 当前的调用方式，POST audio/transcriptions（OpenAI Whisper 多部分上传）。
//    预期返回 404 —— 直接复现打包后录音识别的报错。
Future<bool> _probeWhisperEndpoint(
  http.Client client,
  String baseUrl,
  String apiKey,
  String? audioArg,
  Uint8List bytes,
  bool verbose,
) async {
  stdout.writeln(
    '\n② [诊断] POST $baseUrl/audio/transcriptions  '
    '(app 当前调用方式: OpenAI Whisper 多部分上传，头 Authorization: Bearer)',
  );
  File? tmp;
  String filePath;
  if (audioArg != null && audioArg.isNotEmpty) {
    filePath = audioArg;
  } else {
    tmp = await File(
      '${Directory.systemTemp.path}/mimo_smoke_${DateTime.now().microsecondsSinceEpoch}.wav',
    ).create();
    await tmp.writeAsBytes(bytes);
    filePath = tmp.path;
  }
  try {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/audio/transcriptions'))
      ..fields['model'] = _asrModel
      ..files.add(await http.MultipartFile.fromPath('file', filePath))
      ..headers['Authorization'] = 'Bearer $apiKey';
    final streamed = await client.send(request).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    _printResponse('②', response, verbose);
    return response.statusCode >= 200 && response.statusCode < 300;
  } finally {
    await tmp?.delete();
  }
}

// ③ 附带：用 mimo-v2.5-pro 走 chat/completions 测 QSO 整理链路是否可用。
Future<bool> _probeStructuring(
  http.Client client,
  String baseUrl,
  String apiKey,
  bool verbose,
) async {
  stdout.writeln(
    '\n③ [附带] POST $baseUrl/chat/completions  '
    '(mimo-v2.5-pro，测 QSO 整理链路，头 api-key)',
  );
  final body = jsonEncode({
    'model': _structuringModel,
    'response_format': {'type': 'json_object'},
    'messages': [
      {
        'role': 'system',
        'content': 'Extract one amateur radio QSO. Return JSON only with keys: '
            'callsign, band, frequency, mode, sentRst, receivedRst.',
      },
      {
        'role': 'user',
        'content': 'CQ CQ this is BG7XYZ calling. On 20 meters 14.270 MHz, '
            'you are 59, my QTH is Beijing.',
      },
    ],
  });
  final response = await client
      .post(
        Uri.parse('$baseUrl/chat/completions'),
        headers: {'Content-Type': 'application/json', 'api-key': apiKey},
        body: body,
      )
      .timeout(const Duration(seconds: 60));
  final text = _extractChatText(response.body);
  _printResponse('③', response, verbose, extra: text == null ? null : '整理输出: $text');
  return response.statusCode >= 200 && response.statusCode < 300;
}

void _verdict(bool asrOk, bool whisperOk, bool structOk) {
  stdout.writeln('\n=== 结论 ===');
  stdout.writeln('① ASR 正确调用 (chat/completions): ${asrOk ? "✓ 200 通过" : "✗ 失败"}');
  stdout.writeln('② app 当前调用 (audio/transcriptions): ${whisperOk ? "✓ 通过" : "✗ 非 2xx（若为 404 即为 app 报错根因）"}');
  stdout.writeln('③ QSO 整理 (mimo-v2.5-pro): ${structOk ? "✓ 200 通过" : "✗ 失败"}');
  if (asrOk && !whisperOk) {
    stdout.writeln(
      '\n诊断: MiMo ASR 接口本身可用，app 报 404 是因为代码走了 OpenAI Whisper 的 '
      'audio/transcriptions 端点，而 MiMo 只支持 chat/completions。'
      '\n需将 _transcribeAudio 改为按官方文档的 input_audio + asr_options 方式调用。',
    );
  }
}

void _printResponse(String tag, http.BaseResponse base, bool verbose, {String? extra}) {
  final response = base as http.Response;
  final ok = response.statusCode >= 200 && response.statusCode < 300;
  stdout.writeln('   HTTP ${response.statusCode} ${ok ? "✓" : "✗"}');
  if (extra != null) {
    stdout.writeln('   $extra');
  }
  if (verbose || !ok) {
    stdout.writeln('   响应原文: ${_truncate(response.body, 2000)}');
  }
}

// 从 chat/completions 响应里抽取 message.content 文本。
String? _extractChatText(String body) {
  try {
    final payload = jsonDecode(body) as Map<String, Object?>;
    final choices = payload['choices'] as List<Object?>?;
    if (choices == null || choices.isEmpty) {
      return null;
    }
    final message = (choices.first as Map<String, Object?>)['message'] as Map<String, Object?>?;
    final content = message?['content'];
    return content?.toString();
  } catch (_) {
    return null;
  }
}

class _Audio {
  const _Audio(this.bytes, this.mimeType, this.base64);
  final Uint8List bytes;
  final String mimeType;
  final String base64;
}

Future<_Audio> _loadAudio(String? path) async {
  stdout.writeln('');
  if (path != null && path.isNotEmpty) {
    final file = File(path);
    if (!file.existsSync()) {
      stdout.writeln('✗ 音频文件不存在: $path');
      exit(1);
    }
    final bytes = await file.readAsBytes();
    final mime = path.toLowerCase().endsWith('.mp3') ? 'audio/mpeg' : 'audio/wav';
    stdout.writeln('音频来源 : 文件 $path');
    return _wrapAudio(bytes, mime);
  }
  stdout.writeln('音频来源 : 合成正弦波（仅用于接口探测；真实识别效果请传入真人录音）');
  return _wrapAudio(_syntheticWav(), 'audio/wav');
}

_Audio _wrapAudio(Uint8List bytes, String mime) {
  final b64 = base64Encode(bytes);
  stdout.writeln('音频大小 : ${bytes.length} 字节 (Base64 后 ${b64.length} 字节)');
  if (b64.length > 10 * 1024 * 1024) {
    stdout.writeln('✗ Base64 后超过 10MB 上限，请换更短的音频。');
    exit(1);
  }
  return _Audio(bytes, mime, b64);
}

// 合成一段 16kHz 单声道 PCM16 正弦波 WAV。
Uint8List _syntheticWav() {
  const sampleRate = 16000;
  const durationSeconds = 1.0;
  const freq = 440.0;
  final numSamples = (sampleRate * durationSeconds).round();
  final pcm = Uint8List(numSamples * 2);
  final bd = ByteData.sublistView(pcm);
  for (var i = 0; i < numSamples; i++) {
    final t = i / sampleRate;
    final amp = 0.25 * (1 - i / numSamples);
    final sample = (32767 * amp * sin(2 * pi * freq * t)).round().clamp(-32768, 32767).toInt();
    bd.setInt16(i * 2, sample, Endian.little);
  }
  return _wrapWav(pcm, sampleRate, 1, 16);
}

Uint8List _wrapWav(Uint8List pcm, int sampleRate, int channels, int bitsPerSample) {
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;
  final b = BytesBuilder()
    ..add(utf8.encode('RIFF'))
    ..add(_u32(36 + pcm.length))
    ..add(utf8.encode('WAVE'))
    ..add(utf8.encode('fmt '))
    ..add(_u32(16))
    ..add(_u16(1))
    ..add(_u16(channels))
    ..add(_u32(sampleRate))
    ..add(_u32(byteRate))
    ..add(_u16(blockAlign))
    ..add(_u16(bitsPerSample))
    ..add(utf8.encode('data'))
    ..add(_u32(pcm.length))
    ..add(pcm);
  return b.toBytes();
}

Uint8List _u32(int v) {
  final b = ByteData(4)..setUint32(0, v, Endian.little);
  return b.buffer.asUint8List();
}

Uint8List _u16(int v) {
  final b = ByteData(2)..setUint16(0, v, Endian.little);
  return b.buffer.asUint8List();
}

String _maskKey(String key) {
  if (key.length <= 8) {
    return '${key.substring(0, key.length ~/ 2)}…';
  }
  return '${key.substring(0, 5)}…${key.substring(key.length - 3)}';
}

String _truncate(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max)}…(${s.length} 字节)';

// 捕获单个探针的异常，避免一次失败中断其余探针。
Future<bool> _safe(Future<bool> Function() fn) async {
  try {
    return await fn();
  } catch (e) {
    stdout.writeln('   ✗ 异常: $e\n');
    return false;
  }
}
