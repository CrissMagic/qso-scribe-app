import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qso_scribe_app/src/services/release_info_service.dart';

void main() {
  ReleaseInfoService serviceWithResponse(http.Response response) {
    return ReleaseInfoService(
      httpClient: MockClient((request) async {
        expect(
          request.url.toString(),
          'https://api.github.com/repos/CrissMagic/qso-scribe-app/releases/latest',
        );
        expect(request.headers['Accept'], 'application/vnd.github+json');
        expect(request.headers['User-Agent'], 'qso-scribe-app');
        return response;
      }),
    );
  }

  test('fetchLatestRelease parses GitHub release metadata', () async {
    final service = serviceWithResponse(
      http.Response('''
        {
          "tag_name": "v1.2.3+4",
          "name": " Version 1.2.3 ",
          "body": " Fixes and improvements ",
          "html_url": " https://github.com/CrissMagic/qso-scribe-app/releases/tag/v1.2.3+4 "
        }
        ''', 200),
    );

    final release = await service.fetchLatestRelease();

    expect(release.version, '1.2.3+4');
    expect(release.title, 'Version 1.2.3');
    expect(release.notes, 'Fixes and improvements');
    expect(
      release.htmlUrl,
      'https://github.com/CrissMagic/qso-scribe-app/releases/tag/v1.2.3+4',
    );
  });

  test('fetchLatestRelease reports no release for GitHub 404', () async {
    final service = serviceWithResponse(http.Response('{}', 404));

    expect(
      service.fetchLatestRelease,
      throwsA(
        isA<ReleaseInfoException>().having(
          (error) => error.reason,
          'reason',
          ReleaseInfoFailureReason.noRelease,
        ),
      ),
    );
  });

  test('fetchLatestRelease reports status code for non-success responses', () {
    final service = serviceWithResponse(http.Response('{}', 500));

    expect(
      service.fetchLatestRelease,
      throwsA(
        isA<ReleaseInfoException>()
            .having(
              (error) => error.reason,
              'reason',
              ReleaseInfoFailureReason.httpError,
            )
            .having((error) => error.statusCode, 'statusCode', 500),
      ),
    );
  });

  test('fetchLatestRelease reports timeout failures explicitly', () {
    final service = ReleaseInfoService(
      httpClient: MockClient((request) => throw TimeoutException('slow')),
    );

    expect(
      service.fetchLatestRelease,
      throwsA(
        isA<ReleaseInfoException>().having(
          (error) => error.reason,
          'reason',
          ReleaseInfoFailureReason.timeout,
        ),
      ),
    );
  });

  test('fetchLatestRelease reports client failures explicitly', () {
    final service = ReleaseInfoService(
      httpClient: MockClient(
        (request) => throw http.ClientException('offline'),
      ),
    );

    expect(
      service.fetchLatestRelease,
      throwsA(
        isA<ReleaseInfoException>().having(
          (error) => error.reason,
          'reason',
          ReleaseInfoFailureReason.networkError,
        ),
      ),
    );
  });

  test('fetchLatestRelease rejects malformed JSON', () {
    final service = serviceWithResponse(http.Response('not-json', 200));

    expect(
      service.fetchLatestRelease,
      throwsA(
        isA<ReleaseInfoException>().having(
          (error) => error.reason,
          'reason',
          ReleaseInfoFailureReason.badResponse,
        ),
      ),
    );
  });

  test('fetchLatestRelease rejects missing required release fields', () {
    final service = serviceWithResponse(
      http.Response('{"tag_name":"v1.2.3+4"}', 200),
    );

    expect(
      service.fetchLatestRelease,
      throwsA(
        isA<ReleaseInfoException>().having(
          (error) => error.reason,
          'reason',
          ReleaseInfoFailureReason.badResponse,
        ),
      ),
    );
  });

  test('fetchLatestRelease rejects tags without a build number', () {
    final service = serviceWithResponse(
      http.Response(
        '{"tag_name":"v1.2.3","html_url":"https://github.com/example/release"}',
        200,
      ),
    );

    expect(
      service.fetchLatestRelease,
      throwsA(
        isA<ReleaseInfoException>().having(
          (error) => error.reason,
          'reason',
          ReleaseInfoFailureReason.badResponse,
        ),
      ),
    );
  });

  test('compareVersions compares core version before build number', () {
    expect(compareVersions('1.0.0+2', '1.0.0+1'), greaterThan(0));
    expect(compareVersions('1.0.1+1', '1.0.0+99'), greaterThan(0));
    expect(compareVersions('1.2.0+1', '1.2.0+1'), 0);
    expect(compareVersions('1.2.0+1', '1.2.0'), greaterThan(0));
  });

  test(
    'packageVersionWithBuild keeps package version and build number together',
    () {
      expect(packageVersionWithBuild('1.0.0', '2'), '1.0.0+2');
      expect(packageVersionWithBuild('1.0.0', ''), '1.0.0');
      expect(packageVersionWithBuild('1.0.0', '1.0.0'), '1.0.0');
    },
  );
}
