import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:my_todo/models/quote_model.dart';
import 'package:my_todo/services/quote_service.dart';

class _FakeQuoteService extends QuoteService {
  _FakeQuoteService(this._fetcher);

  final Future<Quote> Function(int callCount) _fetcher;
  int callCount = 0;
  bool isDisposed = false;

  @override
  Future<Quote> fetchQuote() => _fetcher(++callCount);

  @override
  void dispose() {
    isDisposed = true;
    super.dispose();
  }
}

void main() {
  const Duration shortRetryDelay = Duration(milliseconds: 50);

  test('初始加载成功后进入 idle 阶段', () async {
    final service = _FakeQuoteService(
      (_) async => const Quote(content: '测试名言', author: '测试作者'),
    );
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    expect(model.stage, QuoteLoadStage.idle);
    expect(model.quoteFuture, isNull);

    model.refresh();

    expect(model.stage, QuoteLoadStage.loading);
    expect(model.quoteFuture, isNotNull);

    final Quote quote = await model.quoteFuture!;
    expect(quote.content, '测试名言');
    expect(quote.author, '测试作者');

    // 等待完成回调执行
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.idle);
    expect(service.callCount, 1);

    model.dispose();
    expect(service.isDisposed, isTrue);
  });

  test('手动刷新会取消等待中的重连并重置计数', () async {
    final Completer<Quote> firstRequest = Completer<Quote>();
    final service = _FakeQuoteService((int callCount) {
      if (callCount == 1) {
        return firstRequest.future;
      }
      return Future<Quote>.value(
        const Quote(content: '刷新后的名言', author: '新作者'),
      );
    });
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    model.refresh();
    expect(service.callCount, 1);

    // 刷新时第一个请求还未完成，应该取消等待中的重连
    model.refresh();
    expect(service.callCount, 2);

    firstRequest.complete(const Quote(content: '第一条名言', author: '作者甲'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // 完成的是第一个请求，但应该被忽略（requestId 不匹配）
    expect(service.callCount, 2);

    // 等待第二个请求完成
    final Quote quote = await model.quoteFuture!;
    expect(quote.content, '刷新后的名言');
    expect(quote.author, '新作者');

    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.idle);

    model.dispose();
    expect(service.isDisposed, isTrue);
  });

  test('非超时网络异常会自动重连三次', () async {
    final service = _FakeQuoteService(
      (_) => Future<Quote>.error(const QuoteException('网络异常')),
    );
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    model.refresh();
    expect(service.callCount, 1);

    // 第一次请求立即失败，进入重连
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.retrying);

    // 等待第一次重连
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.callCount, 2);

    // 等待第二次重连
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.callCount, 3);

    // 等待第三次重连
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.callCount, 4);

    // 等待第四次请求失败（已达到最大重连次数）
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.failed);

    model.dispose();
    expect(service.isDisposed, isTrue);
  });

  test('超时后每分钟重连且三次失败后停止', () async {
    final service = _FakeQuoteService(
      (_) => Future<Quote>.error(const QuoteTimeoutException()),
    );
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    model.refresh();
    expect(service.callCount, 1);

    // 第一次请求立即失败，进入重连
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.retrying);

    // 等待第一次重连
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.callCount, 2);

    // 等待第二次重连
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.callCount, 3);

    // 等待第三次重连
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.callCount, 4);

    // 等待第四次请求失败（已达到最大重连次数）
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.failed);

    model.dispose();
    expect(service.isDisposed, isTrue);
  });

  test('dispose 后所有回调被 _isDisposed 守卫拦截', () async {
    final Completer<Quote> request = Completer<Quote>();
    final service = _FakeQuoteService((_) => request.future);
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    model.refresh();
    expect(service.callCount, 1);

    model.dispose();
    expect(service.isDisposed, isTrue);

    request.complete(const Quote(content: '完成请求', author: '作者'));

    // 等待可能的回调
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // 由于 _isDisposed 为 true，完成回调不应该更新状态
    expect(model.stage, QuoteLoadStage.loading);

    // dispose 后再等待延迟，不应该触发重连（Timer 已被取消）
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(service.callCount, 1);
  });

  test('dispose 后可以安全调用 refresh（无效果）', () async {
    final service = _FakeQuoteService(
      (_) async => const Quote(content: '测试', author: '作者'),
    );
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    model.refresh();
    expect(service.callCount, 1);

    model.dispose();

    model.refresh();

    // 由于 _isDisposed 为 true，refresh 应该不执行任何操作
    expect(service.callCount, 1);
  });

  test('请求编号确保旧请求结果不覆盖新请求', () async {
    final Completer<Quote> firstRequest = Completer<Quote>();
    final Completer<Quote> secondRequest = Completer<Quote>();
    final service = _FakeQuoteService((int callCount) {
      if (callCount == 1) {
        return firstRequest.future;
      }
      return secondRequest.future;
    });
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    model.refresh();
    expect(service.callCount, 1);

    // 立即再次刷新
    model.refresh();
    expect(service.callCount, 2);

    // 先完成第一个请求（应该被忽略）
    firstRequest.complete(const Quote(content: '旧结果', author: '旧作者'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.loading);

    // 再完成第二个请求（应该生效）
    secondRequest.complete(const Quote(content: '新结果', author: '新作者'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.idle);

    final Quote quote = await model.quoteFuture!;
    expect(quote.content, '新结果');
    expect(quote.author, '新作者');

    model.dispose();
  });

  test('刷新时取消旧重连定时器', () async {
    final Completer<Quote> firstRequest = Completer<Quote>();
    final service = _FakeQuoteService((int callCount) {
      if (callCount == 1) {
        return firstRequest.future;
      }
      return Future<Quote>.value(
        const Quote(content: '刷新后的名言', author: '新作者'),
      );
    });
    final model = QuoteModel(quoteService: service, retryDelay: shortRetryDelay);

    model.refresh();

    // 模拟第一次请求失败，进入重连阶段
    firstRequest.completeError(const QuoteException('网络异常'));
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(model.stage, QuoteLoadStage.retrying);

    // 立即手动刷新
    model.refresh();

    // 等待第一次重连延迟过去
    await Future<void>.delayed(shortRetryDelay);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    // 由于重连定时器被取消，不应该触发重连
    expect(service.callCount, 2);

    model.dispose();
  });
}