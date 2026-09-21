import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/date_time_extensions.dart';
import '../../../../shared/models/category.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../reports/presentation/widgets/charts.dart';
import '../../../transactions/domain/transaction_repository.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';

/// Aggregations the dashboard needs, composed from the transaction providers.
///
/// Composition is the point: none of these touch Isar directly, they derive
/// from `summaryProvider` / `transactionRepositoryProvider`. Riverpod
/// recomputes them only when their inputs change, so the dashboard's six
/// widgets share one underlying database subscription.

/// Lifetime balance — the hero number.
final lifetimeSummaryProvider = Provider<AsyncValue<TransactionSummary>>(
  (Ref ref) => ref.watch(summaryProvider(lifetimeRange)),
  name: 'lifetimeSummary',
);

/// This calendar month, for the income/expense/savings cards.
final monthSummaryProvider = Provider<AsyncValue<TransactionSummary>>((Ref ref) {
  return ref.watch(summaryProvider(ref.watch(currentMonthRange)));
}, name: 'monthSummary');

/// Last seven days, income vs expense, for the dashboard bar chart.
final weeklySeriesProvider = FutureProvider<List<SeriesPoint>>((Ref ref) async {
  // Depend on the summary so the chart refreshes whenever a transaction lands.
  ref.watch(monthSummaryProvider);

  final DateTime now = DateTime.now();
  final DateTime from = now.subtract(const Duration(days: 6)).startOfDay;

  final result = await ref.watch(transactionRepositoryProvider).dailyTotals(from: from, to: now.endOfDay);

  return result.when(
    success: (List<({DateTime day, double income, double expense})> days) =>
        days.map((({DateTime day, double income, double expense}) d) => (label: d.day.weekdayShort, income: d.income, expense: d.expense)).toList(),
    failure: (_) => const <SeriesPoint>[],
  );
}, name: 'weeklySeries');

/// Spending by category this month, ready for the donut.
final monthByCategoryProvider = FutureProvider<List<CategorySlice>>((Ref ref) async {
  ref.watch(monthSummaryProvider);

  final range = ref.watch(currentMonthRange);
  final Map<String, Category> lookup = ref.watch(categoryLookupProvider);

  final result = await ref.watch(transactionRepositoryProvider).totalsByCategory(from: range.from, to: range.to, expensesOnly: true);

  return result.when(
    success: (Map<String, double> totals) => totals.entries
        // Six slices is the readability limit for a donut; beyond that the
        // labels collide and the chart stops communicating.
        .take(6)
        .map((MapEntry<String, double> e) {
          final Category category = lookup[e.key] ?? Category.unknown;
          return (label: category.name, value: e.value, color: category.color);
        })
        .toList(),
    failure: (_) => const <CategorySlice>[],
  );
}, name: 'monthByCategory');

/// Time-of-day greeting for the dashboard header.
final greetingProvider = Provider<String>((Ref ref) {
  final int hour = DateTime.now().hour;
  final String name = ref.watch(currentUserProvider)?.name.split(' ').first ?? '';
  final String part = switch (hour) {
    < 12 => 'good_morning'.tr(),
    < 18 => 'good_afternoon'.tr(),
    _ => 'good_evening'.tr(),
  };
  return name.isEmpty ? part : '$part, $name';
}, name: 'greeting');

/// Capitalized time-of-day greeting for the dashboard header (e.g. 'Good Morning').
///
/// Exposes the translation *key* rather than the text so the widget resolves
/// it at build time and a language change takes effect without restarting.
final greetingTimeOfDayProvider = Provider<String>((Ref ref) {
  final int hour = DateTime.now().hour;
  return switch (hour) {
    < 12 => 'good_morning_2',
    < 18 => 'good_afternoon_2',
    _ => 'good_evening_2',
  };
}, name: 'greetingTimeOfDay');

/// The user's monthly budget, falling back to zero (which hides the card).
final monthlyBudgetProvider = Provider<double>((Ref ref) => ref.watch(currentUserProvider)?.monthlyBudget ?? 0, name: 'monthlyBudget');

/// Convenience for the pull-to-refresh gesture: re-runs the derived providers.
Future<void> refreshDashboard(WidgetRef ref) async {
  ref
    ..invalidate(weeklySeriesProvider)
    ..invalidate(monthByCategoryProvider);
  await ref.read(weeklySeriesProvider.future);
}
