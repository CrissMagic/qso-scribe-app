// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '通联随记';

  @override
  String get appTitleZh => '通联随记';

  @override
  String get firstRunTitle => '初始设置';

  @override
  String get firstRunSubtitle => '开始记录前，先配置必要的操作选项。';

  @override
  String get language => '语言';

  @override
  String get followSystem => '跟随系统';

  @override
  String get followSystemDesc => '使用系统语言设置';

  @override
  String get simplifiedChinese => '简体中文';

  @override
  String get simplifiedChineseDesc => '使用简体中文界面';

  @override
  String get english => 'English';

  @override
  String get englishDesc => '使用英文界面';

  @override
  String get transcriptionMode => '转写模式';

  @override
  String get streamingMode => '实时流式转写';

  @override
  String get streamingModeDesc => '供应商支持实时流时，通联过程中实时转写。';

  @override
  String get afterQsoMode => '结束后统一识别';

  @override
  String get afterQsoModeDesc => '先录音，通联结束后再转写和结构化。';

  @override
  String get failureHandling => '失败处理';

  @override
  String get showErrors => '立即显示错误';

  @override
  String get showErrorsDesc => '转写或结构化失败时，及时暴露错误状态。';

  @override
  String get degradeSilently => '静默降级';

  @override
  String get degradeSilentlyDesc => '保留已有转写，尽量不中断当前通联流程。';

  @override
  String get completeSetup => '完成设置';

  @override
  String get record => '记录';

  @override
  String get logs => '日志';

  @override
  String get import => '导入';

  @override
  String get export => '导出';

  @override
  String get settings => '设置';

  @override
  String get startQso => '开始通联';

  @override
  String get endQso => '结束通联';

  @override
  String get liveTranscript => '实时转写';

  @override
  String get recordingPlaceholder => '等待音频输入...';

  @override
  String get draftEntry => 'QSO 草稿';

  @override
  String get callsign => '呼号';

  @override
  String get dateTime => '日期时间';

  @override
  String get band => '波段';

  @override
  String get frequency => '频率';

  @override
  String get mode => '模式';

  @override
  String get sentRst => '发送 RST';

  @override
  String get receivedRst => '接收 RST';

  @override
  String get name => '姓名';

  @override
  String get qth => 'QTH';

  @override
  String get notes => '备注';

  @override
  String get rig => '设备';

  @override
  String get antenna => '天线';

  @override
  String get optionalFields => '选填字段';

  @override
  String get lowConfidence => '低置信度';

  @override
  String get aiFilled => 'AI 填写';

  @override
  String get userEdited => '用户修改';

  @override
  String get saveQso => '保存 QSO';

  @override
  String get clear => '清空';

  @override
  String get recentSession => '本次会话';

  @override
  String get status => '状态';

  @override
  String get draft => '草稿';

  @override
  String get needsReview => '待确认';

  @override
  String get confirmed => '已确认';

  @override
  String get exported => '已导出';

  @override
  String get failed => '失败';

  @override
  String get searchLogs => '搜索呼号、网格或备注';

  @override
  String get filters => '筛选';

  @override
  String get dateRange => '日期范围';

  @override
  String get all => '全部';

  @override
  String get loadMore => '加载更多';

  @override
  String get importAudio => '导入录音文件';

  @override
  String get importAudioDesc => '选择 WAV、M4A 或 MP3 音频进行识别。';

  @override
  String get importText => '粘贴或导入文本';

  @override
  String get importTextDesc => '粘贴原始转写或随记文本并结构化 QSO。';

  @override
  String get recentImports => '最近导入';

  @override
  String get exportLogs => '导出日志';

  @override
  String get exportDesc => '生成 ADIF、CSV 或原始转写文本。';

  @override
  String get format => '格式';

  @override
  String get rawTranscript => '原始文本';

  @override
  String get selectedForExport => '条 QSO 将被导出';

  @override
  String get exportToFile => '导出到文件';

  @override
  String get providerManagement => '供应商管理';

  @override
  String get providerManagementDesc => 'API Key 与 endpoint';

  @override
  String get modelAssignment => '模型分配';

  @override
  String get modelAssignmentDesc => '为转录和整理分配模型';

  @override
  String get audioRetention => '音频保留策略';

  @override
  String get audioRetentionDesc => '默认保留原始音频';

  @override
  String get localDataManagement => '本地数据管理';

  @override
  String get localDataManagementDesc => '备份与清理';

  @override
  String get transcriptionModel => '转录模型';

  @override
  String get structuringModel => 'QSO 整理模型';

  @override
  String get speech => '语音';

  @override
  String get streaming => '流式';

  @override
  String get text => '文本';

  @override
  String get structuring => '结构化';

  @override
  String get providerSetup => '供应商设置';

  @override
  String get addProvider => '添加供应商';

  @override
  String get editProvider => '编辑供应商';

  @override
  String get providerType => '供应商类型';

  @override
  String get displayName => '显示名称';

  @override
  String get baseUrl => 'Base URL';

  @override
  String get apiKey => 'API Key';

  @override
  String get testConnection => '测试连接';

  @override
  String get qsoReview => 'QSO 复核';

  @override
  String get audioLog => '音频记录';

  @override
  String get originalTranscript => '原始转写';

  @override
  String get confirmAndSave => '确认并保存';

  @override
  String get required => '必填';

  @override
  String get requiredFieldsMissing => '缺少必填字段：呼号、日期时间、频率或波段、模式、发送 RST、接收 RST';

  @override
  String get importJobCreated => '导入任务已创建';

  @override
  String get importJobCompleted => '文本补录已生成待确认 QSO';

  @override
  String get noImportJobs => '暂无导入任务';

  @override
  String get importedText => '文本补录';

  @override
  String get fromDate => '开始日期';

  @override
  String get toDate => '结束日期';

  @override
  String get exportedTo => '已导出到';

  @override
  String get keepAudio => '默认保留原始音频';

  @override
  String get deleteAudioAfterRecognition => '识别完成后删除音频';

  @override
  String get deleteAudioAfterConfirmation => '日志确认后删除音频';

  @override
  String get saveProvider => '保存供应商';

  @override
  String get providerRequiredFields => '供应商类型和显示名称不能为空';

  @override
  String get providerSaved => '供应商已保存';

  @override
  String get modelAssignmentRequired => '请分别选择转录模型和整理模型';

  @override
  String get modelAssignmentSaved => '模型分配已保存';

  @override
  String get noCompatibleModels => '没有匹配当前能力要求的模型';

  @override
  String get pending => '待处理';

  @override
  String get processing => '处理中';

  @override
  String get completed => '已完成';

  @override
  String get noStreamingTranscript => '尚未产生实时转写内容';

  @override
  String get noAudioFile => '未保留音频文件';

  @override
  String get playAudio => '播放音频';

  @override
  String get stopAudio => '停止播放';

  @override
  String get audioPlaybackFailed => '音频播放失败';

  @override
  String get noRawTranscript => '未保留原始转写文本';

  @override
  String get addModel => '添加模型';

  @override
  String get modelName => '模型名称';

  @override
  String get modelRequiredFields => '请选择供应商、填写模型名称并至少选择一种能力';

  @override
  String get modelSaved => '模型已保存';

  @override
  String get streamingAdapterNotConfigured => '实时流式转写适配器尚未配置；可结束后进入复核并手动补全';

  @override
  String get noStreamingTranscriptProduced => '本次通联未产生实时转写，请回放音频或手动补全字段';

  @override
  String get microphonePermissionDenied => '麦克风权限未授予';

  @override
  String get noTranscriptionModelAssigned => '尚未分配转录模型';

  @override
  String get assignedTranscriptionProviderMissing => '已分配的转录供应商不存在';

  @override
  String get transcriptionModelWithoutSpeech => '已分配的转录模型不支持语音能力';

  @override
  String get providerNotOpenAiCompatibleHttp =>
      '该供应商首版暂不支持 OpenAI-compatible HTTP 转录';

  @override
  String get audioFileMissing => '音频文件不存在';

  @override
  String get transcriptionRequestFailed => '转录请求失败';

  @override
  String get transcriptionResponseMissingText => '转录响应中没有文本内容';

  @override
  String get assignedStructuringProviderMissing => '已分配的整理供应商不存在';

  @override
  String get structuringModelWithoutCapability => '已分配的整理模型不支持结构化能力';

  @override
  String get structuringRequestFailed => '结构化请求失败';

  @override
  String get structuringResponseMissingJson => '结构化响应中没有有效 JSON';

  @override
  String get bandOrFrequencyRequired => '波段或频率至少填写一项';

  @override
  String get clearFilters => '清除筛选';

  @override
  String get noLogsMatchFilters => '没有符合当前筛选条件的日志';

  @override
  String get audioImportManualReview => '录音导入已保留，可进入复核页手动补录';

  @override
  String get exportHistory => '导出历史';

  @override
  String get noExportHistory => '暂无导出历史';

  @override
  String get qsoCountUnit => '条 QSO';

  @override
  String get exportPath => '文件';

  @override
  String get filterSummary => '筛选条件';

  @override
  String get generatedLog => '关联 QSO';

  @override
  String get errorDetail => '错误';

  @override
  String get audioSource => '录音导入';

  @override
  String get textSource => '文本导入';

  @override
  String get delete => '删除';

  @override
  String get localDataOverview => '本地数据概览';

  @override
  String get retainedAudioFiles => '已保留音频文件';

  @override
  String get rawTranscriptEntries => '原始转写内容';

  @override
  String get deleteAllRetainedAudio => '删除已保留音频';

  @override
  String get clearAllRawTranscripts => '清除原始转写';

  @override
  String get deleteAllRetainedAudioConfirm =>
      '删除 App 保留的音频文件并清空日志中的音频引用？App 存储目录外的音频文件不会被删除。';

  @override
  String get clearAllRawTranscriptsConfirm =>
      '清除 QSO 日志和导入记录中的原始转写文本？结构化 QSO 字段会保留。';

  @override
  String get localDataCleanupComplete => '本地数据清理已完成';

  @override
  String get deleteRetainedAudio => '删除已保留音频';

  @override
  String get deleteRawTranscript => '删除原始转写';

  @override
  String get deleteRetainedAudioConfirm =>
      '删除这条 App 保留的音频文件并清空日志引用？App 存储目录外的音频文件不会被删除。';

  @override
  String get deleteRawTranscriptConfirm => '清除这条原始转写文本？结构化 QSO 字段会保留。';

  @override
  String get noConfiguredProviders => '尚未添加供应商。请先添加供应商，再分配模型。';

  @override
  String get savedModels => '已保存模型';

  @override
  String get apiKeySaved => '已保存 API Key';

  @override
  String get apiKeyNotSaved => '未保存 API Key';

  @override
  String get fetchModels => '获取模型列表';

  @override
  String get connectionTestSucceeded => '连接测试成功';

  @override
  String get modelsFetched => '个模型已获取';

  @override
  String get noModelsSaved => '所选供应商下暂无已保存模型';

  @override
  String get baseUrlRequired => 'Base URL 不能为空';

  @override
  String get modelListRequestFailed => '模型列表请求失败';

  @override
  String get modelListEmpty => '模型列表响应为空';

  @override
  String get modelListAllCandidatesFailed => '所有模型列表端点均失败';

  @override
  String get undo => '撤销';

  @override
  String get rawTranscriptDeleted => '已清除原始转写';

  @override
  String get retainedAudioDeleted => '已删除音频';

  @override
  String get contactInfo => '通联';

  @override
  String get operatorInfo => '操作员';

  @override
  String get stationInfo => '电台设备';

  @override
  String get notesSection => '备注';

  @override
  String get suggestedBand => '建议波段';

  @override
  String get invalidFrequency => '频率必须在 0.1 至 30000 MHz 之间';

  @override
  String get providerTypeHint => '选择一个受支持的供应商';

  @override
  String get baseUrlHint => '通常以 /v1 结尾,如 https://api.openai.com/v1';

  @override
  String get apiKeyHint => '从供应商控制台复制,本地存储,不会上传';

  @override
  String get displayNameHint => '随便起一个你认得出的名字';

  @override
  String get modelNameHint => '模型 ID,如 gpt-4o-mini / whisper-1';

  @override
  String get providerTemplate => '一键模板';

  @override
  String get capabilityHint => '勾选这个模型能做什么';

  @override
  String get softwareUpdate => '软件更新';

  @override
  String get softwareUpdateDesc => '检查最新版本与更新说明';

  @override
  String get checkUpdate => '检查更新';

  @override
  String get currentVersion => '当前版本';

  @override
  String get latestVersion => '最新版本';

  @override
  String get upToDate => '已是最新版本';

  @override
  String get newVersionAvailable => '发现新版本';

  @override
  String get updateNotes => '更新说明';

  @override
  String get goToDownload => '前往 GitHub 下载';

  @override
  String get updateCheckFailed => '检查更新失败';

  @override
  String get noReleaseAvailable => '暂无可用的发布版本';

  @override
  String get retry => '重试';

  @override
  String get updatePreferences => '更新设置';

  @override
  String get checkUpdatesOnStartup => '启动时检查更新';

  @override
  String get checkUpdatesOnStartupDesc => '进入主界面后自动检查 GitHub Release';

  @override
  String get viewUpdate => '查看';

  @override
  String get updatePackage => '安装包';

  @override
  String get updateAsset => '文件';

  @override
  String get updateSize => '大小';

  @override
  String get updateDigest => 'SHA-256';

  @override
  String get downloadProgress => '下载进度';

  @override
  String get downloadAndOpenInstaller => '下载后打开安装确认';

  @override
  String get backgroundDownload => '后台下载';

  @override
  String get downloadThenOpenInstaller => '下载完成后打开安装确认';

  @override
  String get backgroundDownloading => '后台下载中';

  @override
  String get updateDownloaded => '下载完成';

  @override
  String get openInstaller => '打开安装确认';

  @override
  String get updateNetworkFailed => '网络连接失败';

  @override
  String get updateTimeout => '请求超时';

  @override
  String get updateBadResponse => '发布信息格式不符合预期';

  @override
  String get updateFileSystemFailed => '写入安装包失败';

  @override
  String get updateChecksumMismatch => '安装包校验失败';

  @override
  String get installPermissionRequired => '需要允许本应用安装未知来源应用';

  @override
  String get installerUnavailable => '系统安装器不可用';

  @override
  String get invalidApkPath => '安装包路径无效';

  @override
  String get providerWithoutAsr => '该供应商不支持语音识别';

  @override
  String get connectionTestFailed => '连接测试失败';

  @override
  String get yourCallsign => '您的呼号';

  @override
  String get yourCallsignHint => '输入您的业余无线电呼号，例如 BV2AAA';

  @override
  String get yourQth => '我的 QTH（电台位置）';

  @override
  String get yourQthHint => '例如：上海，或网格定位 PM95';

  @override
  String get save => '保存';

  @override
  String get sortNewestFirst => '最新优先';

  @override
  String get sortOldestFirst => '最早优先';

  @override
  String get filterDimensionStatus => '状态';

  @override
  String get filterDimensionBand => '频段';

  @override
  String get filterDimensionMode => '通联方式';

  @override
  String get paste => '粘贴';

  @override
  String get transcriptionModelAfter => '后置转写模型';

  @override
  String get transcriptionModelStreaming => '实时转写模型';

  @override
  String get tokenUsage => 'Token 消耗';

  @override
  String get tokenUsageDesc => '查看 AI 请求消耗记录';

  @override
  String get totalTokens => '总消耗';

  @override
  String get requestCount => '请求次数';

  @override
  String get promptTokens => '输入';

  @override
  String get completionTokens => '输出';

  @override
  String get clearRecords => '清除记录';

  @override
  String get noTokenRecords => '暂无消耗记录';

  @override
  String get clearRecordsConfirm => '确认清除所有 Token 消耗记录？';

  @override
  String get taskTranscription => '后置转写';

  @override
  String get taskStructuring => '结构化';

  @override
  String get taskStreaming => '实时转写';

  @override
  String get usageUnknown => '—';

  @override
  String get failedReason => '失败原因';

  @override
  String get retrying => '重试中…';

  @override
  String get statusDraft2 => '草稿';

  @override
  String get statusNeedsReview2 => '待确认';

  @override
  String get statusConfirmed2 => '已确认';

  @override
  String get importedAsDraft => '已作为草稿导入';

  @override
  String get callsignSetup => '呼号设置';

  @override
  String get callsignSetupDesc => '输入呼号以便快速记录 QSO';

  @override
  String get stationEquipment => '电台设备';

  @override
  String get stationEquipmentDesc => '管理设备、天线和功率设置';

  @override
  String get equipmentName => '设备名称';

  @override
  String get equipmentNameHint => '例如 IC-7300、FT-991A';

  @override
  String get antennaName => '天线';

  @override
  String get antennaNameHint => '例如 DP-80、Hexbeam';

  @override
  String get powerOptions => '功率选项';

  @override
  String get powerOptionsHint => '每行一个值，例如 5W、10W、50W、100W';

  @override
  String get addEquipment => '添加设备';

  @override
  String get noEquipmentSaved => '尚未配置设备';

  @override
  String get equipmentSaved => '设备已保存';

  @override
  String get power => '功率';

  @override
  String get selectEquipment => '选择设备';

  @override
  String get welcomeTitle => '欢迎使用 QSO Scribe';

  @override
  String welcomeCallsign(Object callsign) {
    return '欢迎，$callsign';
  }

  @override
  String get welcomeSubtitle => '准备好记录下一次 QSO';

  @override
  String get skipWelcome => '进入';

  @override
  String get rawText => '原始文本';

  @override
  String get about => '关于';

  @override
  String get aboutDesc => '应用信息、隐私政策和致谢';

  @override
  String get appDescription =>
      'Hi，很高兴你能看到这里，这是一个由社区维护的业余无线电 QSO 记录工具，借助 AI 辅助开发。';

  @override
  String get privacyPolicy => '隐私政策';

  @override
  String get openSourceCredits => '开源致谢';

  @override
  String get relatedLinks => '相关链接';

  @override
  String get contestMode => '比赛模式';

  @override
  String get contestModeDesc => '比赛中快速记录 QSO';

  @override
  String get filter => '筛选';

  @override
  String get noMoreData => '没有更多数据';

  @override
  String get pullToRefresh => '下拉刷新';

  @override
  String get recording => '录音中';

  @override
  String get afterTranscribe => '后置转写';

  @override
  String get realtimeTranscribe => '实时转写';

  @override
  String get stationSettings => '电台设置';

  @override
  String get stationSettingsDesc => '呼号、设备、天线和功率';

  @override
  String get aiModels => 'AI 模型';

  @override
  String get aiModelsDesc => '供应商和模型配置';

  @override
  String get appSettings => '应用设置';

  @override
  String get appSettingsDesc => '语言、音频和更新偏好';

  @override
  String get aiProcess => 'AI 处理';

  @override
  String get discardAndRestart => '丢弃，重新录音';

  @override
  String get afterQsoRecorderHint => '正在录音，停止后音频将自动转写并结构化。';

  @override
  String get streamingStoppedHint => '录音已停止。请核对上方转写文本，然后点击 AI 处理进行结构化。';

  @override
  String aboutAppVersion(Object version) {
    return '版本 $version';
  }

  @override
  String get privacyPolicyBody =>
      '所有数据（QSO 日志、音频、转写文本和设置）均保存在本地设备上。API 密钥仅存储于本机，并仅发送给您配置的 AI 供应商。我们不收集、不上传、不与第三方共享任何数据。';

  @override
  String get openSourceCreditsBody =>
      '本应用基于 Flutter、Riverpod、sqflite、record、file_picker 等众多开源软件构建。完整依赖列表请查看 pubspec.yaml。';

  @override
  String get relatedLinksBody => '项目主页、问题追踪和版本下载托管在 GitHub。可在软件更新页面查看最新发布版本。';

  @override
  String get githubLink => 'GitHub 仓库';

  @override
  String get continueButton => '继续';

  @override
  String get audioFormatWarningTitle => '音频格式警告';

  @override
  String audioFormatWarningBody(
    String provider,
    String format,
    String supported,
  ) {
    return '当前 ASR 模型（$provider）可能不支持 .$format 格式。支持格式：$supported。是否继续？';
  }
}
