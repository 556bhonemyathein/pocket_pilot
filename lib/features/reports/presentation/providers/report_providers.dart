import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_time_extensions.dart';
import '../../../../shared/models/category.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/models/transaction_query.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_repository.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../widgets/charts.dart';

/// The window the reports screen is currently showing.
class ReportRange {
  const ReportRange({
    required this.period,
    required this.from,
    required this.to,
  });

  final ReportPeriod period;
  final DateTime from;
  final DateTime to;

  String get label => switch (period) {
    ReportPeriod.weekly => 'week_of_formatted'.tr(namedArgs: <String, String>{'formatted': from.formatted}),
    ReportPeriod.monthly => from.monthYear,
    ReportPeriod.yearly => '${from.year}',
    ReportPeriod.custom => '${from.formatted} → ${to.formatted}',
  };

  static ReportRange forPeriod(ReportPeriod period, [DateTime? anchor]) {
    final DateTime now = anchor ?? DateTime.now();
    return switch (period) {
      ReportPeriod.weekly => ReportRange(
        period: period,
        from: now.startOfWeek,
        to: now.endOfWeek,
      ),
      ReportPeriod.monthly => ReportRange(
        period: period,
        from: now.startOfMonth,
        to: now.endOfMonth,
      ),
      ReportPeriod.yearly => ReportRange(
        period: period,
        from: now.startOfYear,
        to: now.endOfYear,
      ),
      ReportPeriod.custom => ReportRange(
        period: period,
        from: now.startOfMonth,
        to: now.endOfMonth,
      ),
    };
  }
}

/// Selected reporting window.
class ReportRangeNotifier extends Notifier<ReportRange> {
  @override
  ReportRange build() => ReportRange.forPeriod(ReportPeriod.monthly);

  void setPeriod(ReportPeriod period) =>
      state = ReportRange.forPeriod(period);

  void setCustom(DateTime from, DateTime to) => state = ReportRange(
    period: ReportPeriod.custom,
    from: from.startOfDay,
    to: to.endOfDay,
  );

  /// Steps the window back or forward — `direction` is -1 or 1.
  void shift(int direction) {
    final ReportRange current = state;
    state = switch (current.period) {
      ReportPeriod.weekly => ReportRange.forPeriod(
        ReportPeriod.weekly,
        current.from.add(Duration(days: 7 * direction)),
      ),
      ReportPeriod.monthly => ReportRange.forPeriod(
        ReportPeriod.monthly,
        DateTime(current.from.year, current.from.month + direction),
      ),
      ReportPeriod.yearly => ReportRange.forPeriod(
        ReportPeriod.yearly,
        DateTime(current.from.year + direction),
      ),
      // A custom range has no natural "next", so stepping is a no-op.
      ReportPeriod.custom => current,
    };
  }
}

final reportRangeProvider =
    NotifierProvider<ReportRangeNotifier, ReportRange>(
      ReportRangeNotifier.new,
      name: 'reportRange',
    );

/// Totals for the selected window.
final reportSummaryProvider = Provider<AsyncValue<TransactionSummary>>((
  Ref ref,
) {
  final ReportRange range = ref.watch(reportRangeProvider);
  return ref.watch(summaryProvider((from: range.from, to: range.to)));
}, name: 'reportSummary');

/// Whether the breakdown shows spending or earning.
class ReportModeNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  // ignore: avoid_positional_boolean_parameters
  void setExpenses({required bool expenses}) => state = expenses;
}

final reportShowsExpensesProvider =
    NotifierProvider<ReportModeNotifier, bool>(
      ReportModeNotifier.new,
      name: 'reportShowsExpenses',
    );

/// Category breakdown for the donut and the ranked list.
final reportByCategoryProvider = FutureProvider<List<CategorySlice>>((
  Ref ref,
) async {
  final ReportRange range = ref.watch(reportRangeProvider);
  final bool expensesOnly = ref.watch(reportShowsExpensesProvider);
  final Map<String, Category> lookup = ref.watch(categoryLookupProvider);

  // Re-run whenever the underlying data changes, not just the range.
  ref.watch(reportSummaryProvider);

  final result = await ref
      .watch(transactionRepositoryProvider)
      .totalsByCategory(
        from: range.from,
        to: range.to,
        expensesOnly: expensesOnly,
      );

  return result.when(
    success: (Map<String, double> totals) => totals.entries.map((
      MapEntry<String, double> entry,
    ) {
      final Category category = lookup[entry.key] ?? Category.unknown;
      return (
        label: category.name,
        value: entry.value,
        color: category.color,
      );
    }).toList(),
    failure: (_) => const <CategorySlice>[],
  );
}, name: 'reportByCategory');

/// Time series for the bar and line charts.
///
/// Daily points for short ranges, monthly buckets for a year — 365 bars would
/// be unreadable, and the axis labels would collide.
final reportSeriesProvider = FutureProvider<List<SeriesPoint>>((Ref ref) async {
  final ReportRange range = ref.watch(reportRangeProvider);
  ref.watch(reportSummaryProvider);

  final result = await ref
      .watch(transactionRepositoryProvider)
      .dailyTotals(from: range.from, to: range.to);

  final List<({DateTime day, double income, double expense})> days =
      result.dataOrNull ?? const <({DateTime day, double income, double expense})>[];

  if (range.period == ReportPeriod.yearly) {
    final Map<int, ({double income, double expense})> byMonth =
        <int, ({double income, double expense})>{};
    for (final ({DateTime day, double income, double expense}) d in days) {
      final ({double income, double expense}) current =
          byMonth[d.day.month] ?? (income: 0, expense: 0);
      byMonth[d.day.month] = (
        income: current.income + d.income,
        expense: current.expense + d.expense,
      );
    }
    return <SeriesPoint>[
      for (int month = 1; month <= 12; month++)
        (
          label: DateTime(range.from.year, month).monthYear.split(' ').first,
          income: byMonth[month]?.income ?? 0,
          expense: byMonth[month]?.expense ?? 0,
        ),
    ];
  }

  return days
      .map(
        (({DateTime day, double income, double expense}) d) => (
          label: range.period == ReportPeriod.weekly
              ? d.day.weekdayShort
              : '${d.day.day}',
          income: d.income,
          expense: d.expense,
        ),
      )
      .toList();
}, name: 'reportSeries');

/// Raw rows in the window — the source for CSV/PDF export.
final reportTransactionsProvider = FutureProvider<List<Transaction>>((
  Ref ref,
) async {
  final ReportRange range = ref.watch(reportRangeProvider);
  final page = await ref.watch(
    transactionPageProvider(
      TransactionQuery(
        from: range.from,
        to: range.to,
        pageSize: 1 << 30,
      ),
    ).future,
  );
  return page.items;
}, name: 'reportTransactions');
