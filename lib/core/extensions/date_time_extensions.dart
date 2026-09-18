import 'package:easy_localization/easy_localization.dart';

/// Date helpers used by reports, filters and transaction grouping.
extension DateTimeX on DateTime {
  // ── Formatting ──────────────────────────────────────────────────────────────

  /// `12 Aug 2026`
  String get formatted => DateFormat('d MMM yyyy').format(this);

  /// `12 Aug 2026 · 14:05`
  String get formattedWithTime => DateFormat('d MMM yyyy · HH:mm').format(this);

  /// `Aug 2026`
  String get monthYear => DateFormat('MMM yyyy').format(this);

  /// `Wed`
  String get weekdayShort => DateFormat('EEE').format(this);

  /// ISO-8601 date only — the wire format for API query parameters.
  String get isoDate => DateFormat('yyyy-MM-dd').format(this);

  /// Human label used in transaction list section headers.
  String get relativeLabel {
    if (isToday) return 'today'.tr();
    if (isYesterday) return 'yesterday'.tr();
    if (isSameYear(DateTime.now())) return DateFormat('d MMM').format(this);
    return formatted;
  }

  // ── Comparison ──────────────────────────────────────────────────────────────

  bool isSameDay(DateTime other) =>
      year == other.year && month == other.month && day == other.day;

  bool isSameMonth(DateTime other) =>
      year == other.year && month == other.month;

  bool isSameYear(DateTime other) => year == other.year;

  bool get isToday => isSameDay(DateTime.now());

  bool get isYesterday =>
      isSameDay(DateTime.now().subtract(const Duration(days: 1)));

  /// Inclusive range check on calendar days, ignoring the time component.
  bool isBetween(DateTime start, DateTime end) {
    final DateTime d = dateOnly;
    return !d.isBefore(start.dateOnly) && !d.isAfter(end.dateOnly);
  }

  // ── Boundaries ──────────────────────────────────────────────────────────────

  DateTime get dateOnly => DateTime(year, month, day);

  DateTime get startOfDay => DateTime(year, month, day);

  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59, 999);

  /// Monday-based week start, matching the weekly report definition.
  DateTime get startOfWeek =>
      dateOnly.subtract(Duration(days: weekday - DateTime.monday));

  DateTime get endOfWeek =>
      startOfWeek.add(const Duration(days: 6)).endOfDay;

  DateTime get startOfMonth => DateTime(year, month);

  DateTime get endOfMonth => DateTime(year, month + 1, 0, 23, 59, 59, 999);

  DateTime get startOfYear => DateTime(year);

  DateTime get endOfYear => DateTime(year, 12, 31, 23, 59, 59, 999);
}
