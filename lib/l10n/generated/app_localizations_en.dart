// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'QSO Scribe';

  @override
  String get appTitleZh => 'Tonglian Notes';

  @override
  String get firstRunTitle => 'Initial Setup';

  @override
  String get firstRunSubtitle =>
      'Configure essential operating choices before logging.';

  @override
  String get language => 'Language';

  @override
  String get followSystem => 'Follow system';

  @override
  String get followSystemDesc => 'Use the device language setting';

  @override
  String get simplifiedChinese => 'Simplified Chinese';

  @override
  String get simplifiedChineseDesc => 'Use the Simplified Chinese interface';

  @override
  String get english => 'English';

  @override
  String get englishDesc => 'Use the English interface';

  @override
  String get transcriptionMode => 'Transcription mode';

  @override
  String get streamingMode => 'Real-time streaming';

  @override
  String get streamingModeDesc =>
      'Transcribe audio during the QSO when the provider supports streaming.';

  @override
  String get afterQsoMode => 'Recognize after QSO';

  @override
  String get afterQsoModeDesc =>
      'Record first, then transcribe and structure after the QSO ends.';

  @override
  String get failureHandling => 'Failure handling';

  @override
  String get showErrors => 'Show errors immediately';

  @override
  String get showErrorsDesc =>
      'Surface transcription or structuring errors during the workflow.';

  @override
  String get degradeSilently => 'Degrade silently';

  @override
  String get degradeSilentlyDesc =>
      'Keep partial transcript and let the operator finish the contact.';

  @override
  String get completeSetup => 'Complete setup';

  @override
  String get record => 'Record';

  @override
  String get logs => 'Logs';

  @override
  String get import => 'Import';

  @override
  String get export => 'Export';

  @override
  String get settings => 'Settings';

  @override
  String get startQso => 'Start QSO';

  @override
  String get endQso => 'End QSO';

  @override
  String get liveTranscript => 'Live transcript';

  @override
  String get recordingPlaceholder => 'Waiting for audio input...';

  @override
  String get draftEntry => 'Draft entry';

  @override
  String get callsign => 'Callsign';

  @override
  String get dateTime => 'Date/time';

  @override
  String get band => 'Band';

  @override
  String get frequency => 'Frequency';

  @override
  String get mode => 'Mode';

  @override
  String get sentRst => 'Sent RST';

  @override
  String get receivedRst => 'Received RST';

  @override
  String get name => 'Name';

  @override
  String get qth => 'QTH';

  @override
  String get notes => 'Notes';

  @override
  String get rig => 'Rig';

  @override
  String get antenna => 'Antenna';

  @override
  String get optionalFields => 'Optional fields';

  @override
  String get lowConfidence => 'Low confidence';

  @override
  String get aiFilled => 'AI filled';

  @override
  String get userEdited => 'User edited';

  @override
  String get saveQso => 'Save QSO';

  @override
  String get clear => 'Clear';

  @override
  String get recentSession => 'Recent session';

  @override
  String get status => 'Status';

  @override
  String get draft => 'Draft';

  @override
  String get needsReview => 'Needs review';

  @override
  String get confirmed => 'Confirmed';

  @override
  String get exported => 'Exported';

  @override
  String get failed => 'Failed';

  @override
  String get searchLogs => 'Search callsign, grid, or notes';

  @override
  String get filters => 'Filters';

  @override
  String get dateRange => 'Date range';

  @override
  String get all => 'All';

  @override
  String get loadMore => 'Load more';

  @override
  String get importAudio => 'Import audio file';

  @override
  String get importAudioDesc =>
      'Select WAV, M4A, or MP3 audio for recognition.';

  @override
  String get importText => 'Paste or import text';

  @override
  String get importTextDesc =>
      'Paste raw transcript or notes to structure QSOs.';

  @override
  String get recentImports => 'Recent imports';

  @override
  String get exportLogs => 'Export logs';

  @override
  String get exportDesc => 'Generate ADIF, CSV, or raw transcript files.';

  @override
  String get format => 'Format';

  @override
  String get rawTranscript => 'Raw transcript text';

  @override
  String get selectedForExport => 'QSOs selected for export';

  @override
  String get exportToFile => 'Export to file';

  @override
  String get providerManagement => 'Provider management';

  @override
  String get providerManagementDesc => 'API keys and endpoints';

  @override
  String get modelAssignment => 'Model assignment';

  @override
  String get modelAssignmentDesc => 'Assign models to workflow tasks';

  @override
  String get audioRetention => 'Audio retention';

  @override
  String get audioRetentionDesc => 'Keep audio by default';

  @override
  String get localDataManagement => 'Local data management';

  @override
  String get localDataManagementDesc => 'Backups and cleanup';

  @override
  String get transcriptionModel => 'Transcription model';

  @override
  String get structuringModel => 'QSO structuring model';

  @override
  String get speech => 'Speech';

  @override
  String get streaming => 'Streaming';

  @override
  String get text => 'Text';

  @override
  String get structuring => 'Structuring';

  @override
  String get providerSetup => 'Provider setup';

  @override
  String get addProvider => 'Add provider';

  @override
  String get editProvider => 'Edit provider';

  @override
  String get providerType => 'Provider type';

  @override
  String get displayName => 'Display name';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get apiKey => 'API key';

  @override
  String get testConnection => 'Test connection';

  @override
  String get qsoReview => 'QSO review';

  @override
  String get audioLog => 'Audio log';

  @override
  String get originalTranscript => 'Original transcript';

  @override
  String get confirmAndSave => 'Confirm and save';

  @override
  String get required => 'Required';

  @override
  String get requiredFieldsMissing =>
      'Missing required fields: callsign, date/time, frequency or band, mode, sent RST, received RST';

  @override
  String get importJobCreated => 'Import job created';

  @override
  String get importJobCompleted => 'Text import created a QSO for review';

  @override
  String get noImportJobs => 'No import jobs yet';

  @override
  String get importedText => 'Imported text';

  @override
  String get fromDate => 'From date';

  @override
  String get toDate => 'To date';

  @override
  String get exportedTo => 'Exported to';

  @override
  String get keepAudio => 'Keep original audio by default';

  @override
  String get deleteAudioAfterRecognition => 'Delete audio after recognition';

  @override
  String get deleteAudioAfterConfirmation =>
      'Delete audio after log confirmation';

  @override
  String get saveProvider => 'Save provider';

  @override
  String get providerRequiredFields =>
      'Provider type and display name are required';

  @override
  String get providerSaved => 'Provider saved';

  @override
  String get modelAssignmentRequired =>
      'Select both transcription and structuring models';

  @override
  String get modelAssignmentSaved => 'Model assignment saved';

  @override
  String get noCompatibleModels =>
      'No models match the current capability requirements';

  @override
  String get pending => 'Pending';

  @override
  String get processing => 'Processing';

  @override
  String get completed => 'Completed';

  @override
  String get noStreamingTranscript => 'No live transcript yet';

  @override
  String get noAudioFile => 'No audio file retained';

  @override
  String get playAudio => 'Play audio';

  @override
  String get stopAudio => 'Stop playback';

  @override
  String get audioPlaybackFailed => 'Audio playback failed';

  @override
  String get noRawTranscript => 'No raw transcript retained';

  @override
  String get addModel => 'Add model';

  @override
  String get modelName => 'Model name';

  @override
  String get modelRequiredFields =>
      'Select a provider, enter a model name, and choose at least one capability';

  @override
  String get modelSaved => 'Model saved';

  @override
  String get streamingAdapterNotConfigured =>
      'Real-time streaming adapter is not configured; finish the QSO and review manually';

  @override
  String get noStreamingTranscriptProduced =>
      'No live transcript was produced for this QSO; review audio or fill fields manually';

  @override
  String get microphonePermissionDenied =>
      'Microphone permission was not granted';

  @override
  String get noTranscriptionModelAssigned =>
      'No transcription model is assigned';

  @override
  String get assignedTranscriptionProviderMissing =>
      'Assigned transcription provider was not found';

  @override
  String get transcriptionModelWithoutSpeech =>
      'Assigned transcription model does not support speech';

  @override
  String get providerNotOpenAiCompatibleHttp =>
      'This provider is not supported for OpenAI-compatible HTTP transcription in the first version';

  @override
  String get audioFileMissing => 'Audio file does not exist';

  @override
  String get transcriptionRequestFailed => 'Transcription request failed';

  @override
  String get transcriptionResponseMissingText =>
      'Transcription response did not include text';

  @override
  String get assignedStructuringProviderMissing =>
      'Assigned structuring provider was not found';

  @override
  String get structuringModelWithoutCapability =>
      'Assigned structuring model does not support structuring';

  @override
  String get structuringRequestFailed => 'Structuring request failed';

  @override
  String get structuringResponseMissingJson =>
      'Structuring response did not include valid JSON';

  @override
  String get bandOrFrequencyRequired => 'Fill either band or frequency';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String get noLogsMatchFilters => 'No logs match the current filters';

  @override
  String get audioImportManualReview =>
      'Audio import was kept for manual review';

  @override
  String get exportHistory => 'Export history';

  @override
  String get noExportHistory => 'No export history yet';

  @override
  String get qsoCountUnit => 'QSOs';

  @override
  String get exportPath => 'File';

  @override
  String get filterSummary => 'Filters';

  @override
  String get generatedLog => 'Generated QSO';

  @override
  String get errorDetail => 'Error';

  @override
  String get audioSource => 'Audio import';

  @override
  String get textSource => 'Text import';

  @override
  String get delete => 'Delete';

  @override
  String get localDataOverview => 'Local data overview';

  @override
  String get retainedAudioFiles => 'Retained audio files';

  @override
  String get rawTranscriptEntries => 'Raw transcript entries';

  @override
  String get deleteAllRetainedAudio => 'Delete retained audio';

  @override
  String get clearAllRawTranscripts => 'Clear raw transcripts';

  @override
  String get deleteAllRetainedAudioConfirm =>
      'Delete app-retained audio files and clear their log references? Audio files outside app storage will not be removed.';

  @override
  String get clearAllRawTranscriptsConfirm =>
      'Clear raw transcript text from QSO logs and import records? Structured QSO fields will be kept.';

  @override
  String get localDataCleanupComplete => 'Local data cleanup completed';

  @override
  String get deleteRetainedAudio => 'Delete retained audio';

  @override
  String get deleteRawTranscript => 'Delete raw transcript';

  @override
  String get deleteRetainedAudioConfirm =>
      'Delete this app-retained audio file and clear the log reference? Audio files outside app storage will not be removed.';

  @override
  String get deleteRawTranscriptConfirm =>
      'Clear this raw transcript text? Structured QSO fields will be kept.';

  @override
  String get noConfiguredProviders =>
      'No providers have been added yet. Add a provider before assigning models.';

  @override
  String get savedModels => 'Saved models';

  @override
  String get apiKeySaved => 'API key saved';

  @override
  String get apiKeyNotSaved => 'No API key saved';

  @override
  String get fetchModels => 'Fetch models';

  @override
  String get connectionTestSucceeded => 'Connection test succeeded';

  @override
  String get modelsFetched => 'models fetched';

  @override
  String get noModelsSaved => 'No saved models for the selected provider';

  @override
  String get baseUrlRequired => 'Base URL is required';

  @override
  String get modelListRequestFailed => 'Model list request failed';

  @override
  String get modelListEmpty => 'Model list response was empty';

  @override
  String get modelListAllCandidatesFailed => 'All model list endpoints failed';

  @override
  String get undo => 'Undo';

  @override
  String get rawTranscriptDeleted => 'Raw transcript cleared';

  @override
  String get retainedAudioDeleted => 'Audio deleted';

  @override
  String get contactInfo => 'Contact';

  @override
  String get operatorInfo => 'Operator';

  @override
  String get stationInfo => 'Station';

  @override
  String get notesSection => 'Notes';

  @override
  String get suggestedBand => 'Suggested band';

  @override
  String get invalidFrequency => 'Frequency must be between 0.1 and 30000 MHz';

  @override
  String get providerTypeHint => 'If unsure, choose OpenAI';

  @override
  String get baseUrlHint => 'Ends with /v1, e.g. https://api.openai.com/v1';

  @override
  String get apiKeyHint =>
      'Paste from provider console. Stored locally, never uploaded.';

  @override
  String get displayNameHint => 'Any label you recognize, e.g. My OpenAI';

  @override
  String get modelNameHint => 'Model ID, e.g. gpt-4o-mini / whisper-1';

  @override
  String get providerTemplate => 'Quick template';

  @override
  String get capabilityHint => 'Pick what this model can do';

  @override
  String get softwareUpdate => 'Software update';

  @override
  String get softwareUpdateDesc => 'Check the latest version and release notes';

  @override
  String get checkUpdate => 'Check for updates';

  @override
  String get currentVersion => 'Current version';

  @override
  String get latestVersion => 'Latest version';

  @override
  String get upToDate => 'You are on the latest version';

  @override
  String get newVersionAvailable => 'A new version is available';

  @override
  String get updateNotes => 'Release notes';

  @override
  String get goToDownload => 'Download on GitHub';

  @override
  String get updateCheckFailed => 'Update check failed';

  @override
  String get noReleaseAvailable => 'No release is available yet';

  @override
  String get retry => 'Retry';

  @override
  String get updatePreferences => 'Update settings';

  @override
  String get checkUpdatesOnStartup => 'Check for updates on startup';

  @override
  String get checkUpdatesOnStartupDesc =>
      'Check GitHub Releases after entering the main screen';

  @override
  String get viewUpdate => 'View';

  @override
  String get updatePackage => 'Package';

  @override
  String get updateAsset => 'File';

  @override
  String get updateSize => 'Size';

  @override
  String get updateDigest => 'SHA-256';

  @override
  String get downloadProgress => 'Download progress';

  @override
  String get downloadAndOpenInstaller => 'Download, then open install prompt';

  @override
  String get backgroundDownload => 'Background download';

  @override
  String get downloadThenOpenInstaller =>
      'Install prompt will open after download';

  @override
  String get backgroundDownloading => 'Downloading in background';

  @override
  String get updateDownloaded => 'Download complete';

  @override
  String get openInstaller => 'Open install prompt';

  @override
  String get updateNetworkFailed => 'Network connection failed';

  @override
  String get updateTimeout => 'Request timed out';

  @override
  String get updateBadResponse =>
      'Release metadata was not in the expected format';

  @override
  String get updateFileSystemFailed => 'Could not write the package';

  @override
  String get updateChecksumMismatch => 'Package checksum did not match';

  @override
  String get installPermissionRequired =>
      'Allow this app to install unknown apps';

  @override
  String get installerUnavailable => 'No system installer is available';

  @override
  String get invalidApkPath => 'Package path is invalid';
}
