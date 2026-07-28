/// 快速添加文本中解析出的任务标题与本地截止时间。
class ParsedTaskInput {
  const ParsedTaskInput({required this.title, required this.dueDate});

  final String title;
  final DateTime dueDate;
}

enum _TimePeriod { morning, afternoon, evening }

class _ParsedCalendarDate {
  const _ParsedCalendarDate({
    required this.day,
    this.year,
    this.month,
    this.monthOffset,
  });

  final int day;
  final int? year;
  final int? month;
  final int? monthOffset;
}

class _ParsedDateToken {
  const _ParsedDateToken({
    required this.match,
    required this.canonicalText,
    this.period,
    this.calendarDate,
    this.dayOffset,
  });

  final RegExpMatch match;
  final String canonicalText;
  final _TimePeriod? period;
  final _ParsedCalendarDate? calendarDate;

  /// 「N 天后」的天数偏移。相对今天计算。
  final int? dayOffset;

  bool get isBareWeekday =>
      calendarDate == null && canonicalText.startsWith('周');
}

const String _chineseNumberCharacters = '零一二三四五六七八九十两';
const String _calendarNumberPattern =
    '(?:\\d{1,2}|[$_chineseNumberCharacters]{1,3})';
const String _calendarYearPattern = '(?:\\d{4}|[零一二三四五六七八九]{4})';
const String _absoluteDateTextPattern =
    '(?:$_calendarYearPattern年)?'
    '$_calendarNumberPattern月$_calendarNumberPattern[日号號]';
const String _relativeMonthDateTextPattern =
    '(?:下(?:个)?月|这个月|本月)$_calendarNumberPattern[日号號]';

/// 「N 天后」。只做天粒度:周/月粒度在口语里并不确定(「3周后」是 21 天
/// 还是下下下周?),保守失败优于猜。
const String _relativeDayOffsetTextPattern =
    '(?:\\d{1,3}|[$_chineseNumberCharacters]{1,4})天(?:后|後)';

final RegExp _relativeDayOffsetPattern = RegExp(
  '^$_relativeDayOffsetTextPattern\$',
);

final RegExp _unsupportedDatePattern = RegExp(
  r'每(?:天|日|晚|早|年|个?月)|'
  // 「这/這/本周X」已改为支持(等价于裸星期词),这里只留「每」(重复)和
  // 「上」(指向过去)。
  r'(?:每|上)(?:个|個)?(?:周|週|星期|礼拜|禮拜)(?:[一二三四五六日天])?|'
  r'下下(?:个|個)?(?:周|週|星期|礼拜|禮拜)(?:[一二三四五六日天])?|'
  '月初|月底|'
  // 「N天后」已改为支持;周/月粒度仍不做 —— 「3周后」是 21 天还是下下下周,
  // 口语里并不确定,保守失败优于猜。
  r'\d+(?:周|星期|礼拜|个月|月)后|'
  '[$_chineseNumberCharacters]+(?:周|星期|礼拜|个月|月)后',
);

final RegExp _unsupportedTimePeriodPattern = RegExp(
  r'凌晨|后半晌|夜里|夜间|深夜|半夜|黎明|破晓',
);

final RegExp _datePattern = RegExp(
  '$_relativeMonthDateTextPattern|'
  '$_absoluteDateTextPattern|'
  // ⚠️ 顺序即优先级:带前缀的写法必须排在裸写法之前,否则只会匹配到后半段,
  // 前缀残留在标题里、日期还错一档 —— 这一族 bug 已复发五次。
  '$_relativeDayOffsetTextPattern|'
  r'明早|聽朝|今晚|明晚|'
  r'下(?:个|個)?(?:周|週|星期|礼拜|禮拜)[一二三四五六日天]|'
  r'(?:这|這|本)(?:个|個)?(?:周|週|星期|礼拜|禮拜)[一二三四五六日天]|'
  r'(?:周|週|星期|礼拜|禮拜)[一二三四五六日天]|'
  r'今天|明天|明日|聽日|大后天|大後天|大後日|后天|後天|後日',
);

final RegExp _relativeMonthDatePattern = RegExp(
  '^(下(?:个)?月|这个月|本月)'
  '($_calendarNumberPattern)[日号號]\$',
);

final RegExp _absoluteDatePattern = RegExp(
  '^(?:($_calendarYearPattern)年)?'
  '($_calendarNumberPattern)月'
  '($_calendarNumberPattern)[日号號]\$',
);

// 用宽模式先吃掉完整的“时间候选”，再由结构化解析校验支持范围。
// 这样“九点三十分”等未支持格式不会被部分截成“九点”。
final RegExp _timeCandidatePattern = RegExp(
  '中午(?:(?:\\d{1,3}|[$_chineseNumberCharacters]{1,4})点'
  '(?:半|一刻|三刻|\\d{1,3}分|[$_chineseNumberCharacters]{1,4}分|'
  '\\d{1,3}|整)?)?|'
  '(?:上午|早上|清早|下午|晚上|傍晚)\\s*'
  '(?:\\d{1,3}|[$_chineseNumberCharacters]{1,4})点'
  '(?:半|一刻|三刻|\\d{1,3}分|[$_chineseNumberCharacters]{1,4}分|'
  '\\d{1,3}|整)?|'
  '\\d{1,3}[:：]\\d{1,3}(?:分)?|'
  '(?:\\d{1,3}|[$_chineseNumberCharacters]{1,4})点'
  '(?:半|一刻|三刻|\\d{1,3}分|[$_chineseNumberCharacters]{1,4}分|'
  '\\d{1,3}|整)?',
);

final RegExp _periodTimePattern = RegExp(
  '^'
  r'(上午|早上|清早|下午|晚上|傍晚)'
  r'(\d{1,3}|[零一二三四五六七八九十两]{1,4})'
  r'点(.*)'
  r'$',
);

final RegExp _bareTimePeriodPattern = RegExp(r'上午|早上|清早|下午|晚上|傍晚');

/// 输入是否含有**明确列为不支持**的时间表达（重复任务、模糊日期、
/// 方向不明的星期词、裸时段无时刻）。
///
/// 与「没有任何时间表达」不同：后者只是没识别到，前者是解析器**认识它、
/// 并有意拒绝**。两者在 [parseNaturalLanguageTask] 里都返回 null，
/// 调用方若要区分二者（给用户提示、或决定要不要走别的解析途径），用这个。
bool hasUnsupportedTimeExpression(String input) =>
    earlyRejectionOf(input) != null;

/// 在做任何日期计算之前就能判定的拒绝原因；不需要 `now`。
///
/// [hasUnsupportedTimeExpression] 与 [parseNaturalLanguageTaskDetailed] **都从
/// 这里取结论**，不各自判断一遍。曾经两处各写一份，结果是「明早开会」在一处
/// 被拦下、在另一处被归错类——**同一个判断存在两份实现，迟早会漂移**。
ParseRejection? earlyRejectionOf(String input) {
  // 顺序有意义：重复语义优先于「写法不支持」，因为前者换任何解析器都无解。
  if (_recurringPattern.hasMatch(input)) {
    return ParseRejection.recurring;
  }
  if (_unsupportedDatePattern.hasMatch(input)) {
    return ParseRejection.unsupportedDateForm;
  }
  if (_unsupportedTimePeriodPattern.hasMatch(input)) {
    return ParseRejection.unsupportedTimeForm;
  }

  final List<RegExpMatch> timeMatches = _timeCandidatePattern
      .allMatches(input)
      .toList();
  final bool hasBareTimePeriod = _bareTimePeriodPattern
      .allMatches(input)
      .any(
        (periodMatch) => !timeMatches.any(
          (timeMatch) => _matchesOverlap(periodMatch, timeMatch),
        ),
      );
  final bool hasBareRelativePeriod =
      timeMatches.isEmpty && RegExp(r'明早|聽朝|今晚|明晚').hasMatch(input);
  if (hasBareTimePeriod || hasBareRelativePeriod) {
    return ParseRejection.bareTimePeriod;
  }
  return null;
}

final RegExp _pointTimePattern = RegExp(
  r'^(\d{1,3}|[零一二三四五六七八九十两]{1,4})点(.*)$',
);

const Map<String, int> _weekdayByText = <String, int>{
  '一': DateTime.monday,
  '二': DateTime.tuesday,
  '三': DateTime.wednesday,
  '四': DateTime.thursday,
  '五': DateTime.friday,
  '六': DateTime.saturday,
  '日': DateTime.sunday,
  '天': DateTime.sunday,
};

const Map<String, int> _chineseDigitValues = <String, int>{
  '零': 0,
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
};

const Map<String, int> _chineseHourByText = <String, int>{
  '一': 1,
  '二': 2,
  '两': 2,
  '三': 3,
  '四': 4,
  '五': 5,
  '六': 6,
  '七': 7,
  '八': 8,
  '九': 9,
  '十': 10,
  '十一': 11,
  '十二': 12,
};

/// 解析失败的原因。
///
/// 解析器有多处返回 null，但语义各不相同：有的是「没识别到」，有的是
/// 「识别到了但有意拒绝」，还有的是「信息本身就不足」。调用方若把它们
/// 一律当成「不知道」，就会做出错误决策——例如把一句根本没有时间表达的
/// 输入送去问模型，白付延迟、成本和隐私。
///
/// 这些取值由 [parseNaturalLanguageTaskDetailed] 与主解析路径**共用同一段
/// 代码**产出，不是在外部重新判断一遍——那样两边一定会随版本漂移。
enum ParseRejection {
  /// 解析成功。
  none,

  /// 重复任务（每天/每周/每月…）。数据模型只有单个截止时间，装不下。
  recurring,

  /// 日期写法不受支持（`月底`、`下下周三`…）。语义本身是可表达的。
  unsupportedDateForm,

  /// 时刻写法不受支持（`九点三十分`…）。同样只是写法问题。
  unsupportedTimeForm,

  /// 只有时段没有具体时刻（`明早开会`）。信息不在句子里。
  bareTimePeriod,

  /// 多个日期或时间候选，无法确定指哪一个。
  ambiguousCandidates,

  /// 整句没有任何时间表达（`买牛奶`）。
  noTimeExpression,

  /// 日期本身非法（`2月30号`）或超出可表示范围。
  invalidDate,
}

typedef ParseOutcome = ({ParsedTaskInput? task, ParseRejection reason});

/// 重复任务标记。从 [_unsupportedDatePattern] 里单独拆出来，是因为
/// 「装不下」和「写法不认识」对调用方的意义完全不同：前者换任何解析器
/// 或模型都无解，后者只是当前词表不够宽。
final RegExp _recurringPattern = RegExp(
  r'每(?:天|日|晚|早|年|个?月)|'
  r'每(?:个|個)?(?:周|週|星期|礼拜|禮拜)(?:[一二三四五六日天])?',
);

/// 从一句快速添加文本中抽取一个受支持的日期/时间表达式。
///
/// [now] 用于相对日期和已过时间的计算；解析按设备本地时区进行。
/// 没有唯一、完整的受支持表达式时返回 null，由调用方保留原句。
///
/// 需要知道**为什么**没解析出来时，用 [parseNaturalLanguageTaskDetailed]。
ParsedTaskInput? parseNaturalLanguageTask(
  String input, {
  required DateTime now,
}) => parseNaturalLanguageTaskDetailed(input, now: now).task;

/// 解析并说明失败原因。见 [ParseRejection]。
ParseOutcome parseNaturalLanguageTaskDetailed(
  String input, {
  required DateTime now,
}) {
  final ParseRejection? early = earlyRejectionOf(input);
  if (early != null) {
    return (task: null, reason: early);
  }

  final List<RegExpMatch> dateMatches = _datePattern.allMatches(input).toList();
  final List<RegExpMatch> timeMatches = _timeCandidatePattern
      .allMatches(input)
      .toList();
  final List<RegExpMatch> bareTimePeriodMatches = _bareTimePeriodPattern
      .allMatches(input)
      .where(
        (periodMatch) => !timeMatches.any(
          (timeMatch) => _matchesOverlap(periodMatch, timeMatch),
        ),
      )
      .toList();
  if (dateMatches.length > 1 || timeMatches.length > 1) {
    return (task: null, reason: ParseRejection.ambiguousCandidates);
  }

  final _ParsedDateToken? dateToken = dateMatches.isEmpty
      ? null
      : _parseDateToken(dateMatches.single);
  if (dateMatches.isNotEmpty && dateToken == null) {
    return (task: null, reason: ParseRejection.unsupportedDateForm);
  }

  final ({int hour, int minute})? parsedTime = timeMatches.isEmpty
      ? null
      : _parseTimeCandidate(
          timeMatches.single.group(0)!,
          inheritedPeriod: dateToken?.period,
        );
  if (timeMatches.isNotEmpty && parsedTime == null) {
    return (task: null, reason: ParseRejection.unsupportedTimeForm);
  }
  if (bareTimePeriodMatches.isNotEmpty ||
      (dateToken?.period != null && parsedTime == null)) {
    // 裸时段没有精确小时，不猜一个默认时间。
    return (task: null, reason: ParseRejection.bareTimePeriod);
  }
  if (dateToken == null && parsedTime == null) {
    return (task: null, reason: ParseRejection.noTimeExpression);
  }

  final DateTime localNow = now.toLocal();
  final ({int hour, int minute}) effectiveTime =
      parsedTime ?? (hour: 23, minute: 59);
  DateTime? dueDate = _resolveDate(
    dateToken,
    localNow,
    effectiveTime.hour,
    effectiveTime.minute,
  );
  if (dueDate == null) {
    return (task: null, reason: ParseRejection.invalidDate);
  }

  // 只写时间时默认取下一次到来的该时间，避免新建一个已经过期的任务。
  if (dateToken == null && !dueDate.isAfter(localNow)) {
    dueDate = dueDate.add(const Duration(days: 1));
  }

  // 裸星期词取最近一次尚未过去的目标时刻。
  if (dateToken?.isBareWeekday == true && !dueDate.isAfter(localNow)) {
    dueDate = dueDate.add(const Duration(days: 7));
  }

  final List<RegExpMatch> matchedTokens = <RegExpMatch>[
    if (dateToken != null) dateToken.match,
    ...timeMatches,
  ]..sort((first, second) => second.start.compareTo(first.start));
  String title = input;
  for (final RegExpMatch match in matchedTokens) {
    title = title.replaceRange(match.start, match.end, '');
  }
  title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

  return (
    task: ParsedTaskInput(title: title, dueDate: dueDate),
    reason: ParseRejection.none,
  );
}

bool _matchesOverlap(RegExpMatch first, RegExpMatch second) =>
    first.start < second.end && second.start < first.end;

_ParsedDateToken? _parseDateToken(RegExpMatch match) {
  final String text = match.group(0)!;

  if (_relativeDayOffsetPattern.hasMatch(text)) {
    // 去掉尾部的「天后/天後」,只留数量部分。
    final int? days = _parseCalendarNumber(text.substring(0, text.length - 2));
    // 0 天后没有意义;上限防止「一百天后」这类被当成正常输入。
    if (days == null || days < 1 || days > 999) {
      return null;
    }
    return _ParsedDateToken(match: match, canonicalText: text, dayOffset: days);
  }
  final RegExpMatch? relativeMonthMatch = _relativeMonthDatePattern.firstMatch(
    text,
  );
  if (relativeMonthMatch != null) {
    final int? day = _parseCalendarNumber(relativeMonthMatch.group(2)!);
    if (day == null) {
      return null;
    }
    return _ParsedDateToken(
      match: match,
      canonicalText: text,
      calendarDate: _ParsedCalendarDate(
        day: day,
        monthOffset: relativeMonthMatch.group(1)!.startsWith('下') ? 1 : 0,
      ),
    );
  }

  final RegExpMatch? absoluteMatch = _absoluteDatePattern.firstMatch(text);
  if (absoluteMatch != null) {
    final String? yearText = absoluteMatch.group(1);
    final int? year = yearText == null ? null : _parseCalendarYear(yearText);
    final int? month = _parseCalendarNumber(absoluteMatch.group(2)!);
    final int? day = _parseCalendarNumber(absoluteMatch.group(3)!);
    if ((yearText != null && year == null) || month == null || day == null) {
      return null;
    }
    return _ParsedDateToken(
      match: match,
      canonicalText: text,
      calendarDate: _ParsedCalendarDate(year: year, month: month, day: day),
    );
  }

  return switch (text) {
    '明早' || '聽朝' => _ParsedDateToken(
      match: match,
      canonicalText: '明天',
      period: _TimePeriod.morning,
    ),
    '明日' || '聽日' => _ParsedDateToken(match: match, canonicalText: '明天'),
    '後天' || '後日' => _ParsedDateToken(match: match, canonicalText: '后天'),
    '大後天' || '大後日' => _ParsedDateToken(match: match, canonicalText: '大后天'),
    '今晚' => _ParsedDateToken(
      match: match,
      canonicalText: '今天',
      period: _TimePeriod.evening,
    ),
    '明晚' => _ParsedDateToken(
      match: match,
      canonicalText: '明天',
      period: _TimePeriod.evening,
    ),
    _ when text.startsWith('下') => _ParsedDateToken(
      match: match,
      canonicalText: '下周${_canonicalWeekday(text)}',
    ),
    // 「这/這/本周X」与裸星期词同义:都指本周该天,已过则顺延到下一次。
    // 归一化成裸写法后复用同一条分支,不另开路径。
    _
        when text.startsWith('这') ||
            text.startsWith('這') ||
            text.startsWith('本') ||
            text.startsWith('周') ||
            text.startsWith('週') ||
            text.startsWith('星期') ||
            text.startsWith('礼拜') ||
            text.startsWith('禮拜') =>
      _ParsedDateToken(
        match: match,
        canonicalText: '周${_canonicalWeekday(text)}',
      ),
    _ => _ParsedDateToken(match: match, canonicalText: text),
  };
}

int? _parseCalendarNumber(String text) {
  if (_isArabicNumber(text)) {
    return int.parse(text);
  }
  // 「十」既是单字符，又是完整的十位数；必须先于单字数字分支处理。
  if (text == '十') {
    return 10;
  }
  if (text.length == 1) {
    return _chineseDigitValues[text];
  }

  final int firstTen = text.indexOf('十');
  if (firstTen < 0 || firstTen != text.lastIndexOf('十')) {
    return null;
  }
  final String tensText = text.substring(0, firstTen);
  final String onesText = text.substring(firstTen + 1);
  final int? tens = tensText.isEmpty ? 1 : _chineseDigitValues[tensText];
  final int? ones = onesText.isEmpty ? 0 : _chineseDigitValues[onesText];
  if (tens == null || ones == null || tens == 0) {
    return null;
  }
  return tens * 10 + ones;
}

int? _parseCalendarYear(String text) {
  if (_isArabicNumber(text)) {
    return int.parse(text);
  }
  if (text.length != 4) {
    return null;
  }

  int year = 0;
  for (final int codeUnit in text.codeUnits) {
    final int? digit = _chineseDigitValues[String.fromCharCode(codeUnit)];
    if (digit == null) {
      return null;
    }
    year = year * 10 + digit;
  }
  return year;
}

String _canonicalWeekday(String text) {
  final String weekday = text.substring(text.length - 1);
  return weekday == '天' ? '日' : weekday;
}

({int hour, int minute})? _parseTimeCandidate(
  String text, {
  required _TimePeriod? inheritedPeriod,
}) {
  if (text.startsWith('中午')) {
    if (inheritedPeriod != null) {
      return null;
    }
    return _parseNoon(text);
  }

  final RegExpMatch? periodMatch = _periodTimePattern.firstMatch(text);
  if (periodMatch != null) {
    if (inheritedPeriod != null || text.contains(RegExp(r'\s'))) {
      return null;
    }
    final _TimePeriod period = _periodFromText(periodMatch.group(1)!);
    final int? hour = _parseHour(periodMatch.group(2)!);
    final String minuteText = periodMatch.group(3)!;
    if (_isArabicNumber(minuteText)) {
      return null;
    }
    final int? minute = _parseMinuteSuffix(minuteText);
    if (hour == null || minute == null) {
      return null;
    }
    final int? normalizedHour = _applyPeriod(hour, period);
    return normalizedHour == null
        ? null
        : (hour: normalizedHour, minute: minute);
  }

  if (text.contains(':') || text.contains('：')) {
    if (inheritedPeriod != null || text.contains('：') || text.endsWith('分')) {
      return null;
    }
    final List<String> parts = text.split(RegExp('[:：]'));
    if (parts.length != 2 ||
        parts[1].length != 2 ||
        !_isArabicNumber(parts[0]) ||
        !_isArabicNumber(parts[1])) {
      return null;
    }
    final int hour = int.parse(parts[0]);
    final int minute = int.parse(parts[1]);
    return hour <= 23 && minute <= 59 ? (hour: hour, minute: minute) : null;
  }

  final RegExpMatch? pointMatch = _pointTimePattern.firstMatch(text);
  if (pointMatch == null) {
    return null;
  }
  final String hourText = pointMatch.group(1)!;
  final String minuteText = pointMatch.group(2)!;
  final int? hour = _parseHour(hourText);
  final int? minute = _parseMinuteSuffix(minuteText);
  if (hour == null || minute == null) {
    return null;
  }

  if (inheritedPeriod != null) {
    if (_isArabicNumber(minuteText)) {
      return null;
    }
    final int? normalizedHour = _applyPeriod(hour, inheritedPeriod);
    return normalizedHour == null
        ? null
        : (hour: normalizedHour, minute: minute);
  }

  if (!_isArabicNumber(hourText)) {
    // 无时段的中文小时只支持一至十一；“十二点”仍有午间/午夜歧义。
    return hour <= 11 && !_isArabicNumber(minuteText)
        ? (hour: hour, minute: minute)
        : null;
  }

  // 无时段的阿拉伯数字小时沿用 24 小时制：裸“H点”不支持；
  // H点MM 要求两位分钟，H点X分/H点XX分允许一至两位分钟。
  final bool hasOralMinute =
      minuteText == '半' || minuteText == '一刻' || minuteText == '三刻';
  if (minuteText.isEmpty ||
      (!hasOralMinute && !minuteText.endsWith('分') && minuteText.length != 2)) {
    return null;
  }
  return hour <= 23 ? (hour: hour, minute: minute) : null;
}

({int hour, int minute})? _parseNoon(String text) {
  if (text == '中午') {
    return (hour: 12, minute: 0);
  }
  final String remainder = text.substring(2);
  final RegExpMatch? match = _pointTimePattern.firstMatch(remainder);
  if (match == null) {
    return null;
  }
  final int? hour = _parseHour(match.group(1)!);
  final int? minute = _parseMinuteSuffix(match.group(2)!);
  return hour == 12 && minute != null ? (hour: 12, minute: minute) : null;
}

_TimePeriod _periodFromText(String text) {
  return switch (text) {
    '上午' || '早上' || '清早' => _TimePeriod.morning,
    '下午' => _TimePeriod.afternoon,
    '晚上' || '傍晚' => _TimePeriod.evening,
    _ => throw StateError('未知时段：$text'),
  };
}

int? _applyPeriod(int hour, _TimePeriod period) {
  return switch (period) {
    _TimePeriod.morning when hour >= 1 && hour <= 11 => hour,
    _TimePeriod.afternoon when hour >= 1 && hour <= 11 => hour + 12,
    _TimePeriod.evening when hour >= 6 && hour <= 11 => hour + 12,
    _ => null,
  };
}

int? _parseHour(String text) {
  if (_isArabicNumber(text)) {
    return int.tryParse(text);
  }
  return _chineseHourByText[text];
}

int? _parseMinuteSuffix(String text) {
  if (text.isEmpty) {
    return 0;
  }
  switch (text) {
    case '半':
      return 30;
    case '一刻':
      return 15;
    case '三刻':
      return 45;
  }
  if (text == '整' || !text.endsWith('分')) {
    if (!_isArabicNumber(text) || text.length != 2) {
      return null;
    }
  }
  final String minuteText = text.endsWith('分')
      ? text.substring(0, text.length - 1)
      : text;
  if (!_isArabicNumber(minuteText) ||
      minuteText.isEmpty ||
      minuteText.length > 2) {
    return null;
  }
  final int minute = int.parse(minuteText);
  return minute <= 59 ? minute : null;
}

bool _isArabicNumber(String text) => RegExp(r'^\d+$').hasMatch(text);

DateTime? _resolveDate(
  _ParsedDateToken? dateToken,
  DateTime now,
  int hour,
  int minute,
) {
  final _ParsedCalendarDate? calendarDate = dateToken?.calendarDate;
  if (calendarDate != null) {
    return _resolveCalendarDate(calendarDate, now, hour, minute);
  }

  final DateTime today = DateTime(now.year, now.month, now.day);

  // 命名避开下方裸星期词分支里的同名局部变量。
  final int? relativeDays = dateToken?.dayOffset;
  if (relativeDays != null) {
    // 用日历字段构造,靠溢出归一化处理跨月/跨年/闰年。
    return DateTime(
      today.year,
      today.month,
      today.day + relativeDays,
      hour,
      minute,
    );
  }

  final String? dateText = dateToken?.canonicalText;
  if (dateText == null || dateText == '今天') {
    return DateTime(today.year, today.month, today.day, hour, minute);
  }
  if (dateText == '明天') {
    final DateTime tomorrow = today.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, hour, minute);
  }
  if (dateText == '后天') {
    final DateTime dayAfterTomorrow = today.add(const Duration(days: 2));
    return DateTime(
      dayAfterTomorrow.year,
      dayAfterTomorrow.month,
      dayAfterTomorrow.day,
      hour,
      minute,
    );
  }
  if (dateText == '大后天') {
    final DateTime threeDaysLater = today.add(const Duration(days: 3));
    return DateTime(
      threeDaysLater.year,
      threeDaysLater.month,
      threeDaysLater.day,
      hour,
      minute,
    );
  }

  final bool nextWeek = dateText.startsWith('下周');
  final int targetWeekday =
      _weekdayByText[dateText.substring(dateText.length - 1)]!;
  final int dayOffset = nextWeek
      ? DateTime.daysPerWeek - now.weekday + targetWeekday
      : (targetWeekday - now.weekday + DateTime.daysPerWeek) %
            DateTime.daysPerWeek;
  final DateTime targetDate = today.add(Duration(days: dayOffset));
  return DateTime(
    targetDate.year,
    targetDate.month,
    targetDate.day,
    hour,
    minute,
  );
}

DateTime? _resolveCalendarDate(
  _ParsedCalendarDate date,
  DateTime now,
  int hour,
  int minute,
) {
  final int? monthOffset = date.monthOffset;
  if (monthOffset != null) {
    final int zeroBasedMonth = now.month - 1 + monthOffset;
    final int year = now.year + zeroBasedMonth ~/ DateTime.monthsPerYear;
    final int month = zeroBasedMonth % DateTime.monthsPerYear + 1;
    return _validCalendarDate(year, month, date.day, hour, minute);
  }

  final int month = date.month!;
  final int? explicitYear = date.year;
  if (explicitYear != null) {
    return _validCalendarDate(explicitYear, month, date.day, hour, minute);
  }

  final DateTime? thisYear = _validCalendarDate(
    now.year,
    month,
    date.day,
    hour,
    minute,
  );
  if (thisYear == null || thisYear.isAfter(now)) {
    return thisYear;
  }
  return _validCalendarDate(now.year + 1, month, date.day, hour, minute);
}

DateTime? _validCalendarDate(
  int year,
  int month,
  int day,
  int hour,
  int minute,
) {
  if (year < 1 || month < 1 || month > DateTime.monthsPerYear || day < 1) {
    return null;
  }
  final DateTime firstDayOfNextMonth = month == DateTime.monthsPerYear
      ? DateTime(year + 1)
      : DateTime(year, month + 1);
  final int daysInMonth = firstDayOfNextMonth
      .subtract(const Duration(days: 1))
      .day;
  if (day > daysInMonth) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}
