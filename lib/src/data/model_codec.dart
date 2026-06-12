import '../domain/app_models.dart';

String encodeLocaleMode(AppLocaleMode value) => value.name;
String encodeTranscriptionMode(TranscriptionMode value) => value.name;
String encodeFailureHandling(FailureHandling value) => value.name;
String encodeAudioRetentionPolicy(AudioRetentionPolicy value) => value.name;
String encodeLogStatus(LogStatus value) => value.name;
String encodeModelAssignmentTask(ModelAssignmentTask value) => value.name;
String encodeImportSourceType(ImportSourceType value) => value.name;
String encodeImportJobStatus(ImportJobStatus value) => value.name;
String encodeModelCapability(ModelCapability value) => value.name;

AppLocaleMode decodeLocaleMode(String? value) {
  return AppLocaleMode.values.firstWhere(
    (item) => item.name == value,
    orElse: () => AppLocaleMode.system,
  );
}

TranscriptionMode decodeTranscriptionMode(String? value) {
  return TranscriptionMode.values.firstWhere(
    (item) => item.name == value,
    orElse: () => TranscriptionMode.streaming,
  );
}

FailureHandling decodeFailureHandling(String? value) {
  return FailureHandling.values.firstWhere(
    (item) => item.name == value,
    orElse: () => FailureHandling.alert,
  );
}

AudioRetentionPolicy decodeAudioRetentionPolicy(String? value) {
  return AudioRetentionPolicy.values.firstWhere(
    (item) => item.name == value,
    orElse: () => AudioRetentionPolicy.keep,
  );
}

LogStatus decodeLogStatus(String? value) {
  return LogStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => LogStatus.draft,
  );
}

ModelAssignmentTask decodeModelAssignmentTask(String? value) {
  return ModelAssignmentTask.values.firstWhere(
    (item) => item.name == value,
    orElse: () => ModelAssignmentTask.transcription,
  );
}

ImportSourceType decodeImportSourceType(String? value) {
  return ImportSourceType.values.firstWhere(
    (item) => item.name == value,
    orElse: () => ImportSourceType.text,
  );
}

ImportJobStatus decodeImportJobStatus(String? value) {
  return ImportJobStatus.values.firstWhere(
    (item) => item.name == value,
    orElse: () => ImportJobStatus.pending,
  );
}

ModelCapability? decodeModelCapability(String? value) {
  for (final item in ModelCapability.values) {
    if (item.name == value) {
      return item;
    }
  }
  return null;
}

int encodeBool(bool value) => value ? 1 : 0;
bool decodeBool(Object? value) =>
    value == 1 || value == true || value == 'true';

String newLocalId(String prefix) {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  return '$prefix-$now';
}
