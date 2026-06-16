import 'app_models.dart';

// 固定供应商目录：所有受支持的供应商在此声明。
//
// 兼容性约定（必须遵守，否则会破坏已发布用户的数据）：
// 1. [AiProvider.name] 是被持久化到数据库的供应商身份键，一经发布
//    永不修改、永不删除、永不复用给其它供应商。
// 2. 新增供应商只能追加新的枚举值 + 新的 [ProviderDescriptor] 条目，
//    不需要任何数据库 schema 变更，旧版本数据不受影响。
// 3. 若读到当前版本不认识的 key（例如用户从更高版本回退），
//    [AiProvider.fromKey] 降级为 [AiProvider.unknown]，不抛异常。
// 4. 预置模型名同样是稳定键，永不更改；新增模型只追加。

/// 受支持的固定供应商。新增供应商只能在此追加新值。
enum AiProvider {
  openai,
  zhipu,
  qwen,
  mimo,
  deepseek,
  unknown;

  /// 将持久化的身份键解析回枚举；未知 key 降级为 [unknown]，绝不抛异常。
  static AiProvider fromKey(String? key) {
    if (key == null) {
      return AiProvider.unknown;
    }
    for (final value in AiProvider.values) {
      if (value.name == key) {
        return value;
      }
    }
    return AiProvider.unknown;
  }
}

/// 鉴权头风格。MiMo 用 `api-key` 头，其余用标准 `Authorization: Bearer`。
enum AuthStyle { bearer, apiKeyHeader }

/// 语音识别调用形态。新增形态时追加新值，并在调用层实现对应 Strategy。
enum AsrShape { whisperMultipart, chatInputAudio }

/// 预置模型。name 即对外稳定键。
class PresetModel {
  const PresetModel(this.name, this.capabilities);

  final String name;
  final Set<ModelCapability> capabilities;
}

/// 某供应商的语音识别能力描述。为 null 表示不支持语音识别。
class AsrSpec {
  const AsrSpec({
    required this.shape,
    required this.defaultModel,
    this.languageOption,
    this.supportedFormats = const [],
    this.hotWords,
  });

  final AsrShape shape;

  /// 该形态下的默认 ASR 模型名。
  final String defaultModel;

  /// 随请求发送的语种值（如 mimo 的 'auto'）；为 null 时不发送 language，
  /// 交由服务端自动检测（如 qwen）。
  final String? languageOption;

  /// 该供应商支持的音频文件格式（小写扩展名，不含点号，如 'wav', 'mp3'）。
  /// 空列表表示未做格式限制（兜底）。
  final List<String> supportedFormats;

  /// 语音识别热词/自定义词典。仅部分供应商支持（如智谱的 hot_words）。
  /// 为 null 时不发送热词参数。
  final String? hotWords;
}

/// 单个固定供应商的全部调用契约。新增供应商 = 新增一个本类实例。
class ProviderDescriptor {
  const ProviderDescriptor({
    required this.provider,
    required this.displayName,
    required this.defaultBaseUrl,
    required this.authStyle,
    required this.structuringModels,
    this.asr,
    this.presetAsrModels = const [],
    this.streamingCapable = false,
  });

  final AiProvider provider;

  /// 展示名（品牌名，无需本地化）。
  final String displayName;
  final String defaultBaseUrl;
  final AuthStyle authStyle;

  /// 语音识别能力；为 null 表示该供应商不支持语音识别。
  final AsrSpec? asr;

  /// 该供应商预置的 ASR 模型清单。
  final List<PresetModel> presetAsrModels;

  /// 该供应商预置的结构化（文字）模型清单。
  final List<PresetModel> structuringModels;

  /// 是否支持实时（流式）转写。
  /// Phase 2 将为 Qwen 实现实时传输；其余供应商暂不支持实时。
  final bool streamingCapable;

  bool get supportsAsr => asr != null;

  /// 该供应商所有预置模型（ASR + 结构化），供表单预填。
  List<PresetModel> get presetModels => [
    ...presetAsrModels,
    ...structuringModels,
  ];
}

const _openaiAsrModels = [
  PresetModel('whisper-1', {ModelCapability.speech}),
  PresetModel('gpt-4o-mini-transcribe', {ModelCapability.speech}),
  PresetModel('gpt-4o-transcribe', {ModelCapability.speech}),
];

const _openaiStructuringModels = [
  PresetModel('gpt-4o-mini', {ModelCapability.text, ModelCapability.structuring}),
  PresetModel('gpt-4o', {ModelCapability.text, ModelCapability.structuring}),
];

const _zhipuAsrModels = [
  PresetModel('glm-asr-2512', {ModelCapability.speech}),
];

const _zhipuStructuringModels = [
  PresetModel('glm-4.6', {ModelCapability.text, ModelCapability.structuring}),
  PresetModel('glm-4-plus', {ModelCapability.text, ModelCapability.structuring}),
];

const _qwenAsrModels = [
  PresetModel('qwen3-asr-flash', {ModelCapability.speech}),
  // 实时（流式）转写模型，仅用于 streaming 模式；文件转写用上面的 qwen3-asr-flash。
  PresetModel('qwen3-asr-flash-realtime', {ModelCapability.streaming}),
];

const _qwenStructuringModels = [
  PresetModel('qwen-plus', {ModelCapability.text, ModelCapability.structuring}),
  PresetModel('qwen-max', {ModelCapability.text, ModelCapability.structuring}),
];

const _mimoAsrModels = [
  PresetModel('mimo-v2.5-asr', {ModelCapability.speech}),
];

const _mimoStructuringModels = [
  PresetModel('mimo-v2.5-pro', {ModelCapability.text, ModelCapability.structuring}),
];

const _deepseekStructuringModels = [
  PresetModel('deepseek-chat', {ModelCapability.text, ModelCapability.structuring}),
  PresetModel('deepseek-reasoner', {ModelCapability.text, ModelCapability.structuring}),
];

// 智谱 ASR 默认热词：标准字母解释法 + 常用 Q 短语 + 业余无线电术语。
// 用于 hot_words 参数，格式为 "词:权重" 逗号分隔。
const _zhipuDefaultHotWords =
    'Alpha:10,Bravo:10,Charlie:10,Delta:10,Echo:10,Foxtrot:10,'
    'Golf:10,Hotel:10,India:10,Juliet:10,Kilo:10,Lima:10,'
    'Mike:10,November:10,Oscar:10,Papa:10,Quebec:10,Romeo:10,'
    'Sierra:10,Tango:10,Uniform:10,Victor:10,Whiskey:10,'
    'X-ray:10,Yankee:10,Zulu:10,'
    'QTH:15,QSL:15,QSO:15,QRM:15,QRN:15,QRP:15,QRO:15,'
    'QRZ:15,QRT:15,QSY:15,QSB:15,QSA:15,QRA:15,QRG:15,QRH:15,'
    'CQ:15,73:15,59:10,599:10,'
    '阿尔法:10,布拉沃:10,查理:10,德尔塔:10,艾柯:10,福克斯特罗特:10,'
    '高尔夫:10,酒店:10,印度:10,朱丽叶:10,基洛:10,利马:10,'
    '迈克:10,十一月:10,奥斯卡:10,帕帕:10,魁北克:10,罗密欧:10,'
    '塞拉:10,探戈:10,优尼佛姆:10,维克托:10,威士忌:10,'
    'X射线:10,扬基:10,祖鲁:10';

final Map<AiProvider, ProviderDescriptor> _descriptors = {
  AiProvider.openai: ProviderDescriptor(
    provider: AiProvider.openai,
    displayName: 'OpenAI',
    defaultBaseUrl: 'https://api.openai.com/v1',
    authStyle: AuthStyle.bearer,
    asr: const AsrSpec(
      shape: AsrShape.whisperMultipart,
      defaultModel: 'whisper-1',
      supportedFormats: ['mp3', 'mp4', 'mpeg', 'mpga', 'm4a', 'wav', 'webm', 'flac', 'ogg'],
    ),
    presetAsrModels: _openaiAsrModels,
    structuringModels: _openaiStructuringModels,
  ),
  AiProvider.zhipu: ProviderDescriptor(
    provider: AiProvider.zhipu,
    displayName: 'Zhipu (GLM)',
    defaultBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    authStyle: AuthStyle.bearer,
    asr: const AsrSpec(
      shape: AsrShape.whisperMultipart,
      defaultModel: 'glm-asr-2512',
      supportedFormats: ['wav', 'mp3', 'opus', 'ogg', 'flac', 'm4a', 'amr', 'pcm'],
      hotWords: _zhipuDefaultHotWords,
    ),
    presetAsrModels: _zhipuAsrModels,
    structuringModels: _zhipuStructuringModels,
  ),
  AiProvider.qwen: ProviderDescriptor(
    provider: AiProvider.qwen,
    displayName: 'Qwen (通义)',
    defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    authStyle: AuthStyle.bearer,
    // qwen3-asr-flash 走 chat/completions + input_audio(base64 data URL)。
    // 语种留空交由服务端自动检测（qwen 的 language 需指定具体语种代码）。
    asr: const AsrSpec(
      shape: AsrShape.chatInputAudio,
      defaultModel: 'qwen3-asr-flash',
      supportedFormats: ['wav', 'mp3', 'flac', 'opus', 'ogg', 'amr', 'aac', 'pcm'],
    ),
    presetAsrModels: _qwenAsrModels,
    structuringModels: _qwenStructuringModels,
    streamingCapable: true,
  ),
  AiProvider.mimo: ProviderDescriptor(
    provider: AiProvider.mimo,
    displayName: 'MiMo (小米)',
    defaultBaseUrl: 'https://api.xiaomimimo.com/v1',
    authStyle: AuthStyle.apiKeyHeader,
    // mimo-v2.5-asr 走 chat/completions + input_audio，鉴权用 api-key 头。
    asr: const AsrSpec(
      shape: AsrShape.chatInputAudio,
      defaultModel: 'mimo-v2.5-asr',
      languageOption: 'auto',
      supportedFormats: ['wav', 'mp3'],
    ),
    presetAsrModels: _mimoAsrModels,
    structuringModels: _mimoStructuringModels,
  ),
  AiProvider.deepseek: ProviderDescriptor(
    provider: AiProvider.deepseek,
    displayName: 'DeepSeek',
    defaultBaseUrl: 'https://api.deepseek.com',
    authStyle: AuthStyle.bearer,
    // DeepSeek 仅用于 QSO 整理（文字模型），不支持语音识别。
    asr: null,
    structuringModels: _deepseekStructuringModels,
  ),
  AiProvider.unknown: ProviderDescriptor(
    provider: AiProvider.unknown,
    displayName: 'Unknown',
    defaultBaseUrl: '',
    authStyle: AuthStyle.bearer,
    asr: null,
    structuringModels: const [],
  ),
};

/// 按供应商获取描述符；未知供应商返回安全降级描述符。
ProviderDescriptor descriptorFor(AiProvider provider) =>
    _descriptors[provider] ?? _descriptors[AiProvider.unknown]!;

/// 所有可在 UI 选择的固定供应商描述符（不含 unknown）。
List<ProviderDescriptor> get selectableProviders => AiProvider.values
    .where((value) => value != AiProvider.unknown)
    .map(descriptorFor)
    .toList();

/// 表单中用于呈现与编辑的模型项（保留 selected/capabilities 可编辑状态）。
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
