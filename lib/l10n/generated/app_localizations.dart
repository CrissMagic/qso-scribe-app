import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'QSO Scribe'**
  String get appTitle;

  /// No description provided for @appTitleZh.
  ///
  /// In en, this message translates to:
  /// **'Tonglian Notes'**
  String get appTitleZh;

  /// No description provided for @firstRunTitle.
  ///
  /// In en, this message translates to:
  /// **'Initial Setup'**
  String get firstRunTitle;

  /// No description provided for @firstRunSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Configure essential operating choices before logging.'**
  String get firstRunSubtitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @followSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get followSystem;

  /// No description provided for @followSystemDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the device language setting'**
  String get followSystemDesc;

  /// No description provided for @simplifiedChinese.
  ///
  /// In en, this message translates to:
  /// **'Simplified Chinese'**
  String get simplifiedChinese;

  /// No description provided for @simplifiedChineseDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the Simplified Chinese interface'**
  String get simplifiedChineseDesc;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @englishDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the English interface'**
  String get englishDesc;

  /// No description provided for @transcriptionMode.
  ///
  /// In en, this message translates to:
  /// **'Transcription mode'**
  String get transcriptionMode;

  /// No description provided for @streamingMode.
  ///
  /// In en, this message translates to:
  /// **'Real-time streaming'**
  String get streamingMode;

  /// No description provided for @streamingModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Transcribe audio during the QSO when the provider supports streaming.'**
  String get streamingModeDesc;

  /// No description provided for @afterQsoMode.
  ///
  /// In en, this message translates to:
  /// **'Recognize after QSO'**
  String get afterQsoMode;

  /// No description provided for @afterQsoModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Record first, then transcribe and structure after the QSO ends.'**
  String get afterQsoModeDesc;

  /// No description provided for @failureHandling.
  ///
  /// In en, this message translates to:
  /// **'Failure handling'**
  String get failureHandling;

  /// No description provided for @showErrors.
  ///
  /// In en, this message translates to:
  /// **'Show errors immediately'**
  String get showErrors;

  /// No description provided for @showErrorsDesc.
  ///
  /// In en, this message translates to:
  /// **'Surface transcription or structuring errors during the workflow.'**
  String get showErrorsDesc;

  /// No description provided for @degradeSilently.
  ///
  /// In en, this message translates to:
  /// **'Degrade silently'**
  String get degradeSilently;

  /// No description provided for @degradeSilentlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep partial transcript and let the operator finish the contact.'**
  String get degradeSilentlyDesc;

  /// No description provided for @completeSetup.
  ///
  /// In en, this message translates to:
  /// **'Complete setup'**
  String get completeSetup;

  /// No description provided for @record.
  ///
  /// In en, this message translates to:
  /// **'Record'**
  String get record;

  /// No description provided for @logs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get logs;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @startQso.
  ///
  /// In en, this message translates to:
  /// **'Start QSO'**
  String get startQso;

  /// No description provided for @endQso.
  ///
  /// In en, this message translates to:
  /// **'End QSO'**
  String get endQso;

  /// No description provided for @liveTranscript.
  ///
  /// In en, this message translates to:
  /// **'Live transcript'**
  String get liveTranscript;

  /// No description provided for @recordingPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Waiting for audio input...'**
  String get recordingPlaceholder;

  /// No description provided for @draftEntry.
  ///
  /// In en, this message translates to:
  /// **'Draft entry'**
  String get draftEntry;

  /// No description provided for @callsign.
  ///
  /// In en, this message translates to:
  /// **'Callsign'**
  String get callsign;

  /// No description provided for @dateTime.
  ///
  /// In en, this message translates to:
  /// **'Date/time'**
  String get dateTime;

  /// No description provided for @band.
  ///
  /// In en, this message translates to:
  /// **'Band'**
  String get band;

  /// No description provided for @frequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency'**
  String get frequency;

  /// No description provided for @mode.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get mode;

  /// No description provided for @sentRst.
  ///
  /// In en, this message translates to:
  /// **'Sent RST'**
  String get sentRst;

  /// No description provided for @receivedRst.
  ///
  /// In en, this message translates to:
  /// **'Received RST'**
  String get receivedRst;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @qth.
  ///
  /// In en, this message translates to:
  /// **'QTH'**
  String get qth;

  /// No description provided for @notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// No description provided for @rig.
  ///
  /// In en, this message translates to:
  /// **'Rig'**
  String get rig;

  /// No description provided for @antenna.
  ///
  /// In en, this message translates to:
  /// **'Antenna'**
  String get antenna;

  /// No description provided for @optionalFields.
  ///
  /// In en, this message translates to:
  /// **'Optional fields'**
  String get optionalFields;

  /// No description provided for @lowConfidence.
  ///
  /// In en, this message translates to:
  /// **'Low confidence'**
  String get lowConfidence;

  /// No description provided for @aiFilled.
  ///
  /// In en, this message translates to:
  /// **'AI filled'**
  String get aiFilled;

  /// No description provided for @userEdited.
  ///
  /// In en, this message translates to:
  /// **'User edited'**
  String get userEdited;

  /// No description provided for @saveQso.
  ///
  /// In en, this message translates to:
  /// **'Save QSO'**
  String get saveQso;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @recentSession.
  ///
  /// In en, this message translates to:
  /// **'Recent session'**
  String get recentSession;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get draft;

  /// No description provided for @needsReview.
  ///
  /// In en, this message translates to:
  /// **'Needs review'**
  String get needsReview;

  /// No description provided for @confirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get confirmed;

  /// No description provided for @exported.
  ///
  /// In en, this message translates to:
  /// **'Exported'**
  String get exported;

  /// No description provided for @failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failed;

  /// No description provided for @searchLogs.
  ///
  /// In en, this message translates to:
  /// **'Search callsign, grid, or notes'**
  String get searchLogs;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @dateRange.
  ///
  /// In en, this message translates to:
  /// **'Date range'**
  String get dateRange;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @importAudio.
  ///
  /// In en, this message translates to:
  /// **'Import audio file'**
  String get importAudio;

  /// No description provided for @importAudioDesc.
  ///
  /// In en, this message translates to:
  /// **'Select WAV, M4A, or MP3 audio for recognition.'**
  String get importAudioDesc;

  /// No description provided for @importText.
  ///
  /// In en, this message translates to:
  /// **'Paste or import text'**
  String get importText;

  /// No description provided for @importTextDesc.
  ///
  /// In en, this message translates to:
  /// **'Paste raw transcript or notes to structure QSOs.'**
  String get importTextDesc;

  /// No description provided for @recentImports.
  ///
  /// In en, this message translates to:
  /// **'Recent imports'**
  String get recentImports;

  /// No description provided for @exportLogs.
  ///
  /// In en, this message translates to:
  /// **'Export logs'**
  String get exportLogs;

  /// No description provided for @exportDesc.
  ///
  /// In en, this message translates to:
  /// **'Generate ADIF, CSV, or raw transcript files.'**
  String get exportDesc;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @rawTranscript.
  ///
  /// In en, this message translates to:
  /// **'Raw transcript text'**
  String get rawTranscript;

  /// No description provided for @selectedForExport.
  ///
  /// In en, this message translates to:
  /// **'QSOs selected for export'**
  String get selectedForExport;

  /// No description provided for @exportToFile.
  ///
  /// In en, this message translates to:
  /// **'Export to file'**
  String get exportToFile;

  /// No description provided for @providerManagement.
  ///
  /// In en, this message translates to:
  /// **'Provider management'**
  String get providerManagement;

  /// No description provided for @providerManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'API keys and endpoints'**
  String get providerManagementDesc;

  /// No description provided for @modelAssignment.
  ///
  /// In en, this message translates to:
  /// **'Model assignment'**
  String get modelAssignment;

  /// No description provided for @modelAssignmentDesc.
  ///
  /// In en, this message translates to:
  /// **'Assign models to workflow tasks'**
  String get modelAssignmentDesc;

  /// No description provided for @audioRetention.
  ///
  /// In en, this message translates to:
  /// **'Audio retention'**
  String get audioRetention;

  /// No description provided for @audioRetentionDesc.
  ///
  /// In en, this message translates to:
  /// **'Keep audio by default'**
  String get audioRetentionDesc;

  /// No description provided for @localDataManagement.
  ///
  /// In en, this message translates to:
  /// **'Local data management'**
  String get localDataManagement;

  /// No description provided for @localDataManagementDesc.
  ///
  /// In en, this message translates to:
  /// **'Backups and cleanup'**
  String get localDataManagementDesc;

  /// No description provided for @transcriptionModel.
  ///
  /// In en, this message translates to:
  /// **'Transcription model'**
  String get transcriptionModel;

  /// No description provided for @structuringModel.
  ///
  /// In en, this message translates to:
  /// **'QSO structuring model'**
  String get structuringModel;

  /// No description provided for @speech.
  ///
  /// In en, this message translates to:
  /// **'Speech'**
  String get speech;

  /// No description provided for @streaming.
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get streaming;

  /// No description provided for @text.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get text;

  /// No description provided for @structuring.
  ///
  /// In en, this message translates to:
  /// **'Structuring'**
  String get structuring;

  /// No description provided for @providerSetup.
  ///
  /// In en, this message translates to:
  /// **'Provider setup'**
  String get providerSetup;

  /// No description provided for @addProvider.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get addProvider;

  /// No description provided for @editProvider.
  ///
  /// In en, this message translates to:
  /// **'Edit provider'**
  String get editProvider;

  /// No description provided for @providerType.
  ///
  /// In en, this message translates to:
  /// **'Provider type'**
  String get providerType;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @baseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get baseUrl;

  /// No description provided for @apiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get apiKey;

  /// No description provided for @testConnection.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get testConnection;

  /// No description provided for @qsoReview.
  ///
  /// In en, this message translates to:
  /// **'QSO review'**
  String get qsoReview;

  /// No description provided for @audioLog.
  ///
  /// In en, this message translates to:
  /// **'Audio log'**
  String get audioLog;

  /// No description provided for @originalTranscript.
  ///
  /// In en, this message translates to:
  /// **'Original transcript'**
  String get originalTranscript;

  /// No description provided for @confirmAndSave.
  ///
  /// In en, this message translates to:
  /// **'Confirm and save'**
  String get confirmAndSave;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @requiredFieldsMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing required fields: callsign, date/time, frequency or band, mode, sent RST, received RST'**
  String get requiredFieldsMissing;

  /// No description provided for @importJobCreated.
  ///
  /// In en, this message translates to:
  /// **'Import job created'**
  String get importJobCreated;

  /// No description provided for @importJobCompleted.
  ///
  /// In en, this message translates to:
  /// **'Text import created a QSO for review'**
  String get importJobCompleted;

  /// No description provided for @noImportJobs.
  ///
  /// In en, this message translates to:
  /// **'No import jobs yet'**
  String get noImportJobs;

  /// No description provided for @importedText.
  ///
  /// In en, this message translates to:
  /// **'Imported text'**
  String get importedText;

  /// No description provided for @fromDate.
  ///
  /// In en, this message translates to:
  /// **'From date'**
  String get fromDate;

  /// No description provided for @toDate.
  ///
  /// In en, this message translates to:
  /// **'To date'**
  String get toDate;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to'**
  String get exportedTo;

  /// No description provided for @keepAudio.
  ///
  /// In en, this message translates to:
  /// **'Keep original audio by default'**
  String get keepAudio;

  /// No description provided for @deleteAudioAfterRecognition.
  ///
  /// In en, this message translates to:
  /// **'Delete audio after recognition'**
  String get deleteAudioAfterRecognition;

  /// No description provided for @deleteAudioAfterConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete audio after log confirmation'**
  String get deleteAudioAfterConfirmation;

  /// No description provided for @saveProvider.
  ///
  /// In en, this message translates to:
  /// **'Save provider'**
  String get saveProvider;

  /// No description provided for @providerRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Provider type and display name are required'**
  String get providerRequiredFields;

  /// No description provided for @providerSaved.
  ///
  /// In en, this message translates to:
  /// **'Provider saved'**
  String get providerSaved;

  /// No description provided for @modelAssignmentRequired.
  ///
  /// In en, this message translates to:
  /// **'Select both transcription and structuring models'**
  String get modelAssignmentRequired;

  /// No description provided for @modelAssignmentSaved.
  ///
  /// In en, this message translates to:
  /// **'Model assignment saved'**
  String get modelAssignmentSaved;

  /// No description provided for @noCompatibleModels.
  ///
  /// In en, this message translates to:
  /// **'No models match the current capability requirements'**
  String get noCompatibleModels;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get processing;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @noStreamingTranscript.
  ///
  /// In en, this message translates to:
  /// **'No live transcript yet'**
  String get noStreamingTranscript;

  /// No description provided for @noAudioFile.
  ///
  /// In en, this message translates to:
  /// **'No audio file retained'**
  String get noAudioFile;

  /// No description provided for @playAudio.
  ///
  /// In en, this message translates to:
  /// **'Play audio'**
  String get playAudio;

  /// No description provided for @stopAudio.
  ///
  /// In en, this message translates to:
  /// **'Stop playback'**
  String get stopAudio;

  /// No description provided for @audioPlaybackFailed.
  ///
  /// In en, this message translates to:
  /// **'Audio playback failed'**
  String get audioPlaybackFailed;

  /// No description provided for @noRawTranscript.
  ///
  /// In en, this message translates to:
  /// **'No raw transcript retained'**
  String get noRawTranscript;

  /// No description provided for @addModel.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get addModel;

  /// No description provided for @modelName.
  ///
  /// In en, this message translates to:
  /// **'Model name'**
  String get modelName;

  /// No description provided for @modelRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Select a provider, enter a model name, and choose at least one capability'**
  String get modelRequiredFields;

  /// No description provided for @modelSaved.
  ///
  /// In en, this message translates to:
  /// **'Model saved'**
  String get modelSaved;

  /// No description provided for @streamingAdapterNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Real-time streaming adapter is not configured; finish the QSO and review manually'**
  String get streamingAdapterNotConfigured;

  /// No description provided for @noStreamingTranscriptProduced.
  ///
  /// In en, this message translates to:
  /// **'No live transcript was produced for this QSO; review audio or fill fields manually'**
  String get noStreamingTranscriptProduced;

  /// No description provided for @microphonePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission was not granted'**
  String get microphonePermissionDenied;

  /// No description provided for @noTranscriptionModelAssigned.
  ///
  /// In en, this message translates to:
  /// **'No transcription model is assigned'**
  String get noTranscriptionModelAssigned;

  /// No description provided for @assignedTranscriptionProviderMissing.
  ///
  /// In en, this message translates to:
  /// **'Assigned transcription provider was not found'**
  String get assignedTranscriptionProviderMissing;

  /// No description provided for @transcriptionModelWithoutSpeech.
  ///
  /// In en, this message translates to:
  /// **'Assigned transcription model does not support speech'**
  String get transcriptionModelWithoutSpeech;

  /// No description provided for @providerNotOpenAiCompatibleHttp.
  ///
  /// In en, this message translates to:
  /// **'This provider is not supported for OpenAI-compatible HTTP transcription in the first version'**
  String get providerNotOpenAiCompatibleHttp;

  /// No description provided for @audioFileMissing.
  ///
  /// In en, this message translates to:
  /// **'Audio file does not exist'**
  String get audioFileMissing;

  /// No description provided for @transcriptionRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Transcription request failed'**
  String get transcriptionRequestFailed;

  /// No description provided for @transcriptionResponseMissingText.
  ///
  /// In en, this message translates to:
  /// **'Transcription response did not include text'**
  String get transcriptionResponseMissingText;

  /// No description provided for @assignedStructuringProviderMissing.
  ///
  /// In en, this message translates to:
  /// **'Assigned structuring provider was not found'**
  String get assignedStructuringProviderMissing;

  /// No description provided for @structuringModelWithoutCapability.
  ///
  /// In en, this message translates to:
  /// **'Assigned structuring model does not support structuring'**
  String get structuringModelWithoutCapability;

  /// No description provided for @structuringRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Structuring request failed'**
  String get structuringRequestFailed;

  /// No description provided for @structuringResponseMissingJson.
  ///
  /// In en, this message translates to:
  /// **'Structuring response did not include valid JSON'**
  String get structuringResponseMissingJson;

  /// No description provided for @bandOrFrequencyRequired.
  ///
  /// In en, this message translates to:
  /// **'Fill either band or frequency'**
  String get bandOrFrequencyRequired;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @noLogsMatchFilters.
  ///
  /// In en, this message translates to:
  /// **'No logs match the current filters'**
  String get noLogsMatchFilters;

  /// No description provided for @audioImportManualReview.
  ///
  /// In en, this message translates to:
  /// **'Audio import was kept for manual review'**
  String get audioImportManualReview;

  /// No description provided for @exportHistory.
  ///
  /// In en, this message translates to:
  /// **'Export history'**
  String get exportHistory;

  /// No description provided for @noExportHistory.
  ///
  /// In en, this message translates to:
  /// **'No export history yet'**
  String get noExportHistory;

  /// No description provided for @qsoCountUnit.
  ///
  /// In en, this message translates to:
  /// **'QSOs'**
  String get qsoCountUnit;

  /// No description provided for @exportPath.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get exportPath;

  /// No description provided for @filterSummary.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filterSummary;

  /// No description provided for @generatedLog.
  ///
  /// In en, this message translates to:
  /// **'Generated QSO'**
  String get generatedLog;

  /// No description provided for @errorDetail.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorDetail;

  /// No description provided for @audioSource.
  ///
  /// In en, this message translates to:
  /// **'Audio import'**
  String get audioSource;

  /// No description provided for @textSource.
  ///
  /// In en, this message translates to:
  /// **'Text import'**
  String get textSource;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @localDataOverview.
  ///
  /// In en, this message translates to:
  /// **'Local data overview'**
  String get localDataOverview;

  /// No description provided for @retainedAudioFiles.
  ///
  /// In en, this message translates to:
  /// **'Retained audio files'**
  String get retainedAudioFiles;

  /// No description provided for @rawTranscriptEntries.
  ///
  /// In en, this message translates to:
  /// **'Raw transcript entries'**
  String get rawTranscriptEntries;

  /// No description provided for @deleteAllRetainedAudio.
  ///
  /// In en, this message translates to:
  /// **'Delete retained audio'**
  String get deleteAllRetainedAudio;

  /// No description provided for @clearAllRawTranscripts.
  ///
  /// In en, this message translates to:
  /// **'Clear raw transcripts'**
  String get clearAllRawTranscripts;

  /// No description provided for @deleteAllRetainedAudioConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete app-retained audio files and clear their log references? Audio files outside app storage will not be removed.'**
  String get deleteAllRetainedAudioConfirm;

  /// No description provided for @clearAllRawTranscriptsConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear raw transcript text from QSO logs and import records? Structured QSO fields will be kept.'**
  String get clearAllRawTranscriptsConfirm;

  /// No description provided for @localDataCleanupComplete.
  ///
  /// In en, this message translates to:
  /// **'Local data cleanup completed'**
  String get localDataCleanupComplete;

  /// No description provided for @deleteRetainedAudio.
  ///
  /// In en, this message translates to:
  /// **'Delete retained audio'**
  String get deleteRetainedAudio;

  /// No description provided for @deleteRawTranscript.
  ///
  /// In en, this message translates to:
  /// **'Delete raw transcript'**
  String get deleteRawTranscript;

  /// No description provided for @deleteRetainedAudioConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this app-retained audio file and clear the log reference? Audio files outside app storage will not be removed.'**
  String get deleteRetainedAudioConfirm;

  /// No description provided for @deleteRawTranscriptConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear this raw transcript text? Structured QSO fields will be kept.'**
  String get deleteRawTranscriptConfirm;

  /// No description provided for @noConfiguredProviders.
  ///
  /// In en, this message translates to:
  /// **'No providers have been added yet. Add a provider before assigning models.'**
  String get noConfiguredProviders;

  /// No description provided for @savedModels.
  ///
  /// In en, this message translates to:
  /// **'Saved models'**
  String get savedModels;

  /// No description provided for @apiKeySaved.
  ///
  /// In en, this message translates to:
  /// **'API key saved'**
  String get apiKeySaved;

  /// No description provided for @apiKeyNotSaved.
  ///
  /// In en, this message translates to:
  /// **'No API key saved'**
  String get apiKeyNotSaved;

  /// No description provided for @fetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch models'**
  String get fetchModels;

  /// No description provided for @connectionTestSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Connection test succeeded'**
  String get connectionTestSucceeded;

  /// No description provided for @modelsFetched.
  ///
  /// In en, this message translates to:
  /// **'models fetched'**
  String get modelsFetched;

  /// No description provided for @noModelsSaved.
  ///
  /// In en, this message translates to:
  /// **'No saved models for the selected provider'**
  String get noModelsSaved;

  /// No description provided for @baseUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Base URL is required'**
  String get baseUrlRequired;

  /// No description provided for @modelListRequestFailed.
  ///
  /// In en, this message translates to:
  /// **'Model list request failed'**
  String get modelListRequestFailed;

  /// No description provided for @modelListEmpty.
  ///
  /// In en, this message translates to:
  /// **'Model list response was empty'**
  String get modelListEmpty;

  /// No description provided for @modelListAllCandidatesFailed.
  ///
  /// In en, this message translates to:
  /// **'All model list endpoints failed'**
  String get modelListAllCandidatesFailed;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @rawTranscriptDeleted.
  ///
  /// In en, this message translates to:
  /// **'Raw transcript cleared'**
  String get rawTranscriptDeleted;

  /// No description provided for @retainedAudioDeleted.
  ///
  /// In en, this message translates to:
  /// **'Audio deleted'**
  String get retainedAudioDeleted;

  /// No description provided for @contactInfo.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contactInfo;

  /// No description provided for @operatorInfo.
  ///
  /// In en, this message translates to:
  /// **'Operator'**
  String get operatorInfo;

  /// No description provided for @stationInfo.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get stationInfo;

  /// No description provided for @notesSection.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesSection;

  /// No description provided for @suggestedBand.
  ///
  /// In en, this message translates to:
  /// **'Suggested band'**
  String get suggestedBand;

  /// No description provided for @invalidFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency must be between 0.1 and 30000 MHz'**
  String get invalidFrequency;

  /// No description provided for @providerTypeHint.
  ///
  /// In en, this message translates to:
  /// **'If unsure, choose OpenAI'**
  String get providerTypeHint;

  /// No description provided for @baseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'Ends with /v1, e.g. https://api.openai.com/v1'**
  String get baseUrlHint;

  /// No description provided for @apiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'Paste from provider console. Stored locally, never uploaded.'**
  String get apiKeyHint;

  /// No description provided for @displayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Any label you recognize, e.g. My OpenAI'**
  String get displayNameHint;

  /// No description provided for @modelNameHint.
  ///
  /// In en, this message translates to:
  /// **'Model ID, e.g. gpt-4o-mini / whisper-1'**
  String get modelNameHint;

  /// No description provided for @providerTemplate.
  ///
  /// In en, this message translates to:
  /// **'Quick template'**
  String get providerTemplate;

  /// No description provided for @capabilityHint.
  ///
  /// In en, this message translates to:
  /// **'Pick what this model can do'**
  String get capabilityHint;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
