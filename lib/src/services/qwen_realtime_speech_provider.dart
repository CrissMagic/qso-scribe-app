import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/app_models.dart';
import '../domain/service_contracts.dart';

// Qwen 实时语音识别（qwen3-asr-flash-realtime）WebSocket 实现。
//
// 协议要点（官方文档：实时语音识别-千问 / Qwen-ASR Realtime）：
// - 端点固定：wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=<model>
// - 握手头：Authorization: Bearer <apiKey>（握手阶段校验，失败返回 401/403）
// - 连接后发 session.update，启用 server_vad 自动断句；服务端回 session.updated 确认
// - 持续发 input_audio_buffer.append，audio 为 base64 的 PCM16 数据
// - 部分结果：conversation.item.input_audio_transcription.text（text 已确认前缀，stash 待定后缀）
// - 最终结果：conversation.item.input_audio_transcription.completed（transcript）
// - 单句失败：conversation.item.input_audio_transcription.failed
// - 结束发 session.finish，收到 session.finished 后断开

const _qwenRealtimeWsUrl = 'wss://dashscope.aliyuncs.com/api-ws/v1/realtime';

class QwenRealtimeSpeechProvider implements SpeechTranscriptionProvider {
  QwenRealtimeSpeechProvider({
    required String apiKey,
    required String modelName,
    this.language,
  }) : _apiKey = apiKey,
       _modelName = modelName;

  final String _apiKey;
  final String _modelName;

  // 语种提示；为 null 时不指定，交由服务端自动检测（与文件转写一致）。
  final String? language;

  WebSocket? _socket;
  int _eventSeq = 0;
  bool _stopped = false;
  final _stopCompleter = Completer<void>();
  // 等待服务端确认 session 配置生效（session.created/session.updated）。
  final _readyCompleter = Completer<void>();
  final _transcriptController = StreamController<TranscriptSegment>.broadcast();

  // 最近一次识别返回的语种（zh/en/yue/...），供上层参考；为 null 表示尚未识别。
  String? lastDetectedLanguage;

  @override
  SpeechProviderCapabilities get capabilities =>
      const SpeechProviderCapabilities(
        supportsStreaming: true,
        supportsPartialResult: true,
        supportsFinalSegment: true,
        preferredSampleRate: 16000,
        acceptedEncoding: 'pcm16',
        requiresManualCommit: false,
      );

  @override
  Stream<TranscriptSegment> get transcriptEvents => _transcriptController.stream;

  String get _wsUrl => '$_qwenRealtimeWsUrl?model=$_modelName';

  @override
  Future<void> startSession(SpeechSessionConfig config) async {
    _socket = await WebSocket.connect(
      _wsUrl,
      headers: {'Authorization': 'Bearer $_apiKey'},
    );
    _send(_buildSessionUpdate());
    _socket!.listen(
      _onData,
      onError: (Object error) => _abort(error),
      onDone: () {
        // 连接关闭时解除所有等待，避免上层永久挂起。
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
        if (!_stopCompleter.isCompleted) {
          _stopCompleter.complete();
        }
      },
      cancelOnError: true,
    );
    // 等待服务端确认 session 配置生效后再返回，确保 VAD 配置按客户端设置生效，
    // 避免首批音频按默认配置（threshold 0.2 / silence 800ms）处理。
    // 超时保护：网络异常未收到确认时也不永久挂起。
    await _readyCompleter.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
  }

  Map<String, Object?> _buildSessionUpdate() {
    return {
      'type': 'session.update',
      'event_id': _nextEventId(),
      'session': {
        'input_audio_format': 'pcm',
        'sample_rate': 16000,
        if (language != null)
          'input_audio_transcription': {'language': language},
        'turn_detection': {
          'type': 'server_vad',
          // 官方推荐：threshold 0.0（高灵敏度）+ silence 400ms（较快断句）。
          'threshold': 0.0,
          'silence_duration_ms': 400,
        },
      },
    };
  }

  @override
  Future<void> sendAudioFrame(AudioFrame frame) async {
    final socket = _socket;
    if (_stopped || socket == null || socket.readyState != WebSocket.open) {
      return;
    }
    _send({
      'type': 'input_audio_buffer.append',
      'event_id': _nextEventId(),
      'audio': base64Encode(frame.bytes),
    });
  }

  @override
  Future<void> commit() async {
    // VAD 模式下由服务端自动断句，无需手动 commit。
  }

  @override
  Future<void> stop() async {
    if (_stopped) {
      return;
    }
    _stopped = true;
    final socket = _socket;
    if (socket != null && socket.readyState == WebSocket.open) {
      _send({'type': 'session.finish', 'event_id': _nextEventId()});
    }
    await _stopCompleter.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    await socket?.close();
    if (!_transcriptController.isClosed) {
      await _transcriptController.close();
    }
  }

  void _onData(Object? data) {
    if (data is! String) {
      return;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return;
    }
    if (decoded is Map<String, Object?>) {
      final type = decoded['type']?.toString();
      final lang = decoded['language']?.toString();
      if (lang != null && lang.isNotEmpty) {
        lastDetectedLanguage = lang;
      }
      switch (type) {
        case 'session.created':
        case 'session.updated':
          if (!_readyCompleter.isCompleted) {
            _readyCompleter.complete();
          }
          return;
        case 'session.finished':
          if (!_stopCompleter.isCompleted) {
            _stopCompleter.complete();
          }
          return;
        case 'error':
          _abort(StateError('streaming_error:${_errorMessage(decoded)}'));
          return;
        case 'conversation.item.input_audio_transcription.failed':
          // 单句识别失败：上报错误但不终止整个会话，后续句子仍可继续。
          _transcriptController.addError(
            StateError('transcription_failed:${_errorMessage(decoded)}'),
          );
          return;
      }
    }
    final segment = parseTranscriptionEvent(decoded);
    if (segment != null) {
      _transcriptController.add(segment);
    }
  }

  // 从 error / transcription.failed 事件中提取可读 message。
  String _errorMessage(Map<String, Object?> event) {
    final error = event['error'];
    if (error is Map<String, Object?>) {
      final msg = error['message'];
      if (msg != null) return msg.toString();
      final code = error['code'];
      if (code != null) return code.toString();
    }
    return error?.toString() ?? 'unknown';
  }

  void _abort(Object error) {
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    if (!_stopCompleter.isCompleted) {
      _stopCompleter.complete();
    }
    _transcriptController.addError(error);
  }

  void _send(Map<String, Object?> event) {
    _socket?.add(jsonEncode(event));
  }

  String _nextEventId() => 'evt_${_eventSeq++}';
}

// 解析服务端事件为转写片段；返回 null 表示该事件不是转写结果（由调用方另行处理）。
// 抽为顶层纯函数以便单测。
TranscriptSegment? parseTranscriptionEvent(Object? raw) {
  if (raw is! Map<String, Object?>) {
    return null;
  }
  switch (raw['type']) {
    case 'conversation.item.input_audio_transcription.text':
      final text = raw['text']?.toString() ?? '';
      final stash = raw['stash']?.toString() ?? '';
      return TranscriptSegment(
        speaker: 'RX',
        text: '$text$stash',
        isFinal: false,
      );
    case 'conversation.item.input_audio_transcription.completed':
      return TranscriptSegment(
        speaker: 'RX',
        text: raw['transcript']?.toString() ?? '',
        isFinal: true,
      );
    default:
      return null;
  }
}
