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
import '../../../../shared/models/category.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../categories/data/default_categories.dart';
import '../../../categories/presentation/providers/category_providers.dart';
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
            pinned: true,
            floating: false,
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
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
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

/// Stadium / capsule search bar with neon border, dynamic category names, and matching illustrations.
class _CapsuleSearchBar extends ConsumerStatefulWidget {
  const _CapsuleSearchBar();

  @override
  ConsumerState<_CapsuleSearchBar> createState() => _CapsuleSearchBarState();
}

class _CapsuleSearchBarState extends ConsumerState<_CapsuleSearchBar> {
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 3500), (_) {
      if (mounted) {
        setState(() {
          _index++;
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

    final List<Category> allCategories = ref.watch(categoriesProvider).value ?? DefaultCategories.build();
    final List<Category> expenseCategories = allCategories.where((Category c) => c.kind != CategoryKind.income).toList();
    final List<Category> displayList = expenseCategories.isNotEmpty ? expenseCategories : allCategories;
    final Category currentCategory = displayList.isNotEmpty ? displayList[_index % displayList.length] : Category.unknown;

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
              // Category-themed subtle gradient wash across the capsule
              AnimatedSwitcher(
                duration: 350.ms,
                child: SizedBox.expand(
                  key: ValueKey<String>('bg_${currentCategory.id}'),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: <Color>[
                          Colors.transparent,
                          currentCategory.color.withValues(alpha: isDark ? 0.22 : 0.09),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Content row: Category Name on left, Single Category Artwork on right (only 1 icon in search box)
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
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
                          currentCategory.name,
                          key: ValueKey<String>(currentCategory.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Exactly ONE icon/image in the search box — the belonging category artwork
                    AnimatedSwitcher(
                      duration: 300.ms,
                      child: SizedBox(
                        key: ValueKey<String>('art_${currentCategory.id}'),
                        width: 30,
                        height: 30,
                        child: CustomPaint(
                          painter: _CategoryArtworkPainter(category: currentCategory, isDark: isDark),
                        ),
                      ),
                    ),
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

/// Illustrates artwork belonging specifically to the active category in the capsule search bar.
class _CategoryArtworkPainter extends CustomPainter {
  const _CategoryArtworkPainter({required this.category, required this.isDark});

  final Category category;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    final String name = category.name.toLowerCase();
    final Color catColor = category.color;

    // Draw artwork corresponding to category
    if (name.contains('food') ||
        name.contains('drink') ||
        name.contains('restaurant') ||
        name.contains('dining') ||
        name.contains('cafe') ||
        name.contains('မုန့်') ||
        name.contains('အစား')) {
      _drawFoodIllustration(canvas, cx, cy);
    } else if (name.contains('grocer') || name.contains('market') || name.contains('ကုန်စုံ') || name.contains('စျေး')) {
      _drawGroceriesIllustration(canvas, cx, cy);
    } else if (name.contains('shop') || name.contains('cloth') || name.contains('gift') || name.contains('ဝယ်')) {
      _drawShoppingIllustration(canvas, cx, cy);
    } else if (name.contains('transport') ||
        name.contains('car') ||
        name.contains('fuel') ||
        name.contains('transit') ||
        name.contains('bus') ||
        name.contains('ကား') ||
        name.contains('ယာဉ်')) {
      _drawTransportIllustration(canvas, cx, cy);
    } else if (name.contains('house') || name.contains('home') || name.contains('rent') || name.contains('အိမ်')) {
      _drawHousingIllustration(canvas, cx, cy);
    } else if (name.contains('bill') ||
        name.contains('utilit') ||
        name.contains('power') ||
        name.contains('electric') ||
        name.contains('water') ||
        name.contains('ဘေလ်') ||
        name.contains('မီး')) {
      _drawBillsIllustration(canvas, cx, cy);
    } else if (name.contains('entertain') ||
        name.contains('movie') ||
        name.contains('cinema') ||
        name.contains('game') ||
        name.contains('ရုပ်ရှင်') ||
        name.contains('ကစား')) {
      _drawEntertainmentIllustration(canvas, cx, cy);
    } else if (name.contains('health') ||
        name.contains('medic') ||
        name.contains('doctor') ||
        name.contains('pharm') ||
        name.contains('ဆေး') ||
        name.contains('ကျန်းမာ')) {
      _drawHealthIllustration(canvas, cx, cy);
    } else if (name.contains('educat') ||
        name.contains('school') ||
        name.contains('course') ||
        name.contains('book') ||
        name.contains('study') ||
        name.contains('ကျောင်း') ||
        name.contains('ပညာ')) {
      _drawEducationIllustration(canvas, cx, cy);
    } else if (name.contains('travel') || name.contains('flight') || name.contains('trip') || name.contains('hotel') || name.contains('ခရီး')) {
      _drawTravelIllustration(canvas, cx, cy);
    } else if (name.contains('salar') ||
        name.contains('saving') ||
        name.contains('invest') ||
        name.contains('income') ||
        name.contains('bonus') ||
        name.contains('လစာ') ||
        name.contains('စုငွေ')) {
      _drawSavingsIllustration(canvas, cx, cy);
    } else {
      _drawGeneralIllustration(canvas, cx, cy, catColor);
    }
  }

  void _drawFoodIllustration(Canvas canvas, double cx, double cy) {
    // Single Burger
    final Paint bunPaint = Paint()..color = const Color(0xFFF59E0B);
    final Path topBun = Path()
      ..moveTo(cx - 9, cy - 1)
      ..quadraticBezierTo(cx, cy - 9, cx + 9, cy - 1)
      ..close();
    canvas.drawPath(topBun, bunPaint);
    final Paint seedPaint = Paint()..color = const Color(0xFFFEF3C7);
    canvas.drawCircle(Offset(cx - 4, cy - 4), 0.9, seedPaint);
    canvas.drawCircle(Offset(cx + 3, cy - 5), 0.9, seedPaint);
    canvas.drawCircle(Offset(cx, cy - 3), 0.9, seedPaint);
    final Paint lettucePaint = Paint()..color = const Color(0xFF10B981);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 0.8), width: 19, height: 2.2), const Radius.circular(1)),
      lettucePaint,
    );
    final Paint cheesePaint = Paint()..color = const Color(0xFFFACC15);
    final Path cheese = Path()
      ..moveTo(cx - 8, cy + 2)
      ..lineTo(cx + 8, cy + 2)
      ..lineTo(cx + 3, cy + 4.5)
      ..lineTo(cx - 3, cy + 2)
      ..close();
    canvas.drawPath(cheese, cheesePaint);
    final Paint pattyPaint = Paint()..color = const Color(0xFF78350F);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 4.2), width: 18, height: 3.2), const Radius.circular(1.5)),
      pattyPaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 7.5), width: 17, height: 3), const Radius.circular(1.5)),
      bunPaint,
    );
  }

  void _drawGroceriesIllustration(Canvas canvas, double cx, double cy) {
    // Single Grocery paper bag with greens
    final Paint bagPaint = Paint()..color = const Color(0xFFD97706);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 2.5), width: 16, height: 14), const Radius.circular(2)),
      bagPaint,
    );
    final Paint foldPaint = Paint()..color = const Color(0xFFB45309);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy - 4.5), width: 16, height: 2), foldPaint);
    final Path carrot = Path()
      ..moveTo(cx - 4, cy - 4.5)
      ..lineTo(cx - 1, cy - 10)
      ..lineTo(cx + 1, cy - 4.5)
      ..close();
    final Paint carrotPaint = Paint()..color = const Color(0xFFEA580C);
    canvas.drawPath(carrot, carrotPaint);
    final Paint leafPaint = Paint()..color = const Color(0xFF22C55E);
    canvas.drawCircle(Offset(cx - 1, cy - 11), 1.6, leafPaint);
    canvas.drawCircle(Offset(cx + 3.5, cy - 7), 2.2, leafPaint);
  }

  void _drawShoppingIllustration(Canvas canvas, double cx, double cy) {
    // Single Shopping Bag
    final Paint bagPaint = Paint()..color = const Color(0xFFEC4899);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 2.5), width: 17, height: 15), const Radius.circular(3)),
      bagPaint,
    );
    final Paint handlePaint = Paint()
      ..color = const Color(0xFFFCE7F3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawArc(Rect.fromCenter(center: Offset(cx, cy - 4.5), width: 9, height: 9), 3.14, 3.14, false, handlePaint);
    final Paint emblemPaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(Offset(cx, cy + 2.5), 2.5, emblemPaint);
  }

  void _drawTransportIllustration(Canvas canvas, double cx, double cy) {
    // Single Car
    final Paint carPaint = Paint()..color = const Color(0xFF3B82F6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 2), width: 22, height: 8.5), const Radius.circular(3)),
      carPaint,
    );
    final Paint roofPaint = Paint()..color = const Color(0xFF1D4ED8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx - 1, cy - 2.5), width: 13, height: 5.5), const Radius.circular(2)),
      roofPaint,
    );
    final Paint windowPaint = Paint()..color = const Color(0xFF93C5FD);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx - 1, cy - 2.5), width: 10, height: 3.5), const Radius.circular(1)),
      windowPaint,
    );
    final Paint wheelPaint = Paint()..color = const Color(0xFF1E293B);
    final Paint hubPaint = Paint()..color = const Color(0xFFCBD5E1);
    canvas.drawCircle(Offset(cx - 6, cy + 6), 3.2, wheelPaint);
    canvas.drawCircle(Offset(cx - 6, cy + 6), 1.2, hubPaint);
    canvas.drawCircle(Offset(cx + 6, cy + 6), 3.2, wheelPaint);
    canvas.drawCircle(Offset(cx + 6, cy + 6), 1.2, hubPaint);
  }

  void _drawHousingIllustration(Canvas canvas, double cx, double cy) {
    // Single House
    final Paint wallPaint = Paint()..color = const Color(0xFF8B5CF6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 2.5), width: 16, height: 12), const Radius.circular(2)),
      wallPaint,
    );
    final Path roof = Path()
      ..moveTo(cx - 10, cy - 2.5)
      ..lineTo(cx, cy - 10)
      ..lineTo(cx + 10, cy - 2.5)
      ..close();
    final Paint roofPaint = Paint()..color = const Color(0xFF6D28D9);
    canvas.drawPath(roof, roofPaint);
    final Paint doorPaint = Paint()..color = const Color(0xFFFBBF24);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy + 5), width: 5, height: 7), const Radius.circular(1)), doorPaint);
    final Paint chimneyPaint = Paint()..color = const Color(0xFF4C1D95);
    canvas.drawRect(Rect.fromLTWH(cx + 4, cy - 8.5, 3.2, 4.5), chimneyPaint);
  }

  void _drawBillsIllustration(Canvas canvas, double cx, double cy) {
    // Single Receipt sheet
    final Paint billBg = Paint()..color = const Color(0xFFF8FAFC);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: 16, height: 20), const Radius.circular(2.5)), billBg);
    final Paint badgePaint = Paint()..color = const Color(0xFF0EA5E9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy - 6), width: 10, height: 3), const Radius.circular(1)),
      badgePaint,
    );
    final Paint linePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cx - 5, cy - 2), Offset(cx + 5, cy - 2), linePaint);
    canvas.drawLine(Offset(cx - 5, cy + 1.5), Offset(cx + 5, cy + 1.5), linePaint);
    canvas.drawLine(Offset(cx - 5, cy + 5), Offset(cx + 2, cy + 5), linePaint);
  }

  void _drawEntertainmentIllustration(Canvas canvas, double cx, double cy) {
    // Single Popcorn Tub: red tub with golden fluffy popcorn on top
    final Paint popPaint = Paint()..color = const Color(0xFFFDE047);
    canvas.drawCircle(Offset(cx - 4.5, cy - 4.5), 3.5, popPaint);
    canvas.drawCircle(Offset(cx + 4.5, cy - 4.5), 3.5, popPaint);
    canvas.drawCircle(Offset(cx, cy - 6.5), 4.0, popPaint);

    final Path tub = Path()
      ..moveTo(cx - 7, cy - 2)
      ..lineTo(cx + 7, cy - 2)
      ..lineTo(cx + 5.5, cy + 9)
      ..lineTo(cx - 5.5, cy + 9)
      ..close();
    final Paint tubPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawPath(tub, tubPaint);

    final Path stripe = Path()
      ..moveTo(cx - 2, cy - 2)
      ..lineTo(cx + 2, cy - 2)
      ..lineTo(cx + 1.5, cy + 9)
      ..lineTo(cx - 1.5, cy + 9)
      ..close();
    final Paint stripePaint = Paint()..color = Colors.white;
    canvas.drawPath(stripe, stripePaint);
  }

  void _drawHealthIllustration(Canvas canvas, double cx, double cy) {
    // Single First-Aid Cross Box
    final Paint boxPaint = Paint()..color = const Color(0xFFEF4444);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: 19, height: 16), const Radius.circular(3.5)), boxPaint);
    final Paint crossPaint = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 9, height: 3), crossPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: 3, height: 9), crossPaint);
  }

  void _drawEducationIllustration(Canvas canvas, double cx, double cy) {
    // Single Graduation Cap
    final Path cap = Path()
      ..moveTo(cx, cy - 6.5)
      ..lineTo(cx + 10, cy - 2)
      ..lineTo(cx, cy + 2.5)
      ..lineTo(cx - 10, cy - 2)
      ..close();
    final Paint capPaint = Paint()..color = const Color(0xFF4F46E5);
    canvas.drawPath(cap, capPaint);
    final Path skull = Path()
      ..moveTo(cx - 6, cy)
      ..quadraticBezierTo(cx, cy + 7, cx + 6, cy)
      ..close();
    final Paint skullPaint = Paint()..color = const Color(0xFF3730A3);
    canvas.drawPath(skull, skullPaint);
    final Paint tasselPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, cy - 2), Offset(cx + 9, cy + 3.5), tasselPaint);
    final Paint tasselEnd = Paint()..color = const Color(0xFFF59E0B);
    canvas.drawCircle(Offset(cx + 9, cy + 4.5), 1.3, tasselEnd);
  }

  void _drawTravelIllustration(Canvas canvas, double cx, double cy) {
    // Single Airplane angled upwards
    final Path plane = Path()
      ..moveTo(cx + 8, cy - 8)
      ..lineTo(cx + 10, cy - 7)
      ..lineTo(cx + 3, cy + 6)
      ..lineTo(cx - 4, cy + 4)
      ..lineTo(cx - 8, cy + 8)
      ..lineTo(cx - 6, cy + 2)
      ..lineTo(cx - 10, cy - 2)
      ..lineTo(cx - 6, cy - 2)
      ..close();
    final Paint planePaint = Paint()..color = const Color(0xFF0284C7);
    canvas.drawPath(plane, planePaint);
  }

  void _drawSavingsIllustration(Canvas canvas, double cx, double cy) {
    // Single Large Gold Coin
    final Paint goldDark = Paint()..color = const Color(0xFFD97706);
    final Paint goldBase = Paint()..color = const Color(0xFFF59E0B);
    final Paint goldShine = Paint()..color = const Color(0xFFFDE047);

    canvas.drawCircle(Offset(cx, cy), 9.0, goldDark);
    canvas.drawCircle(Offset(cx, cy), 8.0, goldBase);
    canvas.drawCircle(Offset(cx, cy), 6.5, goldDark);
    canvas.drawCircle(Offset(cx, cy), 5.5, goldShine);

    final Paint starPaint = Paint()..color = const Color(0xFF78350F);
    final Path star = Path()
      ..moveTo(cx, cy - 3.5)
      ..lineTo(cx + 1, cy - 1)
      ..lineTo(cx + 3.5, cy)
      ..lineTo(cx + 1, cy + 1)
      ..lineTo(cx, cy + 3.5)
      ..lineTo(cx - 1, cy + 1)
      ..lineTo(cx - 3.5, cy)
      ..lineTo(cx - 1, cy - 1)
      ..close();
    canvas.drawPath(star, starPaint);
  }

  void _drawGeneralIllustration(Canvas canvas, double cx, double cy, Color catColor) {
    // Single Payment Card
    final Paint cardBg = Paint()..color = catColor.withValues(alpha: isDark ? 0.9 : 0.85);
    final RRect card = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, cy), width: 19, height: 13), const Radius.circular(2.5));
    canvas.drawRRect(card, cardBg);
    final Paint chipPaint = Paint()..color = const Color(0xFFFDE047);
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 6.5, cy - 2.5, 4.5, 3.5), const Radius.circular(0.8)), chipPaint);
    final Paint linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cx - 6.5, cy + 2.8), Offset(cx + 6.5, cy + 2.8), linePaint);
  }

  @override
  bool shouldRepaint(covariant _CategoryArtworkPainter oldDelegate) => oldDelegate.category != category || oldDelegate.isDark != isDark;
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
              onTap: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}', extra: actions[i].type),
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
              onTap: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}', extra: TransactionType.income),
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
              onTap: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}', extra: TransactionType.expense),
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
