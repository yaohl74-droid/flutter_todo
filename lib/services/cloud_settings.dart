import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String defaultCloudBaseUrl = 'https://api.deepseek.com';
const String defaultCloudModel = 'deepseek-v4-pro';

enum CloudProvider {
  deepSeek(
    id: 'deepseek',
    label: 'DeepSeek',
    baseUrl: defaultCloudBaseUrl,
    defaultModel: defaultCloudModel,
    description: 'DeepSeek 开放平台',
  ),
  qwen(
    id: 'qwen',
    label: '通义千问（Qwen）',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    defaultModel: 'qwen-plus',
    description: '阿里云百炼北京地域；其他地域可修改 Base URL',
  ),
  volcengine(
    id: 'volcengine',
    label: '火山方舟（豆包）',
    baseUrl: 'https://ark.cn-beijing.volces.com/api/v3',
    defaultModel: 'doubao-seed-1-6-251015',
    description: '模型也可填写方舟控制台创建的 Endpoint ID',
  ),
  hunyuan(
    id: 'hunyuan',
    label: '腾讯混元',
    baseUrl: 'https://tokenhub.tencentmaas.com/v1',
    defaultModel: 'hy3-preview',
    description: '使用腾讯云 TokenHub API Key',
  ),
  kimi(
    id: 'kimi',
    label: 'Kimi',
    baseUrl: 'https://api.moonshot.cn/v1',
    defaultModel: 'kimi-k2.6',
    description: 'Moonshot AI 开放平台',
  ),
  glm(
    id: 'glm',
    label: '智谱 GLM',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-4.7',
    description: '智谱 AI 开放平台',
  ),
  custom(
    id: 'custom',
    label: '自定义（OpenAI 兼容）',
    baseUrl: '',
    defaultModel: '',
    description: '填写兼容 Chat Completions 的服务地址和模型 ID',
  );

  const CloudProvider({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.defaultModel,
    required this.description,
  });

  final String id;
  final String label;
  final String baseUrl;
  final String defaultModel;
  final String description;

  static CloudProvider fromId(String? id) {
    return CloudProvider.values.firstWhere(
      (provider) => provider.id == id,
      orElse: () => CloudProvider.custom,
    );
  }

  static CloudProvider fromBaseUrl(String baseUrl) {
    final String normalized = _normalizeBaseUrl(baseUrl);
    return CloudProvider.values.firstWhere(
      (provider) =>
          provider != CloudProvider.custom &&
          _normalizeBaseUrl(provider.baseUrl) == normalized,
      orElse: () => CloudProvider.custom,
    );
  }

  static String _normalizeBaseUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'/+$'), '');
  }
}

class CloudSettings {
  const CloudSettings({
    this.enabled = false,
    this.apiKey = '',
    this.baseUrl = defaultCloudBaseUrl,
    this.model = defaultCloudModel,
    this.provider = CloudProvider.deepSeek,
  });

  final bool enabled;
  final String apiKey;
  final String baseUrl;
  final String model;
  final CloudProvider provider;

  bool get isConfigured =>
      enabled &&
      apiKey.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      model.trim().isNotEmpty;

  CloudSettings copyWith({
    bool? enabled,
    String? apiKey,
    String? baseUrl,
    String? model,
    CloudProvider? provider,
  }) {
    return CloudSettings(
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      provider: provider ?? this.provider,
    );
  }

  @override
  String toString() {
    return 'CloudSettings(enabled:$enabled,apiKey:<redacted>,'
        'provider:${provider.id},baseUrl:$baseUrl,model:$model)';
  }
}

abstract class CloudSettingsStore {
  Future<CloudSettings> read();

  Future<void> write(CloudSettings settings);
}

class SecureCloudSettingsStore implements CloudSettingsStore {
  SecureCloudSettingsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  static const String _enabledKey = 'cloud.enabled';
  static const String _apiKeyKey = 'cloud.api_key';
  static const String _baseUrlKey = 'cloud.base_url';
  static const String _modelKey = 'cloud.model';
  static const String _providerKey = 'cloud.provider';

  final FlutterSecureStorage _storage;

  @override
  Future<CloudSettings> read() async {
    final values = await Future.wait<String?>(<Future<String?>>[
      _storage.read(key: _enabledKey),
      _storage.read(key: _apiKeyKey),
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _modelKey),
      _storage.read(key: _providerKey),
    ]);
    final String baseUrl = _nonEmptyOr(values[2], defaultCloudBaseUrl);
    final CloudProvider storedProvider = CloudProvider.fromId(values[4]);
    final CloudProvider provider = values[4] == null
        ? CloudProvider.fromBaseUrl(baseUrl)
        : storedProvider;
    return CloudSettings(
      enabled: values[0] == 'true',
      apiKey: values[1] ?? '',
      baseUrl: baseUrl,
      model: _nonEmptyOr(values[3], defaultCloudModel),
      provider: provider,
    );
  }

  @override
  Future<void> write(CloudSettings settings) async {
    await _storage.write(key: _enabledKey, value: settings.enabled.toString());
    if (settings.apiKey.isEmpty) {
      await _storage.delete(key: _apiKeyKey);
    } else {
      await _storage.write(key: _apiKeyKey, value: settings.apiKey);
    }
    await _storage.write(key: _baseUrlKey, value: settings.baseUrl);
    await _storage.write(key: _modelKey, value: settings.model);
    await _storage.write(key: _providerKey, value: settings.provider.id);
  }

  static String _nonEmptyOr(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }
}
