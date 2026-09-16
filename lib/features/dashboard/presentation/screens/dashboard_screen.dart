import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../shared/models/app_user.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../reports/presentation/widgets/charts.dart';
import '../../../transactions/domain/transaction_repository.dart';
import '../../../transactions/presentation/providers/transaction_providers.dart';
import '../../../transactions/presentation/widgets/transaction_tile.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/balance_card.dart';
import '../widgets/stat_card.dart';

/// The home screen.
///
/// Built from `CustomScrollView` slivers so the app bar can collapse smoothly
/// and so each section can decide its own loading treatment — a skeleton for
/// the list, a placeholder for the chart — instead of one page-wide spinner
/// that blocks everything on the slowest query.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String currency = ref.watch(currencyCodeProvider);
    final AsyncValue<TransactionSummary> lifetime = ref.watch(lifetimeSummaryProvider);
    final AsyncValue<TransactionSummary> month = ref.watch(monthSummaryProvider);
    final double budget = ref.watch(monthlyBudgetProvider);

    return RefreshIndicator(
      onRefresh: () => refreshDashboard(ref),
      child: CustomScrollView(
        // Always scrollable so pull-to-refresh works even on a short page.
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            floating: true,
            titleSpacing: AppSpacing.page,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(ref.watch(greetingProvider), style: context.text.titleMedium),
                Text(DateTime.now().formatted, style: context.text.labelSmall?.copyWith(color: context.colors.onSurfaceVariant)),
              ],
            ),
            actions: <Widget>[
              IconButton(
                tooltip: 'Search',
                onPressed: () => context.go('${AppRoutes.transactions}/${AppRoutes.search}'),
                icon: const Icon(Icons.search_rounded),
              ),
              const _AvatarButton(),
              AppSpacing.md.gapW,
            ],
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              0,
              AppSpacing.page,
              120, // clears the floating nav bar and the FAB
            ),
            sliver: SliverList.list(
              children: <Widget>[
                // ── Balance ───────────────────────────────────────────────
                lifetime.when(
                  data: (TransactionSummary summary) =>
                      BalanceCard(balance: summary.balance, currencyCode: currency, income: summary.income, expense: summary.expense),
                  loading: () => AppShimmer.box(height: 180, radius: AppRadius.xl),
                  error: (Object error, _) => AppCard(child: Text('Could not load your balance: $error')),
                ),
                AppSpacing.lg.gapH,

                // ── Quick actions ─────────────────────────────────────────
                const _QuickActions(),
                AppSpacing.xl.gapH,

                // ── Month stats ───────────────────────────────────────────
                Text('This month', style: context.text.titleMedium),
                AppSpacing.md.gapH,
                month.when(
                  data: (TransactionSummary summary) => _StatRow(summary: summary, currencyCode: currency),
                  loading: () => AppShimmer.box(height: 120),
                  error: (Object error, _) => const SizedBox.shrink(),
                ),

                if (budget > 0) ...<Widget>[
                  AppSpacing.lg.gapH,
                  BudgetProgressCard(
                    spent: month.value?.expense ?? 0,
                    budget: budget,
                    currencyCode: currency,
                    onTap: () => context.go(AppRoutes.reports),
                  ),
                ],
                AppSpacing.xxl.gapH,

                // ── Weekly chart ──────────────────────────────────────────
                const _WeeklyChartSection(),
                AppSpacing.xxl.gapH,

                // ── Category donut ────────────────────────────────────────
                const _CategorySection(),
                AppSpacing.xxl.gapH,

                // ── Recent activity ───────────────────────────────────────
                const _RecentSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarButton extends ConsumerWidget {
  const _AvatarButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppUser? user = ref.watch(currentUserProvider);

    return GestureDetector(
      onTap: () => context.go(AppRoutes.profile),
      child: UserAvatar(avatarUrl: user?.avatarUrl, name: user?.name, radius: 18, heroTag: 'dashboard-avatar'),
    );
  }
}

/// Shortcuts to the three ways of adding money movement.
class _QuickActions extends ConsumerWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<({String label, IconData icon, Color color, TransactionType type})> actions =
        <({String label, IconData icon, Color color, TransactionType type})>[
          (label: 'Income', icon: Icons.south_west_rounded, color: context.finance.income, type: TransactionType.income),
          (label: 'Expense', icon: Icons.north_east_rounded, color: context.finance.expense, type: TransactionType.expense),
          (label: 'Transfer', icon: Icons.swap_horiz_rounded, color: context.finance.transfer, type: TransactionType.transfer),
        ];

    return Row(
      children: <Widget>[
        for (int i = 0; i < actions.length; i++) ...<Widget>[
          if (i > 0) AppSpacing.md.gapW,
          Expanded(
            child: AppCard(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              onTap: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}'),
              child: Column(
                children: <Widget>[
                  Icon(actions[i].icon, size: 20, color: actions[i].color),
                  AppSpacing.sm.gapH,
                  Text(actions[i].label, style: context.text.labelMedium),
                ],
              ),
            ).animate(delay: (60 * i).ms).fadeIn().slideY(begin: 0.2),
          ),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.summary, required this.currencyCode});

  final TransactionSummary summary;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    // `stretch` makes the three cards share a height — the "Saved" card is
    // taller when it carries a caption, and ragged card bottoms look broken.
    // But stretch resolves to a *tight* cross-axis constraint taken from the
    // incoming maxHeight, which is unbounded inside a sliver. `IntrinsicHeight`
    // measures the tallest card first and hands the Row a bounded height.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: StatCard(
              label: 'Income',
              amount: summary.income,
              currencyCode: currencyCode,
              color: context.finance.income,
              icon: Icons.south_west_rounded,
            ),
          ),
          AppSpacing.md.gapW,
          Expanded(
            child: StatCard(
              label: 'Expenses',
              amount: summary.expense,
              currencyCode: currencyCode,
              color: context.finance.expense,
              icon: Icons.north_east_rounded,
            ),
          ),
          AppSpacing.md.gapW,
          Expanded(
            child: StatCard(
              label: 'Saved',
              amount: summary.balance,
              currencyCode: currencyCode,
              color: context.finance.savings,
              icon: Icons.savings_outlined,
              caption: summary.savingsRate > 0 ? '${summary.savingsRate.toPercent()} of income' : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyChartSection extends ConsumerWidget {
  const _WeeklyChartSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SeriesPoint>> series = ref.watch(weeklySeriesProvider);
    final String currency = ref.watch(currencyCodeProvider);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('Last 7 days', style: context.text.titleSmall),
              const Spacer(),
              _LegendDot(color: context.finance.income, label: 'In'),
              AppSpacing.md.gapW,
              _LegendDot(color: context.finance.expense, label: 'Out'),
            ],
          ),
          AppSpacing.lg.gapH,
          series.when(
            data: (List<SeriesPoint> points) => IncomeExpenseBarChart(points: points, currencyCode: currency),
            loading: () => AppShimmer.box(height: 220),
            error: (Object error, _) => SizedBox(height: 220, child: Center(child: Text('Chart unavailable: $error'))),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          height: 8,
          width: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        AppSpacing.xs.gapW,
        Text(label, style: context.text.labelSmall),
      ],
    );
  }
}

class _CategorySection extends ConsumerWidget {
  const _CategorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<CategorySlice>> slices = ref.watch(monthByCategoryProvider);
    final String currency = ref.watch(currencyCodeProvider);

    return slices.when(
      data: (List<CategorySlice> data) {
        if (data.isEmpty) return const SizedBox.shrink();
        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Where it went', style: context.text.titleSmall),
              AppSpacing.lg.gapH,
              CategoryDonutChart(slices: data, currencyCode: currency),
            ],
          ),
        );
      },
      loading: () => AppShimmer.box(height: 260, radius: AppRadius.lg),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _RecentSection extends ConsumerWidget {
  const _RecentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Transaction>> recent = ref.watch(recentTransactionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Recent activity', style: context.text.titleMedium),
            const Spacer(),
            TextButton(onPressed: () => context.go(AppRoutes.transactions), child: const Text('See all')),
          ],
        ),
        AppSpacing.sm.gapH,
        recent.when(
          data: (List<Transaction> items) {
            if (items.isEmpty) {
              return AppCard(
                child: AppEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No transactions yet',
                  message: 'Tap Add to record your first one.',
                  actionLabel: 'Add transaction',
                  onAction: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}'),
                ),
              );
            }
            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < items.length; i++) ...<Widget>[
                    if (i > 0) const Divider(height: 1),
                    TransactionTile(
                      transaction: items[i],
                      showDate: true,
                      onTap: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}', extra: items[i]),
                    ).animate(delay: (40 * i).ms).fadeIn().slideX(begin: 0.05),
                  ],
                ],
              ),
            );
          },
          loading: () => const AppCard(child: TransactionListSkeleton()),
          error: (Object error, _) => AppCard(child: Text('$error')),
        ),
      ],
    );
  }
}
