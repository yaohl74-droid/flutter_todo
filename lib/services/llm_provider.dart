import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

abstract class LlmProvider {
  /// 返回模型原始文本输出。
  Future<String> complete(String prompt);

  /// 用于日志区分,不含任何密钥。
  String get label;
}

class LlmUsage {
  const LlmUsage({required this.promptTokens, required this.completionTokens});

  final int promptTokens;
  final int completionTokens;
}

class LlmCompletion {
  const LlmCompletion({required this.text, required this.elapsed, this.usage});

  final String text;
  final Duration elapsed;
  final LlmUsage? usage;
}

enum LlmFailureKind {
  configuration('配置错误'),
  timeout('超时'),
  unauthorized('401'),
  rateLimited('429'),
  server('5xx'),
  client('请求错误'),
  network('网络错误'),
  invalidResponse('响应格式错误');

  const LlmFailureKind(this.label);

  final String label;
}

class LlmProviderException implements Exception {
  const LlmProviderException(this.kind, this.safeSummary, {this.statusCode});

  final LlmFailureKind kind;
  final String safeSummary;
  final int? statusCode;

  @override
  String toString() {
    final status = statusCode == null ? '' : ',status:$statusCode';
    return 'LlmProviderException(${kind.label}$status):$safeSummary';
  }
}

class OpenAiCompatibleProvider implements LlmProvider {
  OpenAiCompatibleProvider({
    required String apiKey,
    required String baseUrl,
    required String model,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.maxTokens = 512,
    this.disableThinking = true,
  }) : _apiKey = apiKey.trim(),
       _model = model.trim(),
       _endpoint = _chatCompletionsEndpoint(baseUrl),
       _client = client ?? http.Client();

  final String _apiKey;
  final String _model;
  final Uri _endpoint;
  final http.Client _client;
  final Duration timeout;

  /// 首轮实测教训:`max_tokens: 200` 太小,31 条里 7 条拿不到 `content`
  /// (6 条响应无 content、1 条 `completion_tokens` 正好等于 200 被截断)。
  /// 抽取任务的合法输出只有几十 token,给足余量不增加实际成本。
  final int maxTokens;

  /// `deepseek-v4-pro` 的 thinking **默认开启**,会先产出 `reasoning_content`,
  /// 把 token 预算吃光,`content` 反而为空 —— 首轮 7 条失败的根因。
  ///
  /// **这个任务(从一句话里抽日期)不需要推理**,关掉更快更便宜,
  /// 也让它与本地模型(无 thinking)的对比更公平。
  /// 对不支持该字段的供应商,多传一个未知字段通常被忽略;若报错则设为 false。
  final bool disableThinking;

  @override
  String get label => 'openai-compatible:$_model';

  @override
  Future<String> complete(String prompt) async {
    final result = await completeChat(userPrompt: prompt);
    return result.text;
  }

  Future<LlmCompletion> completeChat({
    required String userPrompt,
    String? systemPrompt,
  }) async {
    if (_apiKey.isEmpty || _model.isEmpty) {
      throw const LlmProviderException(
        LlmFailureKind.configuration,
        'API Key 或模型为空',
      );
    }

    final messages = <Map<String, String>>[
      if (systemPrompt != null)
        <String, String>{'role': 'system', 'content': systemPrompt},
      <String, String>{'role': 'user', 'content': userPrompt},
    ];
    final stopwatch = Stopwatch()..start();
    late final http.Response response;
    try {
      response = await _client
          .post(
            _endpoint,
            headers: <String, String>{
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, Object?>{
              'model': _model,
              'messages': messages,
              'temperature': 0,
              'max_tokens': maxTokens,
              'stream': false,
              if (disableThinking)
                'thinking': <String, String>{'type': 'disabled'},
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      stopwatch.stop();
      throw const LlmProviderException(LlmFailureKind.timeout, '云端请求超时');
    } on http.ClientException {
      stopwatch.stop();
      throw const LlmProviderException(LlmFailureKind.network, '云端网络请求失败');
    }
    stopwatch.stop();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _statusException(response.statusCode);
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const FormatException();
      }
      final first = choices.first;
      if (first is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final message = first['message'];
      if (message is! Map<String, dynamic>) {
        throw const FormatException();
      }
      final content = message['content'];
      if (content is! String || content.trim().isEmpty) {
        throw const FormatException();
      }

      return LlmCompletion(
        text: content,
        elapsed: stopwatch.elapsed,
        usage: _parseUsage(decoded['usage']),
      );
    } on FormatException {
      throw const LlmProviderException(
        LlmFailureKind.invalidResponse,
        '云端响应缺少有效的 choices.message.content',
      );
    }
  }

  static LlmUsage? _parseUsage(Object? rawUsage) {
    if (rawUsage is! Map<String, dynamic>) return null;
    final prompt = rawUsage['prompt_tokens'];
    final completion = rawUsage['completion_tokens'];
    if (prompt is! num || completion is! num) return null;
    return LlmUsage(
      promptTokens: prompt.toInt(),
      completionTokens: completion.toInt(),
    );
  }

  static LlmProviderException _statusException(int statusCode) {
    if (statusCode == 401) {
      return const LlmProviderException(
        LlmFailureKind.unauthorized,
        '云端拒绝认证',
        statusCode: 401,
      );
    }
    if (statusCode == 429) {
      return const LlmProviderException(
        LlmFailureKind.rateLimited,
        '云端请求频率受限',
        statusCode: 429,
      );
    }
    if (statusCode >= 500) {
      return LlmProviderException(
        LlmFailureKind.server,
        '云端服务暂时不可用',
        statusCode: statusCode,
      );
    }
    return LlmProviderException(
      LlmFailureKind.client,
      '云端请求未被接受',
      statusCode: statusCode,
    );
  }

  static Uri _chatCompletionsEndpoint(String rawBaseUrl) {
    final trimmed = rawBaseUrl.trim();
    final base = Uri.tryParse(trimmed);
    if (base == null ||
        !base.hasScheme ||
        (base.scheme != 'https' && base.scheme != 'http') ||
        base.host.isEmpty) {
      throw const LlmProviderException(
        LlmFailureKind.configuration,
        'Base URL 必须是有效的 HTTP(S) 地址',
      );
    }
    final basePath = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$basePath/chat/completions', query: null);
  }
}
