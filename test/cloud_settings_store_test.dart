import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/services/cloud_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
  });

  test('安全存储为空时云端默认关闭并使用 DeepSeek 默认值', () async {
    final store = SecureCloudSettingsStore();

    final settings = await store.read();

    expect(settings.enabled, isFalse);
    expect(settings.apiKey, isEmpty);
    expect(settings.baseUrl, defaultCloudBaseUrl);
    expect(settings.model, defaultCloudModel);
    expect(settings.provider, CloudProvider.deepSeek);
  });

  test('API Key 写入安全存储且清空时删除', () async {
    final store = SecureCloudSettingsStore();
    const configured = CloudSettings(
      enabled: true,
      apiKey: 'sk-secure-test',
      baseUrl: 'https://example.test/v1',
      model: 'custom-model',
      provider: CloudProvider.custom,
    );

    await store.write(configured);
    expect(await store.read(), isA<CloudSettings>());
    final restored = await store.read();
    expect(restored.enabled, isTrue);
    expect(restored.apiKey, 'sk-secure-test');
    expect(restored.baseUrl, 'https://example.test/v1');
    expect(restored.model, 'custom-model');
    expect(restored.provider, CloudProvider.custom);
    expect(restored.toString(), isNot(contains('sk-secure-test')));

    await store.write(configured.copyWith(apiKey: ''));
    expect((await store.read()).apiKey, isEmpty);
  });

  test('旧设置没有服务商字段时按 Base URL 自动识别', () async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      'cloud.base_url': CloudProvider.qwen.baseUrl,
      'cloud.model': CloudProvider.qwen.defaultModel,
    });

    final settings = await SecureCloudSettingsStore().read();

    expect(settings.provider, CloudProvider.qwen);
  });

  test('内置服务商都有完整的地址与默认模型', () {
    for (final provider in CloudProvider.values) {
      if (provider == CloudProvider.custom) continue;
      expect(provider.baseUrl, startsWith('https://'));
      expect(provider.defaultModel, isNotEmpty);
    }
  });
}
