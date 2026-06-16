import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../domain/app_models.dart';
import '../domain/provider_catalog.dart';
import 'wav_audio.dart';

// 固定供应商的 HTTP 调用策略层。
//
// 语音识别按 [AsrShape] 分发到两种实现；结构化统一走 chat/completions；
// 鉴权头按 [AuthStyle] 构造。新增"复用现有形态"的供应商无需新增任何调用代码，
// 只需在 provider_catalog 中声明描述符；新增形态时再在此追加一个实现。

Map<String, String> _authHeaders(AuthStyle style, String? apiKey) {
  if (apiKey == null || apiKey.trim().isEmpty) {
    return const {};
  }
  final key = apiKey.trim();
  return switch (style) {
    AuthStyle.bearer => {'Authorization': 'Bearer $key'},
    AuthStyle.apiKeyHeader => {'api-key': key},
  };
}

String _joinPath(String baseUrl, String suffix) {
  final normalized =
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  return '$normalized/$suffix';
}

String _mimeTypeFor(String path) {
  final ext = p.extension(path).toLowerCase();
  return switch (ext) {
    '.mp3' => 'audio/mpeg',
    '.mp4' || '.m4a' => 'audio/mp4',
    '.ogg' || '.opus' => 'audio/ogg',
    '.flac' => 'audio/flac',
    '.webm' => 'audio/webm',
    '.amr' => 'audio/amr',
    '.aac' => 'audio/aac',
    _ => 'audio/wav',
  };
}

/// 从响应体解析 OpenAI 兼容的 usage 字段；不存在时返回 null。
TokenUsage? _parseUsage(String body) {
  try {
    final payload = jsonDecode(body) as Map<String, Object?>;
    final usage = payload['usage'];
    if (usage is Map<String, Object?>) {
      return TokenUsage(
        promptTokens: (usage['prompt_tokens'] as num?)?.toInt(),
        completionTokens: (usage['completion_tokens'] as num?)?.toInt(),
        totalTokens: (usage['total_tokens'] as num?)?.toInt(),
      );
    }
  } catch (_) {}
  return null;
}

/// 从 chat/completions 响应体中提取 message.content 文本。
String? _chatContent(String body) {
  try {
    final payload = jsonDecode(body) as Map<String, Object?>;
    final choices = payload['choices'] as List<Object?>?;
    if (choices == null || choices.isEmpty) {
      return null;
    }
    final message =
        (choices.first as Map<String, Object?>)['message'] as Map<String, Object?>?;
    return message?['content']?.toString();
  } catch (_) {
    return null;
  }
}

/// 语音识别客户端。按供应商 ASR 形态分发。
class ProviderAsrClient {
  ProviderAsrClient(this._httpClient);

  final http.Client _httpClient;

  Future<({String text, TokenUsage? usage})> transcribe({
    required ProviderDescriptor descriptor,
    required String baseUrl,
    required String? apiKey,
    required String modelName,
    required String audioPath,
  }) async {
    final spec = descriptor.asr;
    if (spec == null) {
      throw StateError('provider_without_asr:${descriptor.provider.name}');
    }
    final uploadPath = await playableAudioPathFor(audioPath);
    _validateAudioFormat(uploadPath, spec);
    return switch (spec.shape) {
      AsrShape.whisperMultipart => _transcribeWhisper(
          descriptor: descriptor,
          baseUrl: baseUrl,
          apiKey: apiKey,
          modelName: modelName,
          uploadPath: uploadPath,
        ),
      AsrShape.chatInputAudio => _transcribeChatInputAudio(
          descriptor: descriptor,
          baseUrl: baseUrl,
          apiKey: apiKey,
          modelName: modelName,
          uploadPath: uploadPath,
        ),
    };
  }

  void _validateAudioFormat(String filePath, AsrSpec spec) {
    if (spec.supportedFormats.isEmpty) {
      return;
    }
    final ext = p.extension(filePath).toLowerCase().replaceFirst('.', '');
    if (ext == 'pcm') {
      return;
    }
    if (!spec.supportedFormats.contains(ext)) {
      throw StateError(
        'unsupported_audio_format:$ext,'
        'supported=${spec.supportedFormats.join(',')}',
      );
    }
  }

  // 形态 A：OpenAI / Zhipu。multipart 文件上传，响应 {text}。
  Future<({String text, TokenUsage? usage})> _transcribeWhisper({
    required ProviderDescriptor descriptor,
    required String baseUrl,
    required String? apiKey,
    required String modelName,
    required String uploadPath,
  }) async {
    if (!File(uploadPath).existsSync()) {
      throw StateError('audio_file_missing');
    }
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(_joinPath(baseUrl, 'audio/transcriptions')),
    )
      ..fields['model'] = modelName
      ..files.add(await http.MultipartFile.fromPath('file', uploadPath));
    final hotWords = descriptor.asr?.hotWords;
    if (hotWords != null && hotWords.isNotEmpty) {
      request.fields['hot_words'] = hotWords;
    }
    request.headers.addAll(_authHeaders(descriptor.authStyle, apiKey));
    final response = await http.Response.fromStream(
      await _httpClient.send(request).timeout(const Duration(minutes: 2)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('transcription_request_failed:${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final text = payload['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw StateError('transcription_response_missing_text');
    }
    return (text: text, usage: _parseUsage(response.body));
  }

  // 形态 B：Qwen / MiMo。base64 data URL 走 input_audio，响应取 message.content。
  Future<({String text, TokenUsage? usage})> _transcribeChatInputAudio({
    required ProviderDescriptor descriptor,
    required String baseUrl,
    required String? apiKey,
    required String modelName,
    required String uploadPath,
  }) async {
    final file = File(uploadPath);
    if (!file.existsSync()) {
      throw StateError('audio_file_missing');
    }
    final bytes = await file.readAsBytes();
    final dataUrl = 'data:${_mimeTypeFor(uploadPath)};base64,${base64Encode(bytes)}';
    final body = <String, Object?>{
      'model': modelName,
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_audio',
              'input_audio': {'data': dataUrl},
            },
          ],
        },
      ],
    };
    final languageOption = descriptor.asr?.languageOption;
    if (languageOption != null) {
      body['asr_options'] = {'language': languageOption};
    }
    final response = await _httpClient
        .post(
          Uri.parse(_joinPath(baseUrl, 'chat/completions')),
          headers: {
            'Content-Type': 'application/json',
            ..._authHeaders(descriptor.authStyle, apiKey),
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('transcription_request_failed:${response.statusCode}');
    }
    final content = _chatContent(response.body);
    if (content == null || content.trim().isEmpty) {
      throw StateError('transcription_response_missing_text');
    }
    return (text: content, usage: _parseUsage(response.body));
  }
}

/// 结构化客户端。所有供应商统一走 chat/completions，仅鉴权头不同。
class ProviderStructuringClient {
  ProviderStructuringClient(this._httpClient);

  final http.Client _httpClient;

  /// 调用结构化模型，返回 content 与 usage。
  Future<({String content, TokenUsage? usage})> structure({
    required ProviderDescriptor descriptor,
    required String baseUrl,
    required String? apiKey,
    required String modelName,
    required String systemPrompt,
    required String userText,
  }) async {
    final response = await _httpClient
        .post(
          Uri.parse(_joinPath(baseUrl, 'chat/completions')),
          headers: {
            'Content-Type': 'application/json',
            ..._authHeaders(descriptor.authStyle, apiKey),
          },
          body: jsonEncode({
            'model': modelName,
            'response_format': {'type': 'json_object'},
            'messages': [
              {'role': 'system', 'content': systemPrompt},
              {'role': 'user', 'content': userText},
            ],
          }),
        )
        .timeout(const Duration(minutes: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('structuring_request_failed:${response.statusCode}');
    }
    final content = _chatContent(response.body);
    if (content == null || content.trim().isEmpty) {
      throw StateError('structuring_response_missing_json');
    }
    return (content: content, usage: _parseUsage(response.body));
  }

  /// 连通性 + 鉴权探测：用结构化默认模型发一次最小 chat 请求。
  Future<void> probe({
    required ProviderDescriptor descriptor,
    required String baseUrl,
    required String? apiKey,
    required String modelName,
  }) async {
    final response = await _httpClient
        .post(
          Uri.parse(_joinPath(baseUrl, 'chat/completions')),
          headers: {
            'Content-Type': 'application/json',
            ..._authHeaders(descriptor.authStyle, apiKey),
          },
          body: jsonEncode({
            'model': modelName,
            'max_tokens': 1,
            'messages': [
              {'role': 'user', 'content': 'ping'},
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('connection_test_failed:${response.statusCode}');
    }
  }
}
