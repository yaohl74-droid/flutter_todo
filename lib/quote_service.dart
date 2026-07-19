import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class Quote {
  const Quote({required this.content, required this.author});

  final String content;
  final String author;
}

class QuoteException implements Exception {
  const QuoteException(this.message);

  final String message;

  @override
  String toString() => message;
}

class QuoteTimeoutException extends QuoteException {
  const QuoteTimeoutException() : super('获取名言超时');
}

class QuoteService {
  QuoteService({http.Client? client, Duration? requestTimeout})
    : _client = client ?? http.Client(),
      _requestTimeout = requestTimeout ?? const Duration(seconds: 8);

  static final Uri _quoteUri = Uri.parse('https://uapis.cn/api/v1/saying');

  final http.Client _client;
  final Duration _requestTimeout;

  void dispose() {
    // QuoteService 与页面生命周期一致，页面销毁时释放底层 HTTP 连接。
    _client.close();
  }

  Future<Quote> fetchQuote() async {
    try {
      final http.Response response = await _client
          .get(_quoteUri)
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw QuoteException('获取名言失败（${response.statusCode}）');
      }

      final dynamic decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const QuoteException('名言数据格式错误');
      }

      // UAPI 的每日一句响应只提供 text，没有作者字段，因此统一显示“佚名”。
      final String content = decoded['text']?.toString().trim() ?? '';
      if (content.isEmpty) {
        throw const QuoteException('名言内容不完整');
      }

      return Quote(content: content, author: '佚名');
    } on TimeoutException {
      // 保留明确的超时类型；页面会对所有 QuoteException 统一启动定时重连。
      throw const QuoteTimeoutException();
    } on FormatException {
      throw const QuoteException('名言数据格式错误');
    } on QuoteException {
      rethrow;
    } on Exception {
      // DNS、断网、TLS 等网络异常统一转换，避免异常逃逸导致 App 崩溃。
      throw const QuoteException('网络异常，暂时无法获取名言');
    }
  }
}
