import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/models/category.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_repository.dart';
import '../../domain/report_exporter.dart';
import '../providers/report_providers.dart';
import '../widgets/charts.dart';

/// Weekly / monthly / yearly / custom reporting with export.
class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReportRange range = ref.watch(reportRangeProvider);
    final AsyncValue<TransactionSummary> summary = ref.watch(reportSummaryProvider);
    final String currency = ref.watch(currencyCodeProvider);

    return Scaffold(
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            floating: true,
            titleSpacing: AppSpacing.page,
            title: const Text('Reports'),
            actions: <Widget>[
              IconButton(tooltip: 'Export', onPressed: () => _openExportSheet(context, ref), icon: const Icon(Icons.ios_share_rounded)),
              AppSpacing.sm.gapW,
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, 120),
            sliver: SliverList.list(
              children: <Widget>[
                const _PeriodSelector(),
                AppSpacing.lg.gapH,
                _RangeStepper(range: range),
                AppSpacing.xl.gapH,

                summary.when(
                  data: (TransactionSummary data) => _SummaryGrid(summary: data, currencyCode: currency),
                  loading: () => AppShimmer.box(height: 140),
                  error: (Object error, _) => Text('$error'),
                ),
                AppSpacing.xxl.gapH,

                const _TrendCard(),
                AppSpacing.xxl.gapH,

                const _BreakdownCard(),
                AppSpacing.xxl.gapH,

                const _TopCategories(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openExportSheet(BuildContext context, WidgetRef ref) async {
    await AppFeedback.sheet<void>(
      context,
      child: AppBottomSheet(
        title: 'Export report',
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV spreadsheet'),
              subtitle: const Text('Open in Excel, Numbers or Sheets'),
              onTap: () {
                Navigator.of(context).pop();
                _export(context, ref, asPdf: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF summary'),
              subtitle: const Text('Formatted totals and full ledger'),
              onTap: () {
                Navigator.of(context).pop();
                _export(context, ref, asPdf: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Generates the file then hands it to the platform share sheet.
  ///
  /// Sharing rather than saving is deliberate: it lets the user decide the
  /// destination (mail, Drive, Files) without the app requesting storage
  /// permissions it does not otherwise need.
  Future<void> _export(BuildContext context, WidgetRef ref, {required bool asPdf}) async {
    final ReportRange range = ref.read(reportRangeProvider);
    final String currency = ref.read(currencyCodeProvider);
    final Map<String, Category> categories = ref.read(categoryLookupProvider);

    final List<Transaction> transactions = await ref.read(reportTransactionsProvider.future);

    if (!context.mounted) return;
    if (transactions.isEmpty) {
      AppFeedback.warning(context, 'Nothing to export in this period');
      return;
    }

    const ReportExporter exporter = ReportExporter();
    final String fileName = 'pocketpilot-${range.from.isoDate}-to-${range.to.isoDate}';

    final Result<File> result = asPdf
        ? await exporter.toPdf(
            transactions: transactions,
            categories: categories,
            title: 'PocketPilot report',
            subtitle: range.label,
            currencyCode: currency,
            fileName: fileName,
          )
        : await exporter.toCsv(transactions: transactions, categories: categories, fileName: fileName);

    if (!context.mounted) return;
    await result.when(
      success: (File file) async {
        await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(file.path)], text: 'PocketPilot report · ${range.label}'));
      },
      failure: (failure) async => AppFeedback.error(context, failure),
    );
  }
}

class _PeriodSelector extends ConsumerWidget {
  const _PeriodSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ReportPeriod current = ref.watch(reportRangeProvider).period;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final ReportPeriod period in ReportPeriod.values) ...<Widget>[
            ChoiceChip(
              label: Text(period.label),
              selected: current == period,
              onSelected: (_) async {
                if (period == ReportPeriod.custom) {
                  final DateTimeRange? picked = await showDateRangePicker(context: context, firstDate: DateTime(2015), lastDate: DateTime.now());
                  if (picked != null) {
                    ref.read(reportRangeProvider.notifier).setCustom(picked.start, picked.end);
                  }
                } else {
                  ref.read(reportRangeProvider.notifier).setPeriod(period);
                }
              },
            ),
            AppSpacing.sm.gapW,
          ],
        ],
      ),
    );
  }
}

class _RangeStepper extends ConsumerWidget {
  const _RangeStepper({required this.range});

  final ReportRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool canStep = range.period != ReportPeriod.custom;

    return Row(
      children: <Widget>[
        IconButton(onPressed: canStep ? () => ref.read(reportRangeProvider.notifier).shift(-1) : null, icon: const Icon(Icons.chevron_left_rounded)),
        Expanded(
          child: AnimatedSwitcher(
            duration: 220.ms,
            child: Text(range.label, key: ValueKey<String>(range.label), textAlign: TextAlign.center, style: context.text.titleMedium),
          ),
        ),
        IconButton(onPressed: canStep ? () => ref.read(reportRangeProvider.notifier).shift(1) : null, icon: const Icon(Icons.chevron_right_rounded)),
      ],
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary, required this.currencyCode});

  final TransactionSummary summary;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _Metric(
                label: 'Income',
                value: summary.income.toCurrency(currencyCode: currencyCode),
                color: context.finance.income,
              ),
              _Metric(
                label: 'Expenses',
                value: summary.expense.toCurrency(currencyCode: currencyCode),
                color: context.finance.expense,
              ),
            ],
          ),
          const Divider(height: AppSpacing.xxl),
          Row(
            children: <Widget>[
              _Metric(
                label: 'Net',
                value: summary.balance.toSignedCurrency(currencyCode: currencyCode),
                color: summary.balance >= 0 ? context.finance.income : context.finance.expense,
              ),
              _Metric(label: 'Savings rate', value: summary.savingsRate.toPercent(), color: context.finance.savings),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
          AppSpacing.xs.gapH,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: context.text.titleMedium?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends ConsumerWidget {
  const _TrendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SeriesPoint>> series = ref.watch(reportSeriesProvider);
    final String currency = ref.watch(currencyCodeProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: Text('Income vs expenses', style: context.text.titleSmall)),
              _ChartLegend(color: context.finance.income, label: 'Income'),
              AppSpacing.md.gapW,
              _ChartLegend(color: context.finance.expense, label: 'Expenses'),
            ],
          ),
          AppSpacing.lg.gapH,
          series.when(
            data: (List<SeriesPoint> points) => Column(
              children: <Widget>[
                IncomeExpenseBarChart(points: points, currencyCode: currency),
                AppSpacing.xl.gapH,
                Text('Running balance', style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                AppSpacing.md.gapH,
                BalanceLineChart(points: points, currencyCode: currency),
              ],
            ),
            loading: () => AppShimmer.box(height: 220),
            error: (Object error, _) => Text('$error'),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        AppSpacing.xs.gapW,
        Text(
          label,
          style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _BreakdownCard extends ConsumerWidget {
  const _BreakdownCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CategorySlice>> slices = ref.watch(reportByCategoryProvider);
    final bool expenses = ref.watch(reportShowsExpensesProvider);
    final String currency = ref.watch(currencyCodeProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('By category', style: context.text.titleSmall),
              const Spacer(),
              SegmentedButton<bool>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text('Out')),
                  ButtonSegment<bool>(value: false, label: Text('In')),
                ],
                selected: <bool>{expenses},
                onSelectionChanged: (Set<bool> selection) => ref.read(reportShowsExpensesProvider.notifier).setExpenses(expenses: selection.first),
              ),
            ],
          ),
          AppSpacing.lg.gapH,
          slices.when(
            data: (List<CategorySlice> data) => data.isEmpty
                ? const AppEmptyState(icon: Icons.pie_chart_outline_rounded, title: 'Nothing to show', message: 'No activity in this period.')
                : CategoryDonutChart(slices: data.take(8).toList(), currencyCode: currency),
            loading: () => AppShimmer.box(height: 240),
            error: (Object error, _) => Text('$error'),
          ),
        ],
      ),
    );
  }
}

class _TopCategories extends ConsumerWidget {
  const _TopCategories();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<CategorySlice> slices = ref.watch(reportByCategoryProvider).value ?? const <CategorySlice>[];
    if (slices.isEmpty) return const SizedBox.shrink();

    final String currency = ref.watch(currencyCodeProvider);
    final double total = slices.fold<double>(0, (double sum, CategorySlice s) => sum + s.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Ranked', style: context.text.titleMedium),
        AppSpacing.md.gapH,
        AppCard(
          child: Column(
            children: <Widget>[
              for (int i = 0; i < slices.length; i++) ...<Widget>[
                if (i > 0) AppSpacing.lg.gapH,
                _RankedRow(
                  slice: slices[i],
                  share: total <= 0 ? 0 : slices[i].value / total,
                  currencyCode: currency,
                ).animate(delay: (40 * i).ms).fadeIn().slideX(begin: 0.05),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({required this.slice, required this.share, required this.currencyCode});

  final CategorySlice slice;
  final double share;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(child: Text(slice.label, style: context.text.bodyMedium)),
            Text(slice.value.toCurrency(currencyCode: currencyCode), style: context.text.titleSmall),
          ],
        ),
        AppSpacing.sm.gapH,
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: TweenAnimationBuilder<double>(
            duration: 600.ms,
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: share),
            builder: (BuildContext context, double value, _) =>
                LinearProgressIndicator(value: value, minHeight: 6, color: slice.color, backgroundColor: context.colors.outlineVariant),
          ),
        ),
      ],
    );
  }
}
