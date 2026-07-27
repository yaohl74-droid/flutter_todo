/// 快速添加文本中解析出的任务标题与本地截止时间。
class ParsedTaskInput {
  const ParsedTaskInput({required this.title, required this.dueDate});

  final String title;
  final DateTime dueDate;
}

enum _TimePeriod { morning, afternoon, evening }

class _ParsedDateToken {
  const _ParsedDateToken({
    required this.match,
    required this.canonicalText,
    this.period,
  });

  final RegExpMatch match;
  final String canonicalText;
  final _TimePeriod? period;

  bool get isBareWeekday => canonicalText.startsWith('周');
}

final RegExp _unsupportedDatePattern = RegExp(
  r'每(?:天|日|晚|早|年|个?月)|'
  r'(?:每|本|上|这)(?:个)?(?:周|星期|礼拜)(?:[一二三四五六日天])?|'
  r'下下(?:个)?(?:周|星期|礼拜)(?:[一二三四五六日天])?|'
  r'月初|月底|\d{1,2}月\d{1,2}[日号]|'
  r'\d+(?:天|周|星期|礼拜|个月|月)后',
);

final RegExp _unsupportedTimePeriodPattern = RegExp(
  r'凌晨|后半晌|夜里|夜间|深夜|半夜|黎明|破晓',
);

final RegExp _datePattern = RegExp(
  r'明早|今晚|明晚|'
  r'下(?:个)?(?:周|星期|礼拜)[一二三四五六日天]|'
  r'(?:周|星期|礼拜)[一二三四五六日天]|'
  r'今天|明天|大后天|后天',
);

const String _chineseNumberCharacters = '零一二三四五六七八九十两';

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

/// 从一句快速添加文本中抽取一个受支持的日期/时间表达式。
///
/// [now] 用于相对日期和已过时间的计算；解析按设备本地时区进行。
/// 没有唯一、完整的受支持表达式时返回 null，由调用方保留原句。
ParsedTaskInput? parseNaturalLanguageTask(
  String input, {
  required DateTime now,
}) {
  if (_unsupportedDatePattern.hasMatch(input) ||
      _unsupportedTimePeriodPattern.hasMatch(input)) {
    return null;
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
    return null;
  }

  final _ParsedDateToken? dateToken = dateMatches.isEmpty
      ? null
      : _parseDateToken(dateMatches.single);

  final ({int hour, int minute})? parsedTime = timeMatches.isEmpty
      ? null
      : _parseTimeCandidate(
          timeMatches.single.group(0)!,
          inheritedPeriod: dateToken?.period,
        );
  if (timeMatches.isNotEmpty && parsedTime == null) {
    return null;
  }
  if (bareTimePeriodMatches.isNotEmpty ||
      (dateToken?.period != null && parsedTime == null)) {
    // 裸时段没有精确小时，不猜一个默认时间。
    return null;
  }
  if (dateToken == null && parsedTime == null) {
    return null;
  }

  final DateTime localNow = now.toLocal();
  final ({int hour, int minute}) effectiveTime =
      parsedTime ?? (hour: 23, minute: 59);
  DateTime dueDate = _resolveDate(
    dateToken?.canonicalText,
    localNow,
    effectiveTime.hour,
    effectiveTime.minute,
  );

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

  return ParsedTaskInput(title: title, dueDate: dueDate);
}

bool _matchesOverlap(RegExpMatch first, RegExpMatch second) =>
    first.start < second.end && second.start < first.end;

_ParsedDateToken _parseDateToken(RegExpMatch match) {
  final String text = match.group(0)!;
  return switch (text) {
    '明早' => _ParsedDateToken(
      match: match,
      canonicalText: '明天',
      period: _TimePeriod.morning,
    ),
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
    _
        when text.startsWith('周') ||
            text.startsWith('星期') ||
            text.startsWith('礼拜') =>
      _ParsedDateToken(
        match: match,
        canonicalText: '周${_canonicalWeekday(text)}',
      ),
    _ => _ParsedDateToken(match: match, canonicalText: text),
  };
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

DateTime _resolveDate(String? dateText, DateTime now, int hour, int minute) {
  final DateTime today = DateTime(now.year, now.month, now.day);
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
