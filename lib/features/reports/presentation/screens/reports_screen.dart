import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/utils/result.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/models/category.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/models/transaction_query.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../../../transactions/domain/transaction_repository.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
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
            title: Text('reports'.tr()),
            actions: <Widget>[
              IconButton(tooltip: 'export'.tr(), onPressed: () => _openExportSheet(context, ref), icon: const Icon(Icons.ios_share_rounded)),
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
        title: 'export_report'.tr(),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: const Icon(Icons.table_chart_outlined, color: Colors.green),
              ),
              title: Text('csv_spreadsheet'.tr()),
              subtitle: Text('open_in_excel_numbers_or_sheets'.tr()),
              trailing: IconButton(
                tooltip: 'share_csv'.tr(),
                icon: const Icon(Icons.share_outlined, size: 20),
                onPressed: () {
                  Navigator.of(context).pop();
                  _export(context, ref, asPdf: false, shareDirectly: true);
                },
              ),
              onTap: () {
                Navigator.of(context).pop();
                _export(context, ref, asPdf: false);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(AppRadius.sm)),
                child: const Icon(Icons.picture_as_pdf_outlined, color: Colors.redAccent),
              ),
              title: Text('pdf_summary'.tr()),
              subtitle: Text('formatted_totals_and_full_ledger'.tr()),
              trailing: IconButton(
                tooltip: 'share_pdf'.tr(),
                icon: const Icon(Icons.share_outlined, size: 20),
                onPressed: () {
                  Navigator.of(context).pop();
                  _export(context, ref, asPdf: true, shareDirectly: true);
                },
              ),
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

  /// Generates the file, saves it where the user can find it, then opens or shares it.
  ///
  /// Every step is guarded: a failed font load, a rejected write path or a
  /// missing viewer app must surface as a message, never as a silent stall
  /// behind a "Preparing..." toast.
  Future<void> _export(BuildContext context, WidgetRef ref, {required bool asPdf, bool shareDirectly = false}) async {
    final String kind = asPdf ? 'pdf_summary'.tr() : 'csv_spreadsheet'.tr();
    final ReportRange range = ref.read(reportRangeProvider);
    final String currency = ref.read(currencyCodeProvider);
    final Map<String, Category> categories = ref.read(categoryLookupProvider);

    final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
    bool dialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (BuildContext _) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: <Widget>[
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                AppSpacing.md.gapW,
                Expanded(child: Text('generating_kind'.tr(namedArgs: <String, String>{'kind': kind}))),
              ],
            ),
          ),
        ),
      ).whenComplete(() => dialogOpen = false),
    );
    void closeDialog() {
      if (dialogOpen && navigator.mounted) {
        navigator.pop();
        dialogOpen = false;
      }
    }

    Result<File> result;
    String subtitle = range.label;
    try {
      debugPrint('[export] start kind=$kind range=${range.label}');
      // Query the repository directly rather than `reportTransactionsProvider.future`:
      // that provider chains through a StreamProvider whose `.future` never
      // resolves when nothing is listening, which left the dialog spinning forever.
      final TransactionRepository repository = ref.read(transactionRepositoryProvider);
      final Result<TransactionPage> page = await repository.getPage(TransactionQuery(from: range.from, to: range.to, pageSize: 1 << 30));
      List<Transaction> transactions = page.dataOrNull?.items ?? const <Transaction>[];
      debugPrint('[export] rows=${transactions.length}');
      if (transactions.isEmpty) {
        final List<Transaction> all = (await repository.exportAll()).dataOrNull ?? const <Transaction>[];
        if (all.isNotEmpty) {
          transactions = all;
          subtitle = 'all_transactions_label_had_no_activity'.tr(namedArgs: <String, String>{'label': range.label});
        }
      }

      if (transactions.isEmpty) {
        closeDialog();
        if (context.mounted) AppFeedback.warning(context, 'nothing_to_export_yet_add_a_transaction_first'.tr());
        return;
      }

      pw.Font? regularFont;
      pw.Font? boldFont;
      if (asPdf) {
        try {
          regularFont = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Regular.ttf'));
          boldFont = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-Bold.ttf'));
        } catch (_) {
          // Built-in Helvetica is fine; the report just loses the brand font.
        }
      }

      const ReportExporter exporter = ReportExporter();
      final String stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
      final String fileName = 'pocketpilot-${range.from.isoDate}-to-${range.to.isoDate}-$stamp';

      debugPrint('[export] writing $fileName');
      result = asPdf
          ? await exporter.toPdf(
              transactions: transactions,
              categories: categories,
              title: 'PocketPilot report',
              subtitle: subtitle,
              currencyCode: currency,
              fileName: fileName,
              regularFont: regularFont,
              boldFont: boldFont,
            )
          : await exporter.toCsv(transactions: transactions, categories: categories, fileName: fileName);
      debugPrint('[export] result=$result');
    } catch (error, stackTrace) {
      debugPrint('[export] threw $error $stackTrace');
      result = FailureResult<File>(FailureMapper.from(error, stackTrace));
    } finally {
      closeDialog();
    }

    if (!context.mounted) return;
    await result.when(
      success: (File file) => _deliver(context, file, asPdf: asPdf, subtitle: subtitle, shareDirectly: shareDirectly),
      failure: (Failure failure) async => AppFeedback.error(context, failure),
    );
  }

  /// Hands a finished export to the user: share sheet, system viewer, or at
  /// minimum a "saved to" message with a Share action if no viewer exists.
  Future<void> _deliver(BuildContext context, File file, {required bool asPdf, required String subtitle, required bool shareDirectly}) async {
    final String kind = asPdf ? 'pdf_summary'.tr() : 'csv_spreadsheet'.tr();
    final String mime = asPdf ? 'application/pdf' : 'text/csv';
    final String location = ReportExporter.isUserVisible(file.parent) ? 'Downloads/PocketPilot' : file.parent.path;

    Future<void> share() async {
      try {
        await SharePlus.instance.share(ShareParams(files: <XFile>[XFile(file.path, mimeType: mime)], text: 'PocketPilot report - $subtitle'));
      } catch (error, stackTrace) {
        if (context.mounted) AppFeedback.error(context, FailureMapper.from(error, stackTrace));
      }
    }

    if (shareDirectly) {
      await share();
      return;
    }

    OpenResult opened;
    try {
      opened = await OpenFilex.open(file.path, type: mime);
    } catch (error) {
      opened = OpenResult(type: ResultType.error, message: error.toString());
    }
    debugPrint('[export] open ${file.path} -> ${opened.type} ${opened.message}');
    if (!context.mounted) return;

    if (opened.type == ResultType.done) {
      AppFeedback.success(context, '$kind saved to $location');
      return;
    }

    // No viewer installed (common for CSV) — tell them where it is and offer the share sheet.
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text('$kind saved to $location'),
          action: SnackBarAction(label: 'share'.tr(), onPressed: share),
        ),
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
                label: 'income'.tr(),
                value: summary.income.toCurrency(currencyCode: currencyCode),
                color: context.finance.income,
              ),
              _Metric(
                label: 'expenses'.tr(),
                value: summary.expense.toCurrency(currencyCode: currencyCode),
                color: context.finance.expense,
              ),
            ],
          ),
          const Divider(height: AppSpacing.xxl),
          Row(
            children: <Widget>[
              _Metric(
                label: 'net'.tr(),
                value: summary.balance.toSignedCurrency(currencyCode: currencyCode),
                color: summary.balance >= 0 ? context.finance.income : context.finance.expense,
              ),
              _Metric(label: 'savings_rate'.tr(), value: summary.savingsRate.toPercent(), color: context.finance.savings),
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
              Expanded(child: Text('income_vs_expenses'.tr(), style: context.text.titleSmall)),
              _ChartLegend(color: context.finance.income, label: 'income'.tr()),
              AppSpacing.md.gapW,
              _ChartLegend(color: context.finance.expense, label: 'expenses'.tr()),
            ],
          ),
          AppSpacing.lg.gapH,
          series.when(
            data: (List<SeriesPoint> points) => Column(
              children: <Widget>[
                IncomeExpenseBarChart(points: points, currencyCode: currency),
                AppSpacing.xl.gapH,
                Text('running_balance'.tr(), style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
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
              Text('by_category'.tr(), style: context.text.titleSmall),
              const Spacer(),
              SegmentedButton<bool>(
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: <ButtonSegment<bool>>[
                  ButtonSegment<bool>(value: true, label: Text('out'.tr())),
                  ButtonSegment<bool>(value: false, label: Text('in'.tr())),
                ],
                selected: <bool>{expenses},
                onSelectionChanged: (Set<bool> selection) => ref.read(reportShowsExpensesProvider.notifier).setExpenses(expenses: selection.first),
              ),
            ],
          ),
          AppSpacing.lg.gapH,
          slices.when(
            data: (List<CategorySlice> data) => data.isEmpty
                ? AppEmptyState(icon: Icons.pie_chart_outline_rounded, title: 'nothing_to_show'.tr(), message: 'no_activity_in_this_period'.tr())
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
        Text('ranked'.tr(), style: context.text.titleMedium),
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
