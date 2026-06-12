import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/app_models.dart';

const _knownCompatSuffixes = [
  '/api/claudecode',
  '/api/anthropic',
  '/apps/anthropic',
  '/api/coding',
  '/claudecode',
  '/anthropic',
  '/step_plan',
  '/coding',
  '/claude',
];

class ProviderModelFetchService {
  ProviderModelFetchService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<List<FetchedProviderModel>> fetchModels({
    required String baseUrl,
    required String? apiKey,
  }) async {
    final candidates = buildModelListUrlCandidates(baseUrl);
    String? lastError;
    for (final url in candidates) {
      final response = await _httpClient
          .get(
            Uri.parse(url),
            headers: {
              if (apiKey != null && apiKey.trim().isNotEmpty)
                'Authorization': 'Bearer ${apiKey.trim()}',
            },
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = jsonDecode(response.body) as Map<String, Object?>;
        final data = payload['data'] as List<Object?>? ?? const [];
        final models =
            data
                .whereType<Map<String, Object?>>()
                .map((item) => item['id'] as String?)
                .whereType<String>()
                .where((id) => id.trim().isNotEmpty)
                .map(
                  (id) => FetchedProviderModel(
                    id: id.trim(),
                    capabilities: inferModelCapabilities(id),
                  ),
                )
                .toList()
              ..sort((a, b) => a.id.compareTo(b.id));
        return models;
      }
      if (response.statusCode == 404 || response.statusCode == 405) {
        lastError = 'HTTP ${response.statusCode}: ${_truncate(response.body)}';
        continue;
      }
      throw StateError(
        'model_list_request_failed:${response.statusCode}:${_truncate(response.body)}',
      );
    }
    throw StateError('model_list_all_candidates_failed:${lastError ?? ''}');
  }

  Future<void> testConnection({
    required String baseUrl,
    required String? apiKey,
  }) async {
    final models = await fetchModels(baseUrl: baseUrl, apiKey: apiKey);
    if (models.isEmpty) {
      throw StateError('model_list_empty');
    }
  }
}

class FetchedProviderModel {
  const FetchedProviderModel({
    required this.id,
    required this.capabilities,
    this.selected = true,
  });

  final String id;
  final Set<ModelCapability> capabilities;
  final bool selected;

  FetchedProviderModel copyWith({
    Set<ModelCapability>? capabilities,
    bool? selected,
  }) {
    return FetchedProviderModel(
      id: id,
      capabilities: capabilities ?? this.capabilities,
      selected: selected ?? this.selected,
    );
  }
}

List<String> buildModelListUrlCandidates(String baseUrl) {
  final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) {
    throw StateError('base_url_required');
  }

  final candidates = <String>[];
  if (_containsVersionSegment(trimmed)) {
    candidates.add('$trimmed/models');
    if (!_endsWithVersionSegment(trimmed)) {
      candidates.add('$trimmed/v1/models');
    } else if (!trimmed.endsWith('/v1')) {
      candidates.add('$trimmed/v1/models');
    }
  } else if (_endsWithVersionSegment(trimmed)) {
    candidates.add('$trimmed/models');
    if (!trimmed.endsWith('/v1')) {
      candidates.add('$trimmed/v1/models');
    }
  } else {
    candidates.add('$trimmed/v1/models');
  }

  final stripped = _stripCompatSuffix(trimmed);
  if (stripped != null && stripped.contains('://')) {
    final root = stripped.replaceFirst(RegExp(r'/+$'), '');
    candidates.add('$root/v1/models');
    candidates.add('$root/models');
  }

  final unique = <String>[];
  for (final candidate in candidates) {
    if (!unique.contains(candidate)) {
      unique.add(candidate);
    }
  }
  return unique;
}

Set<ModelCapability> inferModelCapabilities(String modelId) {
  final lower = modelId.toLowerCase();
  if (lower.contains('realtime') || lower.contains('live')) {
    return {ModelCapability.speech, ModelCapability.streaming};
  }
  if (lower.contains('whisper') ||
      lower.contains('transcribe') ||
      lower.contains('stt') ||
      lower.contains('audio')) {
    return {ModelCapability.speech};
  }
  return {ModelCapability.text, ModelCapability.structuring};
}

bool _endsWithVersionSegment(String value) {
  final segment = value.split('/').last;
  return _isVersionSegment(segment);
}

bool _containsVersionSegment(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) {
    return false;
  }
  return uri.pathSegments.any(_isVersionSegment);
}

bool _isVersionSegment(String segment) {
  if (!segment.startsWith('v') || segment.length == 1) {
    return false;
  }
  final tail = segment.substring(1);
  final numericPrefix = RegExp(r'^\d+').firstMatch(tail)?.group(0);
  return numericPrefix != null;
}

String? _stripCompatSuffix(String baseUrl) {
  for (final suffix in _knownCompatSuffixes) {
    if (baseUrl.endsWith(suffix)) {
      return baseUrl.substring(0, baseUrl.length - suffix.length);
    }
  }
  return null;
}

String _truncate(String value) {
  const maxLength = 512;
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}
