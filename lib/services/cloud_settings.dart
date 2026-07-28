import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String defaultCloudBaseUrl = 'https://api.deepseek.com';
const String defaultCloudModel = 'deepseek-v4-pro';

class CloudSettings {
  const CloudSettings({
    this.enabled = false,
    this.apiKey = '',
    this.baseUrl = defaultCloudBaseUrl,
    this.model = defaultCloudModel,
  });

  final bool enabled;
  final String apiKey;
  final String baseUrl;
  final String model;

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
  }) {
    return CloudSettings(
      enabled: enabled ?? this.enabled,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
    );
  }

  @override
  String toString() {
    return 'CloudSettings(enabled:$enabled,apiKey:<redacted>,'
        'baseUrl:$baseUrl,model:$model)';
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

  final FlutterSecureStorage _storage;

  @override
  Future<CloudSettings> read() async {
    final values = await Future.wait<String?>(<Future<String?>>[
      _storage.read(key: _enabledKey),
      _storage.read(key: _apiKeyKey),
      _storage.read(key: _baseUrlKey),
      _storage.read(key: _modelKey),
    ]);
    return CloudSettings(
      enabled: values[0] == 'true',
      apiKey: values[1] ?? '',
      baseUrl: _nonEmptyOr(values[2], defaultCloudBaseUrl),
      model: _nonEmptyOr(values[3], defaultCloudModel),
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
  }

  static String _nonEmptyOr(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }
}
