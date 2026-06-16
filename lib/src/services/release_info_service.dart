import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

const String _kRepo = 'CrissMagic/qso-scribe-app';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.title,
    required this.notes,
    required this.htmlUrl,
    required this.apkAsset,
  });

  final String version;
  final String title;
  final String notes;
  final String htmlUrl;
  final AppReleaseAsset apkAsset;
}

class AppReleaseAsset {
  const AppReleaseAsset({
    required this.name,
    required this.downloadUrl,
    this.size,
    this.sha256Digest,
  });

  final String name;
  final String downloadUrl;
  final int? size;
  final String? sha256Digest;
}

enum ReleaseInfoFailureReason {
  noRelease,
  httpError,
  networkError,
  timeout,
  badResponse,
}

class ReleaseInfoException implements Exception {
  const ReleaseInfoException(this.reason, {this.statusCode});

  final ReleaseInfoFailureReason reason;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode == null ? '' : '-$statusCode';
    return 'ReleaseInfoException(${reason.name}$code)';
  }
}

class ReleaseInfoService {
  ReleaseInfoService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  void close() {
    _httpClient.close();
  }

  Future<AppRelease> fetchLatestRelease() async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$_kRepo/releases/latest',
    );
    final http.Response response;
    try {
      response = await _httpClient
          .get(
            uri,
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'qso-scribe-app',
            },
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.timeout);
    } on http.ClientException {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.networkError);
    }

    if (response.statusCode == 404) {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.noRelease);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ReleaseInfoException(
        ReleaseInfoFailureReason.httpError,
        statusCode: response.statusCode,
      );
    }

    final payload = _decodeJsonObject(response.body);
    final tagName = (payload['tag_name'] as String?)?.trim() ?? '';
    final version = _releaseVersionFromTag(tagName);
    final htmlUrl = (payload['html_url'] as String?)?.trim() ?? '';
    final apkAsset = _apkAssetFromAssets(payload['assets']);
    if (version.isEmpty || htmlUrl.isEmpty) {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.badResponse);
    }
    return AppRelease(
      version: version,
      title: (payload['name'] as String?)?.trim() ?? '',
      notes: (payload['body'] as String?)?.trim() ?? '',
      htmlUrl: htmlUrl,
      apkAsset: apkAsset,
    );
  }

  AppReleaseAsset _apkAssetFromAssets(Object? value) {
    if (value is! List) {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.badResponse);
    }

    Map<Object?, Object?>? selected;
    for (final item in value) {
      if (item is! Map) {
        continue;
      }
      final asset = Map<Object?, Object?>.from(item);
      final name = (item['name'] as String?)?.trim() ?? '';
      if (_isPreferredApkAssetName(name)) {
        selected = asset;
        break;
      }
      if (selected == null && name.toLowerCase().endsWith('.apk')) {
        selected = asset;
      }
    }
    if (selected == null) {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.badResponse);
    }

    final name = (selected['name'] as String?)?.trim() ?? '';
    final downloadUrl =
        (selected['browser_download_url'] as String?)?.trim() ?? '';
    final size = selected['size'];
    if (name.isEmpty || downloadUrl.isEmpty) {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.badResponse);
    }
    return AppReleaseAsset(
      name: name,
      downloadUrl: downloadUrl,
      size: size is int && size > 0 ? size : null,
      sha256Digest: _sha256Digest(selected['digest']),
    );
  }

  bool _isPreferredApkAssetName(String name) {
    final lowerName = name.toLowerCase();
    return lowerName.startsWith('qso-scribe-app-') &&
        lowerName.endsWith('-android.apk');
  }

  String? _sha256Digest(Object? value) {
    final text = (value as String?)?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final match = RegExp(r'^sha256:([a-fA-F0-9]{64})$').firstMatch(text);
    if (match == null) {
      throw const ReleaseInfoException(ReleaseInfoFailureReason.badResponse);
    }
    return match.group(1)!.toLowerCase();
  }

  Map<String, Object?> _decodeJsonObject(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        return decoded;
      }
    } on FormatException {
      // Normalized below.
    }
    throw const ReleaseInfoException(ReleaseInfoFailureReason.badResponse);
  }

  String _releaseVersionFromTag(String tagName) {
    final version = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    if (RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(version)) {
      return version;
    }
    throw const ReleaseInfoException(ReleaseInfoFailureReason.badResponse);
  }
}

int compareVersions(String a, String b) {
  final pa = _ParsedVersion.parse(a);
  final pb = _ParsedVersion.parse(b);
  final len = pa.coreSegments.length > pb.coreSegments.length
      ? pa.coreSegments.length
      : pb.coreSegments.length;
  for (var i = 0; i < len; i++) {
    final va = i < pa.coreSegments.length ? pa.coreSegments[i] : 0;
    final vb = i < pb.coreSegments.length ? pb.coreSegments[i] : 0;
    if (va != vb) {
      return va.compareTo(vb);
    }
  }
  return pa.buildNumber.compareTo(pb.buildNumber);
}

String packageVersionWithBuild(String version, String buildNumber) {
  final cleanVersion = version.trim();
  final cleanBuild = buildNumber.trim();
  if (cleanBuild.isEmpty || cleanBuild == cleanVersion) {
    return cleanVersion;
  }
  return '$cleanVersion+$cleanBuild';
}

class _ParsedVersion {
  const _ParsedVersion({required this.coreSegments, required this.buildNumber});

  final List<int> coreSegments;
  final int buildNumber;

  static _ParsedVersion parse(String version) {
    final parts = version.trim().split('+');
    final core = parts.first;
    final build = parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 0 : 0;
    return _ParsedVersion(
      coreSegments: core
          .split('.')
          .map((part) => int.tryParse(part.trim()) ?? 0)
          .toList(),
      buildNumber: build,
    );
  }
}
