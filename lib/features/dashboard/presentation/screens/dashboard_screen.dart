import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            pinned: false,
            toolbarHeight: 64,
            titleSpacing: AppSpacing.page,
            backgroundColor: context.isDark ? context.colors.surface : Colors.white,
            surfaceTintColor: Colors.transparent,
            systemOverlayStyle: context.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            elevation: 0,
            flexibleSpace: DecoratedBox(decoration: BoxDecoration(color: context.isDark ? context.colors.surface : Colors.white)),
            title: Row(
              children: <Widget>[
                const _AvatarButton(),
                AppSpacing.sm.gapW,
                Text(
                  ref.watch(greetingTimeOfDayProvider),
                  style: context.text.titleSmall?.copyWith(
                    color: context.isDark ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: -0.2,
                  ),
                ),
                AppSpacing.md.gapW,
                const Expanded(child: _CapsuleSearchBar()),
              ],
            ),
            actions: const <Widget>[],
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.md,
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
    final bool isDark = context.isDark;

    return GestureDetector(
      onTap: () => context.go(AppRoutes.profile),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? Colors.white24 : const Color(0xFFE2E8F0), width: 1.5),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: UserAvatar(avatarUrl: user?.avatarUrl, name: user?.name, radius: 17, heroTag: 'dashboard-avatar'),
      ),
    );
  }
}

/// Stadium / capsule search bar with neon border, banner illustration and cycling keywords.
class _CapsuleSearchBar extends StatefulWidget {
  const _CapsuleSearchBar();

  @override
  State<_CapsuleSearchBar> createState() => _CapsuleSearchBarState();
}

class _CapsuleSearchBarState extends State<_CapsuleSearchBar> {
  static const List<String> _hints = <String>['SP Bakery', 'City Mart', 'Coffee & Tea', 'Groceries', 'Snacks', 'Search...'];

  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (mounted) {
        setState(() {
          _index = (_index + 1) % _hints.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = context.isDark;
    final Color capsuleBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9);
    final Color textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final Color iconColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);

    return GestureDetector(
      onTap: () => context.go('${AppRoutes.transactions}/${AppRoutes.search}'),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: capsuleBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF38BDF8), width: 1.5),
          boxShadow: <BoxShadow>[BoxShadow(color: const Color(0xFF00E5FF).withValues(alpha: isDark ? 0.25 : 0.12), blurRadius: 8, spreadRadius: 0.5)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // Banner illustration artwork
              CustomPaint(
                painter: _CapsuleBannerPainter(fadeColor: capsuleBg, isDark: isDark),
              ),

              // Content row
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 10),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 80,
                      child: AnimatedSwitcher(
                        duration: 300.ms,
                        layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
                          return Stack(alignment: Alignment.centerLeft, children: <Widget>[...previousChildren, ?currentChild]);
                        },
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.35),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          _hints[_index],
                          key: ValueKey<int>(_index),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textColor, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.search_rounded, color: iconColor, size: 21),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Illustrates the warm banner motif on the right side of the capsule search bar.
class _CapsuleBannerPainter extends CustomPainter {
  const _CapsuleBannerPainter({required this.fadeColor, required this.isDark});

  final Color fadeColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Right-half warm ambient bakery/store glow
    final Rect glowRect = Rect.fromLTWH(w * 0.48, 0, w * 0.52, h);
    final Paint glowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[Colors.transparent, const Color(0x22F59E0B), const Color(0x44FB923C), Color(isDark ? 0x6638BDF8 : 0x2238BDF8)],
        stops: const <double>[0.0, 0.25, 0.65, 1.0],
      ).createShader(glowRect);
    canvas.drawRect(glowRect, glowPaint);

    // Warm bakery / merchant box on the right
    final Paint boxPaint = Paint()..color = const Color(0xFFF97316);
    final RRect box = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.59, h * 0.62), width: 14, height: 13), const Radius.circular(3.5));
    canvas.drawRRect(box, boxPaint);

    // Mini box lid
    final Paint lidPaint = Paint()..color = const Color(0xFFEA580C);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.59, h * 0.54), width: 15, height: 3.5), const Radius.circular(1.5)),
      lidPaint,
    );

    // Character with round glasses
    final Offset headCenter = Offset(w * 0.71, h * 0.48);
    // Shirt
    final Paint shirtPaint = Paint()..color = const Color(0xFF10B981);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(headCenter.dx, h * 0.82), width: 15, height: 12), const Radius.circular(5)),
      shirtPaint,
    );
    // Face
    final Paint facePaint = Paint()..color = const Color(0xFFFED7AA);
    canvas.drawCircle(headCenter, 6.0, facePaint);
    // Hair
    final Paint hairPaint = Paint()..color = const Color(0xFF334155);
    canvas.drawArc(Rect.fromCircle(center: Offset(headCenter.dx, headCenter.dy - 1), radius: 6.3), 3.14, 3.14, true, hairPaint);
    // Round glasses
    final Paint glassesPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(Offset(headCenter.dx - 2.2, headCenter.dy), 2.0, glassesPaint);
    canvas.drawCircle(Offset(headCenter.dx + 2.2, headCenter.dy), 2.0, glassesPaint);
    canvas.drawLine(Offset(headCenter.dx - 0.3, headCenter.dy), Offset(headCenter.dx + 0.3, headCenter.dy), glassesPaint);

    // Mini smartphone illustration on the right
    final Paint phoneBody = Paint()..color = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final RRect phone = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(w * 0.82, h * 0.50), width: 11, height: 17),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(phone, phoneBody);

    final Paint screen = Paint()..color = const Color(0xFF38BDF8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(w * 0.82, h * 0.50), width: 8, height: 12), const Radius.circular(1.5)),
      screen,
    );

    // Decorative script in Burmese ("မုန့်နှင့်အစားအစာ")
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: 'မုန့်နှင့်အစားအစာ',
        style: TextStyle(
          color: isDark ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF64748B).withValues(alpha: 0.6),
          fontSize: 7.0,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(w * 0.52, h * 0.06));

    // Left fade mask so text on the left is 100% crisp and readable
    final Rect fadeRect = Rect.fromLTWH(0, 0, w * 0.53, h);
    final Paint fadePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: <Color>[fadeColor, fadeColor.withValues(alpha: 0.85), Colors.transparent],
        stops: const <double>[0.0, 0.75, 1.0],
      ).createShader(fadeRect);
    canvas.drawRect(fadeRect, fadePaint);
  }

  @override
  bool shouldRepaint(covariant _CapsuleBannerPainter oldDelegate) => oldDelegate.fadeColor != fadeColor || oldDelegate.isDark != isDark;
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
