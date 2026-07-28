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
  });

  test('API Key 写入安全存储且清空时删除', () async {
    final store = SecureCloudSettingsStore();
    const configured = CloudSettings(
      enabled: true,
      apiKey: 'sk-secure-test',
      baseUrl: 'https://example.test/v1',
      model: 'custom-model',
    );

    await store.write(configured);
    expect(await store.read(), isA<CloudSettings>());
    final restored = await store.read();
    expect(restored.enabled, isTrue);
    expect(restored.apiKey, 'sk-secure-test');
    expect(restored.baseUrl, 'https://example.test/v1');
    expect(restored.model, 'custom-model');
    expect(restored.toString(), isNot(contains('sk-secure-test')));

    await store.write(configured.copyWith(apiKey: ''));
    expect((await store.read()).apiKey, isEmpty);
  });
}
