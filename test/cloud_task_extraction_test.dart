import 'package:flutter_test/flutter_test.dart';
import 'package:my_todo/utils/cloud_task_extraction.dart';

void main() {
  group('云端宽契约提示词', () {
    test('注入固定当前时间并写清五条产品约定', () {
      final prompt = buildCloudTaskExtractionSystemPrompt(
        now: DateTime(2013, 2, 12, 4, 30),
      );

      expect(prompt, contains('2013-02-12 04:30:00'));
      expect(prompt, contains('当天 23:59'));
      expect(prompt, contains('title 必须逐字出现在用户输入中'));
      expect(prompt, contains('重复任务无法表示'));
      expect(prompt, contains('多个时间候选歧义'));
      expect(prompt, contains('只允许 title 和 dueDate 两个字段'));
    });
  });

  group('云端宽契约解析', () {
    test('合法输出映射为 ParsedTaskInput', () {
      final result = parseCloudTaskExtractionOutput(
        '{"title":"交周报","dueDate":"2013-02-15T23:59:00"}',
        input: '三天后交周报',
      );

      expect(result, isNotNull);
      expect(result!.title, '交周报');
      expect(result.dueDate, DateTime(2013, 2, 15, 23, 59));
    });

    test('dueDate null 自然映射为弃权', () {
      expect(
        parseCloudTaskExtractionOutput(
          '{"title":"买牛奶","dueDate":null}',
          input: '买牛奶',
        ),
        isNull,
      );
    });

    test('title 必须非空且逐字来自输入', () {
      for (final output in <String>[
        '{"title":"","dueDate":"2013-02-15T23:59:00"}',
        '{"title":"提交报告","dueDate":"2013-02-15T23:59:00"}',
      ]) {
        expect(
          () => parseCloudTaskExtractionOutput(output, input: '三天后交周报'),
          throwsA(
            predicate<FormatException>(
              (error) =>
                  error.message.contains('input="三天后交周报"') &&
                  error.message.contains('title='),
            ),
          ),
          reason: output,
        );
      }
    });

    test('严格拒绝溢出日期和额外字段', () {
      expect(
        () => parseCloudTaskExtractionOutput(
          '{"title":"交周报","dueDate":"2013-02-30T23:59:00"}',
          input: '三天后交周报',
        ),
        throwsFormatException,
      );
      expect(
        () => parseCloudTaskExtractionOutput(
          '{"title":"交周报","dueDate":"2013-02-15T23:59:00","raw":"三天后"}',
          input: '三天后交周报',
        ),
        throwsFormatException,
      );
    });

    test('假 provider 走完整云端调用链且不联网', () async {
      var calls = 0;
      final result = await extractTaskCloud(
        '这周三体检',
        now: DateTime(2013, 2, 12, 4, 30),
        provider: ({required systemPrompt, required userPrompt}) async {
          calls++;
          expect(systemPrompt, contains('2013-02-12 04:30:00'));
          expect(userPrompt, '这周三体检');
          return '{"title":"体检","dueDate":"2013-02-13T23:59:00"}';
        },
      );

      expect(calls, 1);
      expect(result!.title, '体检');
      expect(result.dueDate, DateTime(2013, 2, 13, 23, 59));
    });
  });
}
