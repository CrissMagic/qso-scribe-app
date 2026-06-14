import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/model_assignment_repository.dart';
import '../data/model_repository.dart';
import '../data/provider_repository.dart';
import '../domain/app_models.dart';
import 'heuristic_qso_structuring_service.dart';
import 'wav_audio.dart';

class QsoProcessingService {
  QsoProcessingService({
    required ProviderRepository providerRepository,
    required ModelAssignmentRepository modelAssignmentRepository,
    required ModelRepository modelRepository,
    required HeuristicQsoStructuringService heuristicStructuringService,
    http.Client? httpClient,
  }) : _providerRepository = providerRepository,
       _modelAssignmentRepository = modelAssignmentRepository,
       _modelRepository = modelRepository,
       _heuristicStructuringService = heuristicStructuringService,
       _httpClient = httpClient ?? http.Client();

  final ProviderRepository _providerRepository;
  final ModelAssignmentRepository _modelAssignmentRepository;
  final ModelRepository _modelRepository;
  final HeuristicQsoStructuringService _heuristicStructuringService;
  final http.Client _httpClient;

  Future<QsoDraft> createDraftFromText(
    String rawText, {
    DateTime? dateTime,
    String? audioPath,
  }) async {
    final assignment = await _assignment(ModelAssignmentTask.structuring);
    if (assignment == null) {
      return _heuristicStructuringService.createDraftFromText(
        rawText: rawText,
        audioPath: audioPath,
        dateTime: dateTime,
      );
    }
    return _structureTranscript(
      rawText: rawText,
      assignment: assignment,
      dateTime: dateTime,
      audioPath: audioPath,
    );
  }

  Future<QsoDraft> createDraftFromAudio({
    required String audioPath,
    DateTime? qsoStartedAt,
  }) async {
    final transcript = await _transcribeAudio(audioPath);
    try {
      return await createDraftFromText(
        transcript,
        audioPath: audioPath,
        dateTime: qsoStartedAt,
      );
    } catch (error) {
      throw QsoStructuringException(
        message: error.toString(),
        rawTranscript: transcript,
      );
    }
  }

  Future<QsoDraft> _structureTranscript({
    required String rawText,
    required ModelAssignment assignment,
    DateTime? dateTime,
    String? audioPath,
  }) async {
    final provider = await _providerRepository.findConnection(
      assignment.providerId,
    );
    if (provider == null) {
      throw StateError('assigned_structuring_provider_missing');
    }
    final model = await _modelById(assignment.modelId);
    if (model == null || !model.supports(ModelCapability.structuring)) {
      throw StateError('structuring_model_without_capability');
    }
    if (!_supportsOpenAiCompatibleHttp(provider)) {
      throw StateError('provider_not_openai_compatible_http');
    }

    final baseUri = _baseUri(provider);
    final response = await _httpClient.post(
      baseUri.replace(path: _joinUriPath(baseUri.path, 'chat/completions')),
      headers: {
        'Content-Type': 'application/json',
        if (provider.apiKey?.isNotEmpty ?? false)
          'Authorization': 'Bearer ${provider.apiKey}',
      },
      body: jsonEncode({
        'model': model.name,
        'response_format': {'type': 'json_object'},
        'messages': [
          {'role': 'system', 'content': _structuringSystemPrompt},
          {'role': 'user', 'content': rawText},
        ],
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('structuring_request_failed:${response.statusCode}');
    }

    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final choices = payload['choices'] as List<Object?>?;
    if (choices == null || choices.isEmpty) {
      throw StateError('structuring_response_missing_json');
    }
    final firstChoice = choices.first as Map<String, Object?>;
    final message = firstChoice['message'] as Map<String, Object?>?;
    final content = message?['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw StateError('structuring_response_missing_json');
    }

    final structured = jsonDecode(content) as Map<String, Object?>;
    return _draftFromStructuredJson(
      structured,
      rawText: rawText,
      audioPath: audioPath,
      dateTime: dateTime,
    );
  }

  QsoDraft _draftFromStructuredJson(
    Map<String, Object?> json, {
    required String rawText,
    String? audioPath,
    DateTime? dateTime,
  }) {
    final parsedDateTime =
        dateTime ?? DateTime.tryParse(_stringValue(json['dateTime']));
    return QsoDraft(
      callsign: _fieldFromJson(json, 'callsign'),
      dateTime: QsoField(
        value: parsedDateTime,
        confidence: _confidenceFromJson(json, 'dateTime'),
        sourceText: rawText,
      ),
      band: _fieldFromJson(json, 'band'),
      frequency: _fieldFromJson(json, 'frequency'),
      mode: _fieldFromJson(json, 'mode'),
      sentRst: _fieldFromJson(json, 'sentRst'),
      receivedRst: _fieldFromJson(json, 'receivedRst'),
      status: LogStatus.needsReview,
      name: _optionalFieldFromJson(json, 'name'),
      qth: _optionalFieldFromJson(json, 'qth'),
      notes: _optionalFieldFromJson(json, 'notes'),
      rig: _optionalFieldFromJson(json, 'rig'),
      antenna: _optionalFieldFromJson(json, 'antenna'),
      audioPath: audioPath,
      rawTranscript: rawText,
    );
  }

  QsoField<String> _fieldFromJson(Map<String, Object?> json, String key) {
    return QsoField(
      value: _stringValue(json[key]).trim(),
      confidence: _confidenceFromJson(json, key),
      sourceText: _stringValue(json['sourceText']).trim().isEmpty
          ? null
          : _stringValue(json['sourceText']).trim(),
    );
  }

  QsoField<String>? _optionalFieldFromJson(
    Map<String, Object?> json,
    String key,
  ) {
    final value = _stringValue(json[key]).trim();
    if (value.isEmpty) {
      return null;
    }
    return QsoField(
      value: value,
      confidence: _confidenceFromJson(json, key),
      sourceText: _stringValue(json['sourceText']).trim().isEmpty
          ? null
          : _stringValue(json['sourceText']).trim(),
    );
  }

  double _confidenceFromJson(Map<String, Object?> json, String key) {
    final confidences = json['confidence'] as Map<String, Object?>?;
    final value = confidences?[key];
    if (value is num) {
      return value.toDouble().clamp(0, 1).toDouble();
    }
    return 0.75;
  }

  String _stringValue(Object? value) {
    if (value == null) {
      return '';
    }
    return value.toString();
  }

  Future<String> _transcribeAudio(String audioPath) async {
    final assignment = await _assignment(ModelAssignmentTask.transcription);
    if (assignment == null) {
      throw StateError('no_transcription_model_assigned');
    }
    final provider = await _providerRepository.findConnection(
      assignment.providerId,
    );
    if (provider == null) {
      throw StateError('assigned_transcription_provider_missing');
    }
    final model = await _modelById(assignment.modelId);
    if (model == null || !model.supports(ModelCapability.speech)) {
      throw StateError('transcription_model_without_speech');
    }

    if (!_supportsOpenAiCompatibleHttp(provider)) {
      throw StateError('provider_not_openai_compatible_http');
    }

    final file = File(audioPath);
    if (!file.existsSync()) {
      throw StateError('audio_file_missing');
    }

    final uploadPath = await playableAudioPathFor(audioPath);
    final baseUri = _baseUri(provider);
    final request =
        http.MultipartRequest(
            'POST',
            baseUri.replace(
              path: _joinUriPath(baseUri.path, 'audio/transcriptions'),
            ),
          )
          ..fields['model'] = model.name
          ..files.add(await http.MultipartFile.fromPath('file', uploadPath));
    final apiKey = provider.apiKey;
    if (apiKey != null && apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }

    final response = await http.Response.fromStream(
      await _httpClient.send(request),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('transcription_request_failed:${response.statusCode}');
    }
    final payload = jsonDecode(response.body) as Map<String, Object?>;
    final text = payload['text'] as String?;
    if (text == null || text.trim().isEmpty) {
      throw StateError('transcription_response_missing_text');
    }
    return text;
  }

  Future<ModelAssignment?> _assignment(ModelAssignmentTask task) async {
    final assignments = await _modelAssignmentRepository.listAssignments();
    for (final assignment in assignments) {
      if (assignment.task == task) {
        return assignment;
      }
    }
    return null;
  }

  Future<AiModelOption?> _modelById(String id) async {
    final models = await _modelRepository.listModels();
    for (final model in models) {
      if (model.id == id) {
        return model;
      }
    }
    return null;
  }

  bool _supportsOpenAiCompatibleHttp(ProviderConnection provider) {
    return const {
      'OpenAI',
      'OpenAI-compatible',
      'Local endpoint',
      'DeepSeek',
      'Qwen',
      'Zhipu',
      'Gemini',
    }.contains(provider.type);
  }

  Uri _baseUri(ProviderConnection provider) {
    final baseUrl = provider.baseUrl == null || provider.baseUrl!.isEmpty
        ? 'https://api.openai.com/v1'
        : provider.baseUrl!;
    return Uri.parse(baseUrl);
  }

  String _joinUriPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    return '$normalizedBase/$suffix';
  }

  static const _structuringSystemPrompt = '''
Extract one amateur radio QSO log from the transcript.
Return JSON only. Use these keys: callsign, dateTime, band, frequency, mode, sentRst, receivedRst, name, qth, notes, rig, antenna, confidence, sourceText.
dateTime must be ISO 8601 when explicitly present; otherwise use null.
confidence must be an object with numeric 0-1 confidence for each extracted field.
Prefer the operator's latest correction when the transcript contains a spoken correction.
Do not invent missing required fields. Keep missing fields as empty strings or null.
''';
}

class QsoStructuringException implements Exception {
  const QsoStructuringException({
    required this.message,
    required this.rawTranscript,
  });

  final String message;
  final String rawTranscript;

  @override
  String toString() => message;
}
