import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/quote_service.dart';

enum QuoteLoadStage { idle, loading, retrying, failed }

/// 管理每日一句的加载状态、重连逻辑和请求取消。
///
/// 接收可注入的 QuoteService，持有当前请求 Future、加载阶段、重连计数和定时器。
/// 提供刷新接口，内部处理请求取消、重试调度和资源清理。
class QuoteModel extends ChangeNotifier {
  QuoteModel({
    QuoteService? quoteService,
    @visibleForTesting Duration retryDelay = const Duration(seconds: 60),
  })  : _quoteService = quoteService ?? QuoteService(),
        _quoteRetryDelay = retryDelay;

  final QuoteService _quoteService;

  static const int _maxQuoteRetries = 3;
  final Duration _quoteRetryDelay;

  // 当前请求的 Future，由 QuoteCard 的 FutureBuilder 使用
  Future<Quote>? _quoteFuture;

  // 加载阶段：idle(成功或未开始), loading(初始加载), retrying(重连中), failed(最终失败)
  QuoteLoadStage _quoteStage = QuoteLoadStage.idle;

  // 自动重连计数器，达到 _maxQuoteRetries 后停止重连
  int _quoteRetryCount = 0;

  // 请求编号，用于取消已过期的请求回调（避免旧请求结果覆盖新请求）
  int _quoteRequestId = 0;

  // 重连定时器
  Timer? _quoteRetryTimer;

  // Dispose 标记，所有异步回调在执行前检查此标记
  bool _isDisposed = false;

  /// 当前加载阶段
  QuoteLoadStage get stage => _quoteStage;

  /// 当前请求的 Future
  Future<Quote>? get quoteFuture => _quoteFuture;

  /// 开始名言请求（初始加载或重连）
  void _startQuoteRequest({
    required QuoteLoadStage stage,
    required bool notify,
  }) {
    if (_isDisposed) {
      return;
    }

    final int requestId = ++_quoteRequestId;
    final Future<Quote> request = _quoteService.fetchQuote();

    void updateRequest() {
      _quoteStage = stage;
      _quoteFuture = request;
    }

    if (notify) {
      updateRequest();
      notifyListeners();
    } else {
      updateRequest();
    }

    // FutureBuilder 只展示这一次请求；超时后的定时重连由 QuoteModel 统一调度。
    request.then<void>(
      (_) {
        if (_isDisposed || requestId != _quoteRequestId) {
          return;
        }
        _quoteRetryTimer?.cancel();
        _quoteRetryCount = 0;
        _quoteStage = QuoteLoadStage.idle;
        notifyListeners();
      },
      onError: (Object error, StackTrace stackTrace) {
        if (_isDisposed || requestId != _quoteRequestId) {
          return;
        }
        // 超时、断网、DNS 和 TLS 等请求失败都统一按 QuoteException 重连。
        if (error is QuoteException && _quoteRetryCount < _maxQuoteRetries) {
          _scheduleQuoteRetry();
          return;
        }
        _quoteStage = QuoteLoadStage.failed;
        notifyListeners();
      },
    );
  }

  /// 调度下一次重连
  void _scheduleQuoteRetry() {
    if (_isDisposed) {
      return;
    }

    _quoteRetryTimer?.cancel();
    _quoteStage = QuoteLoadStage.retrying;
    notifyListeners();

    _quoteRetryTimer = Timer(_quoteRetryDelay, () {
      if (_isDisposed) {
        return;
      }
      _quoteRetryCount++;
      _startQuoteRequest(stage: QuoteLoadStage.retrying, notify: true);
    });
  }

  /// 手动刷新名言
  ///
  /// 取消等待中的重连，重置重连计数，并开始新的请求。
  void refresh() {
    if (_isDisposed) {
      return;
    }

    // 手动刷新代表一轮全新尝试：取消旧 Timer，并重置自动重连次数。
    _quoteRetryTimer?.cancel();
    _quoteRetryCount = 0;
    _startQuoteRequest(stage: QuoteLoadStage.loading, notify: true);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _quoteRetryTimer?.cancel();
    _quoteService.dispose();
    super.dispose();
  }
}