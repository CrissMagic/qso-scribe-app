import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qso_scribe_app/src/domain/provider_catalog.dart';
import 'package:qso_scribe_app/src/services/ai_provider_clients.dart';

void main() {
  test('仅支持热词的 ASR 接收去重后的会话呼号', () async {
    final dir = await Directory.systemTemp.createTemp('qso-asr-client-test-');
    addTearDown(() => dir.delete(recursive: true));
    final audio = File('${dir.path}${Platform.pathSeparator}sample.wav');
    await audio.writeAsBytes(const [0, 1, 2, 3]);

    final requests = <http.MultipartRequest>[];
    final httpClient = MockClient.streaming((request, bodyStream) async {
      requests.add(request as http.MultipartRequest);
      await bodyStream.toBytes();
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"text":"CQ test"}')),
        200,
      );
    });
    addTearDown(httpClient.close);
    final client = ProviderAsrClient(httpClient);

    await client.transcribe(
      descriptor: descriptorFor(AiProvider.zhipu),
      baseUrl: 'https://example.test/v1',
      apiKey: 'key',
      modelName: 'glm-asr-2512',
      audioPath: audio.path,
      contextualHotWords: const ['BA1SELF', 'qth', 'F/BA1SELF/P'],
    );
    await client.transcribe(
      descriptor: descriptorFor(AiProvider.openai),
      baseUrl: 'https://example.test/v1',
      apiKey: 'key',
      modelName: 'whisper-1',
      audioPath: audio.path,
      contextualHotWords: const ['BA1SELF'],
    );

    final zhipuHotWords = requests.first.fields['hot_words']!;
    expect(zhipuHotWords, contains('BA1SELF:20'));
    expect(zhipuHotWords, contains('F/BA1SELF/P:20'));
    expect(RegExp(r'(?:^|,)QTH:').allMatches(zhipuHotWords), hasLength(1));
    expect(requests.last.fields, isNot(contains('hot_words')));
  });
}
