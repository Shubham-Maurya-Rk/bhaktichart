class AppDateUtils {
  static String formatDate(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  static String monthStart(DateTime date) {
    return formatDate(DateTime(date.year, date.month, 1));
  }

  static String monthEnd(DateTime date) {
    return formatDate(DateTime(date.year, date.month + 1, 0));
  }
}
