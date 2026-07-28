import 'dart:convert';

import 'natural_language_task_parser.dart';

/// 云端兜底:规则接不住时,把整句交给云端大模型抽取 `{title, dueDate}`。
///
/// **本地规则永远优先。** 只有规则明确"问了也没用"之外的失败才联网 ——
/// 见 [kLocalOnlyRejections]。九成以上输入不会走到这里。
///
/// 契约刻意窄:只有两个字段，且 `title` 必须逐字来自原句。让模型直接输出
/// 结构化字段虽然省事，但也把**任务正文重新放回了模型的输出通道** ——
/// 校验必须到位，否则正文会被悄悄改写。

/// 规则做出这些判断时，**不问云端**:问题出在信息本身或数据模型，不是写法。
/// 再好的模型也补不出不存在的信息，而每一次无谓的请求都会把用户的任务文本
/// 发出设备。
const Set<ParseRejection> kLocalOnlyRejections = <ParseRejection>{
  ParseRejection.recurring, // 数据模型只有单个 dueDate，装不下
  ParseRejection.bareTimePeriod, // 有时段没时刻，信息不在句子里
  ParseRejection.ambiguousCandidates, // 多个候选，歧义
  ParseRejection.noTimeExpression, // 根本没有时间表达，答案已知
  ParseRejection.invalidDate, // 日期非法，不是理解问题
};

typedef CloudTaskProvider =
    Future<String> Function({
      required String systemPrompt,
      required String userPrompt,
    });

String buildCloudTaskExtractionSystemPrompt({required DateTime now}) {
  final String nowText =
      '${now.year}-${_two(now.month)}-${_two(now.day)} '
      '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
  return '你是中文待办任务解析器。当前本地时间是 $nowText。\n'
      '只输出一个 JSON 对象:{"title":"任务正文","dueDate":"ISO8601本地时间或null"}。\n'
      '必须遵守以下约定:\n'
      '1. 当前时间只使用上面给出的时间,不要使用你自己的当前时间。\n'
      '2. 只给日期不给时刻时,dueDate 使用当天 23:59。\n'
      '3. title 必须逐字出现在用户输入中,只去掉时间表达,不得改写或补充正文。\n'
      '4. 每天、每周、每月等重复任务无法表示,dueDate 必须为 null。\n'
      '5. 没有时间表达或存在多个时间候选歧义时,dueDate 必须为 null,不要猜。\n'
      '只允许 title 和 dueDate 两个字段,不要解释,不要 markdown 围栏。';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// 解析云端输出。校验刻意严格 —— 见文件头注释。
///
/// `dueDate` 为 null 表示模型判定弃权，自然映射为返回 null。
ParsedTaskInput? parseCloudTaskExtractionOutput(
  String rawOutput, {
  required String input,
}) {
  final Map<String, dynamic> decoded = _decodeFirstJsonObject(rawOutput);
  if (decoded.length != 2 ||
      !decoded.containsKey('title') ||
      !decoded.containsKey('dueDate')) {
    throw const FormatException('模型输出必须且只能包含 title、dueDate');
  }

  final Object? title = decoded['title'];
  // 正文必须逐字来自原句：模型改写正文是真实发生过的失败模式。
  if (title is! String || title.trim().isEmpty || !input.contains(title)) {
    throw FormatException('title 不是输入中的非空原文片段:input="$input",title="$title"');
  }

  final Object? dueDate = decoded['dueDate'];
  if (dueDate == null) return null;
  // 严格校验，不用 DateTime.tryParse —— 它会把 2月30日 溢出归一化成 3月2日。
  if (dueDate is! String || !_isValidIso8601Local(dueDate)) {
    throw FormatException('dueDate 不是合法 ISO8601 时间:dueDate="$dueDate"');
  }

  return ParsedTaskInput(title: title, dueDate: DateTime.parse(dueDate));
}

Future<ParsedTaskInput?> extractTaskCloud(
  String input, {
  required DateTime now,
  required CloudTaskProvider provider,
}) async {
  final String rawOutput = await provider(
    systemPrompt: buildCloudTaskExtractionSystemPrompt(now: now),
    userPrompt: input,
  );
  return parseCloudTaskExtractionOutput(rawOutput, input: input);
}

final RegExp _iso8601Local = RegExp(
  r'^(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})T'
  r'(?<hour>\d{2}):(?<minute>\d{2})'
  r'(?::(?<second>\d{2})(?:\.\d{1,6})?)?$',
);

bool _isValidIso8601Local(String value) {
  final RegExpMatch? match = _iso8601Local.firstMatch(value);
  if (match == null) return false;

  final int year = int.parse(match.namedGroup('year')!);
  final int month = int.parse(match.namedGroup('month')!);
  final int day = int.parse(match.namedGroup('day')!);
  final int hour = int.parse(match.namedGroup('hour')!);
  final int minute = int.parse(match.namedGroup('minute')!);
  final String? secondText = match.namedGroup('second');
  final int second = secondText == null ? 0 : int.parse(secondText);

  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    return false;
  }
  // 当月天数用「下月一日减一天」求，闰年由构造正确，不硬编码表。
  final DateTime firstOfNextMonth = month == 12
      ? DateTime(year + 1)
      : DateTime(year, month + 1);
  final int daysInMonth = firstOfNextMonth
      .subtract(const Duration(days: 1))
      .day;
  return day >= 1 && day <= daysInMonth;
}

Map<String, dynamic> _decodeFirstJsonObject(String rawOutput) {
  final String withoutFences = rawOutput
      .replaceAll(RegExp(r'```json', caseSensitive: false), '')
      .replaceAll('```', '');
  final int start = withoutFences.indexOf('{');
  if (start == -1) {
    throw const FormatException('未找到 JSON 对象');
  }

  int depth = 0;
  bool inString = false;
  bool escaped = false;
  for (int index = start; index < withoutFences.length; index++) {
    final String character = withoutFences[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (character == r'\') {
        escaped = true;
      } else if (character == '"') {
        inString = false;
      }
      continue;
    }
    if (character == '"') {
      inString = true;
    } else if (character == '{') {
      depth++;
    } else if (character == '}') {
      depth--;
      if (depth == 0) {
        final Object? decoded = jsonDecode(
          withoutFences.substring(start, index + 1),
        );
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('输出的 JSON 不是对象');
        }
        return decoded;
      }
    }
  }
  throw const FormatException('JSON 对象括号不完整');
}
