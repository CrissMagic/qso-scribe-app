import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/services/qwen_realtime_speech_provider.dart';

void main() {
  group('parseTranscriptionEvent', () {
    test('部分结果拼接 text + stash，标记为非最终', () {
      final segment = parseTranscriptionEvent(
        jsonDecode('{"type": '
            '"conversation.item.input_audio_transcription.text", '
            '"text": "今天天气不错，", "stash": "阳光"}')
            as Object,
      );
      expect(segment, isNotNull);
      expect(segment!.isFinal, isFalse);
      expect(segment.text, '今天天气不错，阳光');
    });

    test('stash 为空时仅返回已确认文本', () {
      final segment = parseTranscriptionEvent(
        {'type': 'conversation.item.input_audio_transcription.text', 'text': '你好', 'stash': ''},
      );
      expect(segment!.text, '你好');
      expect(segment.isFinal, isFalse);
    });

    test('最终结果使用 transcript，标记为最终', () {
      final segment = parseTranscriptionEvent(
        {
          'type': 'conversation.item.input_audio_transcription.completed',
          'transcript': '今天天气怎么样',
        },
      );
      expect(segment!.isFinal, isTrue);
      expect(segment.text, '今天天气怎么样');
    });

    test('session.finished / error / 未知事件返回 null（由调用方另行处理）', () {
      expect(parseTranscriptionEvent({'type': 'session.finished'}), isNull);
      expect(
        parseTranscriptionEvent({'type': 'error', 'error': {'code': 'x'}}),
        isNull,
      );
      expect(parseTranscriptionEvent({'type': 'session.created'}), isNull);
    });

    test('非对象或缺字段安全返回 null', () {
      expect(parseTranscriptionEvent(null), isNull);
      expect(parseTranscriptionEvent('not a map'), isNull);
      expect(parseTranscriptionEvent(42), isNull);
      expect(
        parseTranscriptionEvent(
          {'type': 'conversation.item.input_audio_transcription.completed'},
        )!.text,
        '',
      );
    });
  });
}
