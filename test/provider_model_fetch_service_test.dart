import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:qso_scribe_app/src/services/provider_model_fetch_service.dart';

void main() {
  test('builds model endpoint candidates for versioned base URLs', () {
    expect(buildModelListUrlCandidates('https://api.example.com/v1'), [
      'https://api.example.com/v1/models',
    ]);
    expect(
      buildModelListUrlCandidates('https://open.bigmodel.cn/api/paas/v4'),
      [
        'https://open.bigmodel.cn/api/paas/v4/models',
        'https://open.bigmodel.cn/api/paas/v4/v1/models',
      ],
    );
    expect(
      buildModelListUrlCandidates(
        'https://generativelanguage.googleapis.com/v1beta/openai',
      ),
      [
        'https://generativelanguage.googleapis.com/v1beta/openai/models',
        'https://generativelanguage.googleapis.com/v1beta/openai/v1/models',
      ],
    );
  });

  test('strips known compatibility suffixes as fallback model endpoints', () {
    expect(buildModelListUrlCandidates('https://api.deepseek.com/anthropic'), [
      'https://api.deepseek.com/anthropic/v1/models',
      'https://api.deepseek.com/v1/models',
      'https://api.deepseek.com/models',
    ]);
  });

  test('infers basic model capabilities for assignment filtering', () {
    expect(inferModelCapabilities('whisper-1'), {ModelCapability.speech});
    expect(inferModelCapabilities('gpt-realtime'), {
      ModelCapability.speech,
      ModelCapability.streaming,
    });
    expect(inferModelCapabilities('deepseek-chat'), {
      ModelCapability.text,
      ModelCapability.structuring,
    });
  });
}
