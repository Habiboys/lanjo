import 'package:intl/intl.dart';

/// Period and Indonesian date helpers (BR-07, FR-10).
abstract final class ArusDateUtils {
  static final DateFormat _shortDate = DateFormat('d MMM yyyy', 'id_ID');
  static final DateFormat _shortDateTime = DateFormat('d MMM yyyy, HH:mm', 'id_ID');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy', 'id_ID');
  static final DateFormat _timeOnly = DateFormat('HH:mm', 'id_ID');

  static String formatShortDate(DateTime dt) => _shortDate.format(dt);
  static String formatDateTime(DateTime dt) => _shortDateTime.format(dt);
  static String formatMonthYear(DateTime dt) => _monthYear.format(dt);
  static String formatTime(DateTime dt) => _timeOnly.format(dt);

  static String formatRelativeDay(DateTime dt, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final d1 = DateTime(dt.year, dt.month, dt.day);
    final d2 = DateTime(ref.year, ref.month, ref.day);
    final diff = d2.difference(d1).inDays;
    if (diff == 0) return 'Hari ini, ${_timeOnly.format(dt)}';
    if (diff == 1) return 'Kemarin, ${_timeOnly.format(dt)}';
    if (diff == -1) return 'Besok, ${_timeOnly.format(dt)}';
    return _shortDateTime.format(dt);
  }

  /// Clamps a target day-of-month (1..31) to the last day of [year]/[month]
  /// (FR-10 short-month handling for days 29-31).
  static DateTime clampDayInMonth(int year, int month, int desiredDay) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = desiredDay.clamp(1, lastDay);
    return DateTime(year, month, day);
  }

  /// Computes the active financial period `[start, endExclusive)` anchored
  /// at [paydayDay] (default 1 = calendar month).
  static ({DateTime start, DateTime endExclusive, int remainingDays})
      currentFinancialPeriod({
    DateTime? now,
    int? paydayDay,
  }) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final anchor = (paydayDay ?? 1).clamp(1, 31);

    final thisMonthAnchor = clampDayInMonth(today.year, today.month, anchor);
    late DateTime start;
    late DateTime endExclusive;

    if (!today.isBefore(thisMonthAnchor)) {
      start = thisMonthAnchor;
      final nextMonth = today.month == 12
          ? DateTime(today.year + 1, 1)
          : DateTime(today.year, today.month + 1);
      endExclusive = clampDayInMonth(nextMonth.year, nextMonth.month, anchor);
    } else {
      final prevMonth = today.month == 1
          ? DateTime(today.year - 1, 12)
          : DateTime(today.year, today.month - 1);
      start = clampDayInMonth(prevMonth.year, prevMonth.month, anchor);
      endExclusive = thisMonthAnchor;
    }

    final remaining = endExclusive.difference(today).inDays;
    return (
      start: start,
      endExclusive: endExclusive,
      remainingDays: remaining < 1 ? 1 : remaining,
    );
  }

  /// Advances a due date by [frequency]: daily, weekly, monthly, yearly.
  static DateTime nextDueDate(
    DateTime current,
    String frequency, {
    int? preferredDayOfMonth,
  }) {
    switch (frequency) {
      case 'daily':
        return current.add(const Duration(days: 1));
      case 'weekly':
        return current.add(const Duration(days: 7));
      case 'yearly':
        return clampDayInMonth(
          current.year + 1,
          current.month,
          preferredDayOfMonth ?? current.day,
        );
      case 'monthly':
      default:
        final nextMonth = current.month == 12
            ? DateTime(current.year + 1, 1)
            : DateTime(current.year, current.month + 1);
        return clampDayInMonth(
          nextMonth.year,
          nextMonth.month,
          preferredDayOfMonth ?? current.day,
        );
    }
  }
}
