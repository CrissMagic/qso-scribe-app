import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:qso_scribe_app/src/services/app_update_service.dart';
import 'package:qso_scribe_app/src/services/release_info_service.dart';

void main() {
  AppRelease releaseWithDigest(String digest) {
    return AppRelease(
      version: '1.2.3+4',
      title: 'Version 1.2.3',
      notes: 'Notes',
      htmlUrl: 'https://github.com/example/release',
      apkAsset: AppReleaseAsset(
        name: 'qso-scribe-app-1.2.3-build4-android.apk',
        downloadUrl:
            'https://github.com/example/qso-scribe-app-1.2.3-build4-android.apk',
        size: 9,
        sha256Digest: digest,
      ),
    );
  }

  Future<Directory> createTempDir() async {
    final dir = await Directory.systemTemp.createTemp('qso-update-test-');
    addTearDown(() async {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    });
    return dir;
  }

  test('downloadApk writes file and reports progress', () async {
    final tempDir = await createTempDir();
    final bytes = utf8.encode('apk bytes!');
    final service = AppUpdateService(
      httpClient: MockClient.streaming((request, bodyStream) async {
        expect(
          request.url.toString(),
          'https://github.com/example/qso-scribe-app-1.2.3-build4-android.apk',
        );
        expect(request.headers['User-Agent'], 'qso-scribe-app');
        return http.StreamedResponse(
          Stream.fromIterable([bytes.sublist(0, 4), bytes.sublist(4)]),
          200,
          contentLength: bytes.length,
        );
      }),
      methodChannel: const MethodChannel('unused'),
      tempDirectoryProvider: () async => tempDir,
    );
    addTearDown(service.close);

    final received = <int>[];
    final path = await service.downloadApk(
      releaseWithDigest(sha256.convert(bytes).toString()),
      onProgress: (receivedBytes, totalBytes) {
        received.add(receivedBytes);
        expect(totalBytes, bytes.length);
      },
    );

    expect(await File(path).readAsBytes(), bytes);
    expect(received, [4, bytes.length]);
  });

  test(
    'downloadApk rejects checksum mismatch and removes partial file',
    () async {
      final tempDir = await createTempDir();
      final bytes = utf8.encode('apk bytes!');
      final service = AppUpdateService(
        httpClient: MockClient.streaming((request, bodyStream) async {
          return http.StreamedResponse(
            Stream.fromIterable([bytes]),
            200,
            contentLength: bytes.length,
          );
        }),
        methodChannel: const MethodChannel('unused'),
        tempDirectoryProvider: () async => tempDir,
      );
      addTearDown(service.close);

      await expectLater(
        service.downloadApk(
          releaseWithDigest(List.filled(64, '0').join()),
          onProgress: (_, _) {},
        ),
        throwsA(
          isA<AppUpdateException>().having(
            (error) => error.reason,
            'reason',
            AppUpdateFailureReason.checksumMismatch,
          ),
        ),
      );

      final updateDir = Directory(p.join(tempDir.path, 'updates'));
      expect(updateDir.existsSync(), isTrue);
      expect(updateDir.listSync(), isEmpty);
    },
  );
}
