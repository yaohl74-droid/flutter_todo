import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_todo/quote_service.dart';

void main() {
  test('QuoteService 解析 UAPI 名言并使用佚名作为作者', () async {
    final MockClient client = MockClient(
      (_) async => http.Response(
        '{"text":"保持好奇"}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    final QuoteService service = QuoteService(client: client);

    final Quote quote = await service.fetchQuote();

    expect(quote.content, '保持好奇');
    expect(quote.author, '佚名');
  });

  test('QuoteService 将请求超时转换为 QuoteTimeoutException', () async {
    final Completer<http.Response> response = Completer<http.Response>();
    final QuoteService service = QuoteService(
      client: MockClient((_) => response.future),
      requestTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      service.fetchQuote(),
      throwsA(isA<QuoteTimeoutException>()),
    );
  });

  test('QuoteService 捕获其他网络异常', () async {
    final QuoteService service = QuoteService(
      client: MockClient((_) => Future<http.Response>.error(StateError('断网'))),
    );

    await expectLater(
      service.fetchQuote(),
      throwsA(
        isA<QuoteException>().having(
          (error) => error.message,
          'message',
          '网络异常，暂时无法获取名言',
        ),
      ),
    );
  });
}
