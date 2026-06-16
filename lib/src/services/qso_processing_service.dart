import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/model_assignment_repository.dart';
import '../data/model_repository.dart';
import '../data/provider_repository.dart';
import '../data/token_usage_repository.dart';
import '../domain/app_models.dart';
import '../domain/provider_catalog.dart';
import 'ai_provider_clients.dart';
import 'heuristic_qso_structuring_service.dart';

class QsoProcessingService {
  QsoProcessingService({
    required ProviderRepository providerRepository,
    required ModelAssignmentRepository modelAssignmentRepository,
    required ModelRepository modelRepository,
    required HeuristicQsoStructuringService heuristicStructuringService,
    required TokenUsageRepository tokenUsageRepository,
    http.Client? httpClient,
  }) : _providerRepository = providerRepository,
       _modelAssignmentRepository = modelAssignmentRepository,
       _modelRepository = modelRepository,
       _heuristicStructuringService = heuristicStructuringService,
       _tokenUsageRepository = tokenUsageRepository,
       _httpClient = httpClient ?? http.Client() {
    _asrClient = ProviderAsrClient(_httpClient);
    _structuringClient = ProviderStructuringClient(_httpClient);
  }

  final ProviderRepository _providerRepository;
  final ModelAssignmentRepository _modelAssignmentRepository;
  final ModelRepository _modelRepository;
  final HeuristicQsoStructuringService _heuristicStructuringService;
  final TokenUsageRepository _tokenUsageRepository;
  final http.Client _httpClient;
  late final ProviderAsrClient _asrClient;
  late final ProviderStructuringClient _structuringClient;

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
    final descriptor = descriptorFor(AiProvider.fromKey(provider.type));
    final baseUrl = (provider.baseUrl != null && provider.baseUrl!.isNotEmpty)
        ? provider.baseUrl!
        : descriptor.defaultBaseUrl;

    final result = await _structuringClient.structure(
      descriptor: descriptor,
      baseUrl: baseUrl,
      apiKey: provider.apiKey,
      modelName: model.name,
      systemPrompt: _structuringSystemPrompt,
      userText: rawText,
    );
    await _recordUsage(
      provider: descriptor.provider.name,
      model: model.name,
      taskType: 'structuring',
      usage: result.usage,
    );
    final structured = jsonDecode(result.content) as Map<String, Object?>;
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
      power: _optionalFieldFromJson(json, 'power'),
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
    final descriptor = descriptorFor(AiProvider.fromKey(provider.type));
    if (!descriptor.supportsAsr) {
      throw StateError('provider_without_asr:${descriptor.provider.name}');
    }
    final baseUrl = (provider.baseUrl != null && provider.baseUrl!.isNotEmpty)
        ? provider.baseUrl!
        : descriptor.defaultBaseUrl;

    final result = await _asrClient.transcribe(
      descriptor: descriptor,
      baseUrl: baseUrl,
      apiKey: provider.apiKey,
      modelName: model.name,
      audioPath: audioPath,
    );
    await _recordUsage(
      provider: descriptor.provider.name,
      model: model.name,
      taskType: 'transcription',
      usage: result.usage,
    );
    return result.text;
  }

  Future<void> _recordUsage({
    required String provider,
    required String model,
    required String taskType,
    required TokenUsage? usage,
  }) async {
    // Token 消耗记录是辅助功能，DB 写入失败不得中断已成功的转写/结构化主流程。
    try {
      await _tokenUsageRepository.insertRecord(
        provider: provider,
        model: model,
        taskType: taskType,
        usage: usage,
      );
    } catch (_) {}
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

  static const _structuringSystemPrompt = '''
Extract one amateur radio QSO log from the transcript.
Return JSON only. Use these keys: callsign, dateTime, band, frequency, mode, sentRst, receivedRst, name, qth, notes, rig, antenna, power, confidence, sourceText.
dateTime must be ISO 8601 when explicitly present; otherwise use null.
confidence must be an object with numeric 0-1 confidence for each extracted field.
Prefer the operator's latest correction when the transcript contains a spoken correction.
Do not invent missing required fields. Keep missing fields as empty strings or null.

## Amateur Radio Terminology Reference

### Q-Codes (common in QSO context)
- QTH = location/station address → extract to qth field
- QSL = confirmation/acknowledgment
- QSO = a contact/conversation between two stations
- QRM = man-made interference
- QRN = natural/static interference
- QRP = low power operation (typically ≤5W)
- QRO = high power operation
- QRZ = "who is calling me?"
- QRT = "stop transmitting" / going off air
- QSY = change frequency
- QSB = signal fading
- QSA = signal strength (QSA1-5)
- QRA = station name/callsign
- QRG = exact frequency
- QRH = frequency instability

### Signal Reports (RST)
- RST = Readability-Signal-Tone (e.g., "59", "599")
- Readability: 1 (unreadable) to 5 (perfectly readable)
- Signal: 1 (barely perceptible) to 9 (extremely strong)
- Tone: 1 (very harsh) to 9 (perfectly pure) — CW/digital only
- Common voice: "five nine" = 59, "five nine nine" = 599 (CW)
- "5 by 9" or "five by nine" also means R=5 S=9

### Phonetic Alphabet (NATO/ITU)
Alpha=A, Bravo=B, Charlie=C, Delta=D, Echo=E, Foxtrot=F,
Golf=G, Hotel=H, India=I, Juliet=J, Kilo=K, Lima=L,
Mike=M, November=N, Oscar=O, Papa=P, Quebec=Q, Romeo=R,
Sierra=S, Tango=T, Uniform=U, Victor=V, Whiskey=W,
X-ray=X, Yankee=Y, Zulu=Z

### Callsign Patterns
- Format: prefix + digit(s) + suffix (e.g., BV2AAA, W1AW, JA1ABC)
- Chinese callsigns: B, BV, VR, 3D, V8, etc. + digit + 1-3 letters
- US callsigns: W, K, N, AA-AL, etc. + digit + 1-3 letters
- When spelled phonetically, map back to letters (e.g., "Bravo Victor Two" → "BV2")

### Common Phrases
- "CQ CQ CQ" = general call seeking any station
- "73" = best regards / goodbye
- "88" = love and kisses
- "59" / "599" = excellent signal report
- "you are" / "your RST is" = signal report follows
- "my QTH is" = my location is
- "my name is" = operator's name
- "how copy" = did you receive my transmission clearly
- "over" = your turn to transmit
- "roger" / "copy" = message received and understood
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
