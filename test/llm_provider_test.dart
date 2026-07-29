import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_todo/services/cloud_settings.dart';
import 'package:my_todo/services/llm_provider.dart';

void main() {
  test('各服务商使用自己的思考开关且保持 OpenAI 兼容请求', () async {
    for (final provider in CloudProvider.values) {
      if (provider == CloudProvider.custom) continue;
      late Map<String, dynamic> requestBody;
      final client = MockClient((request) async {
        expect(request.url.path, endsWith('/chat/completions'));
        expect(request.headers['authorization'], 'Bearer sk-test');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode(<String, Object>{
            'choices': <Object>[
              <String, Object>{
                'message': <String, String>{'content': 'ok'},
              },
            ],
          }),
          200,
        );
      });
      final llm = OpenAiCompatibleProvider(
        apiKey: 'sk-test',
        baseUrl: provider.baseUrl,
        model: provider.defaultModel,
        provider: provider,
        client: client,
      );

      expect(await llm.complete('测试'), 'ok');
      expect(requestBody['model'], provider.defaultModel);
      expect(requestBody['stream'], isFalse);

      switch (provider) {
        case CloudProvider.deepSeek:
        case CloudProvider.volcengine:
        case CloudProvider.kimi:
        case CloudProvider.glm:
          expect(requestBody['thinking'], <String, String>{'type': 'disabled'});
          expect(requestBody, isNot(contains('enable_thinking')));
        case CloudProvider.qwen:
          expect(requestBody['enable_thinking'], isFalse);
          expect(requestBody, isNot(contains('thinking')));
        case CloudProvider.hunyuan:
        case CloudProvider.custom:
          expect(requestBody, isNot(contains('thinking')));
          expect(requestBody, isNot(contains('enable_thinking')));
      }
    }
  });
}
