import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/services/qwen_realtime_speech_provider.dart';

void main() {
  group('parseTranscriptionEvent', () {
    test('部分结果拼接 text + stash，标记为非最终', () {
      final segment = parseTranscriptionEvent(
        jsonDecode(
              '{"type": '
              '"conversation.item.input_audio_transcription.text", '
              '"text": "今天天气不错，", "stash": "阳光"}',
            )
            as Object,
      );
      expect(segment, isNotNull);
      expect(segment!.isFinal, isFalse);
      expect(segment.text, '今天天气不错，阳光');
    });

    test('stash 为空时仅返回已确认文本', () {
      final segment = parseTranscriptionEvent({
        'type': 'conversation.item.input_audio_transcription.text',
        'text': '你好',
        'stash': '',
      });
      expect(segment!.text, '你好');
      expect(segment.isFinal, isFalse);
    });

    test('最终结果使用 transcript，标记为最终', () {
      final segment = parseTranscriptionEvent({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': '今天天气怎么样',
      });
      expect(segment!.isFinal, isTrue);
      expect(segment.text, '今天天气怎么样');
    });

    test('session.finished / error / 未知事件返回 null（由调用方另行处理）', () {
      expect(parseTranscriptionEvent({'type': 'session.finished'}), isNull);
      expect(
        parseTranscriptionEvent({
          'type': 'error',
          'error': {'code': 'x'},
        }),
        isNull,
      );
      expect(parseTranscriptionEvent({'type': 'session.created'}), isNull);
    });

    test('非对象或缺字段安全返回 null', () {
      expect(parseTranscriptionEvent(null), isNull);
      expect(parseTranscriptionEvent('not a map'), isNull);
      expect(parseTranscriptionEvent(42), isNull);
      expect(
        parseTranscriptionEvent({
          'type': 'conversation.item.input_audio_transcription.completed',
        })!.text,
        '',
      );
    });
  });

  group('startSession', () {
    test('session.created 不代表配置就绪，必须等待 session.updated', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final socketReady = Completer<WebSocket>();
      final updateReceived = Completer<void>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((data) {
          final event = jsonDecode(data as String) as Map<String, Object?>;
          if (event['type'] == 'session.update' &&
              !updateReceived.isCompleted) {
            updateReceived.complete();
          }
          if (event['type'] == 'session.finish') {
            socket.add(jsonEncode({'type': 'session.finished'}));
          }
        });
        socketReady.complete(socket);
      });
      final provider = QwenRealtimeSpeechProvider(
        apiKey: 'test-key',
        modelName: 'test-model',
        webSocketUrl: 'ws://${server.address.address}:${server.port}/realtime',
        readyTimeout: const Duration(seconds: 1),
      );
      addTearDown(provider.stop);

      var started = false;
      final startFuture = provider.startSession().then((_) => started = true);
      final socket = await socketReady.future;
      await updateReceived.future;
      socket.add(jsonEncode({'type': 'session.created'}));
      final completedBeforeUpdate = await Future.any<bool>([
        startFuture.then((_) => true),
        Future<bool>.delayed(const Duration(milliseconds: 50), () => false),
      ]);
      expect(completedBeforeUpdate, isFalse);
      expect(started, isFalse);

      socket.add(jsonEncode({'type': 'session.updated'}));
      await startFuture;
      expect(started, isTrue);
      await provider.stop();
    });

    test('服务端在就绪前关闭连接时返回失败', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        await socket.close();
      });
      final provider = QwenRealtimeSpeechProvider(
        apiKey: 'test-key',
        modelName: 'test-model',
        webSocketUrl: 'ws://${server.address.address}:${server.port}/realtime',
      );
      addTearDown(provider.stop);

      await expectLater(
        provider.startSession(),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'streaming_closed_before_ready',
          ),
        ),
      );
    });

    test('服务端不确认会话时就绪等待超时', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        Timer(const Duration(milliseconds: 100), socket.close);
      });
      final provider = QwenRealtimeSpeechProvider(
        apiKey: 'test-key',
        modelName: 'test-model',
        webSocketUrl: 'ws://${server.address.address}:${server.port}/realtime',
        readyTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(provider.stop);

      await expectLater(
        provider.startSession(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('WebSocket 握手失败后 stop 不再等待收尾超时', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.statusCode = HttpStatus.serviceUnavailable;
        await request.response.close();
      });
      final provider = QwenRealtimeSpeechProvider(
        apiKey: 'test-key',
        modelName: 'test-model',
        webSocketUrl: 'ws://${server.address.address}:${server.port}/realtime',
      );

      await expectLater(provider.startSession(), throwsA(anything));
      await expectLater(
        provider.stop().timeout(const Duration(milliseconds: 300)),
        completes,
      );
    });
  });
}
