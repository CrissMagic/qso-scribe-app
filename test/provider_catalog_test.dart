import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:qso_scribe_app/src/domain/provider_catalog.dart';

void main() {
  group('AiProvider.fromKey 兼容性', () {
    test('所有固定供应商 key 可往返解析', () {
      for (final provider in selectableProviders) {
        final key = provider.provider.name;
        expect(AiProvider.fromKey(key), provider.provider);
      }
    });

    test('未知 key 与 null 安全降级为 unknown，绝不抛异常', () {
      expect(AiProvider.fromKey('not-a-real-provider'), AiProvider.unknown);
      expect(AiProvider.fromKey(null), AiProvider.unknown);
      expect(AiProvider.fromKey(''), AiProvider.unknown);
    });
  });

  group('selectableProviders', () {
    test('不含 unknown，且包含全部固定供应商', () {
      final keys = selectableProviders.map((d) => d.provider).toSet();
      expect(keys.contains(AiProvider.unknown), isFalse);
      expect(keys, {
        AiProvider.openai,
        AiProvider.zhipu,
        AiProvider.qwen,
        AiProvider.mimo,
        AiProvider.deepseek,
      });
    });
  });

  group('各家 ASR 形态与鉴权契约', () {
    test('OpenAI / Zhipu 走 Whisper 多部分上传 + Bearer', () {
      for (final provider in const [AiProvider.openai, AiProvider.zhipu]) {
        final d = descriptorFor(provider);
        expect(d.supportsAsr, isTrue, reason: provider.name);
        expect(d.asr!.shape, AsrShape.whisperMultipart, reason: provider.name);
        expect(d.authStyle, AuthStyle.bearer, reason: provider.name);
      }
    });

    test('Qwen / MiMo 走 chat/completions + input_audio', () {
      final qwen = descriptorFor(AiProvider.qwen);
      expect(qwen.asr!.shape, AsrShape.chatInputAudio);
      expect(qwen.asr!.languageOption, isNull);
      expect(qwen.authStyle, AuthStyle.bearer);
      expect(qwen.streamingCapable, isTrue);
      // 文件转写(speech)与实时转写(streaming)两个模型能力分离，互不混用。
      final qwenAsrByName = {
        for (final model in qwen.presetAsrModels) model.name: model,
      };
      expect(
        qwenAsrByName['qwen3-asr-flash']!.capabilities,
        {ModelCapability.speech},
      );
      expect(
        qwenAsrByName['qwen3-asr-flash-realtime']!.capabilities,
        {ModelCapability.streaming},
      );

      final mimo = descriptorFor(AiProvider.mimo);
      expect(mimo.asr!.shape, AsrShape.chatInputAudio);
      expect(mimo.asr!.languageOption, 'auto');
      expect(mimo.authStyle, AuthStyle.apiKeyHeader);
    });

    test('DeepSeek 不支持语音识别，仅结构化', () {
      final d = descriptorFor(AiProvider.deepseek);
      expect(d.supportsAsr, isFalse);
      expect(d.presetAsrModels, isEmpty);
      expect(d.structuringModels, isNotEmpty);
    });

    test('每个支持 ASR 的供应商预置的 ASR 模型都具备语音能力(speech 或 streaming)', () {
      for (final d in selectableProviders) {
        if (!d.supportsAsr) continue;
        for (final model in d.presetAsrModels) {
          final caps = model.capabilities;
          expect(
            caps.contains(ModelCapability.speech) ||
                caps.contains(ModelCapability.streaming),
            isTrue,
            reason: '${d.provider.name}: ${model.name}',
          );
        }
      }
    });
  });
}
