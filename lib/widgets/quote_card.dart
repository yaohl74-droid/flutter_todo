import 'package:flutter/material.dart';

import '../services/quote_service.dart';

enum QuoteLoadStage { idle, loading, retrying, failed }

/// 每日一句的纯展示组件；请求、重试计时和阶段切换仍由页面 State 管理。
class QuoteCard extends StatelessWidget {
  const QuoteCard({
    super.key,
    required this.quoteFuture,
    required this.stage,
    required this.onRefresh,
  });

  final Future<Quote> quoteFuture;
  final QuoteLoadStage stage;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const ValueKey<String>('daily-quote-card'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: FutureBuilder<Quote>(
                future: quoteFuture,
                builder: (context, snapshot) {
                  if (stage == QuoteLoadStage.retrying) {
                    return const Text('正在联网获取名言,请稍等');
                  }

                  // FutureBuilder 的三种状态：waiting 表示加载中；hasError
                  // 表示本次请求失败；hasData 表示请求成功并可安全展示名言。
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError || stage == QuoteLoadStage.failed) {
                    final String message = stage == QuoteLoadStage.failed
                        ? '无法连接,无法显示名言'
                        : '获取名言失败';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message),
                        TextButton(
                          onPressed: onRefresh,
                          child: const Text('重试'),
                        ),
                      ],
                    );
                  }
                  if (snapshot.hasData) {
                    final Quote quote = snapshot.data!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('“${quote.content}”'),
                        const SizedBox(height: 6),
                        Text(
                          '—— ${quote.author}',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ],
                    );
                  }

                  return const Text('暂无名言');
                },
              ),
            ),
            IconButton(
              key: const ValueKey<String>('refresh-quote-button'),
              tooltip: '刷新名言',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}
