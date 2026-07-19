/// 将绝对时刻转换成设备当前本地时间，并统一显示到分钟。
String formatDateTime(DateTime date) {
  final DateTime localDate = date.toLocal();
  final String month = localDate.month.toString().padLeft(2, '0');
  final String day = localDate.day.toString().padLeft(2, '0');
  final String hour = localDate.hour.toString().padLeft(2, '0');
  final String minute = localDate.minute.toString().padLeft(2, '0');
  return '${localDate.year}-$month-$day $hour:$minute';
}
