import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/enums.dart';

/// The dashboard hero: current balance on a gradient.
///
/// The amount animates from the previous value rather than snapping, so a
/// refresh reads as a change rather than a repaint.
class BalanceCard extends StatelessWidget {
  const BalanceCard({required this.balance, required this.currencyCode, required this.income, required this.expense, super.key});

  final double balance;
  final String currencyCode;
  final double income;
  final double expense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        gradient: LinearGradient(colors: context.finance.balanceGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: <BoxShadow>[
          BoxShadow(color: context.finance.balanceGradient.first.withValues(alpha: 0.28), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('current_balance'.tr(), style: context.text.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
              const Spacer(),
              Icon(Icons.account_balance_wallet_outlined, size: 18, color: Colors.white.withValues(alpha: 0.75)),
            ],
          ),
          AppSpacing.sm.gapH,

          TweenAnimationBuilder<double>(
            duration: 700.ms,
            curve: Curves.easeOutCubic,
            tween: Tween<double>(begin: 0, end: balance),
            builder: (BuildContext context, double value, _) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value.toCurrency(currencyCode: currencyCode),
                style: context.text.displayMedium?.copyWith(color: Colors.white, fontFeatures: AppTypography.tabularFigures),
              ),
            ),
          ),
          AppSpacing.xl.gapH,

          Row(
            children: <Widget>[
              _MiniStat(
                label: 'income'.tr(),
                value: income.toCompactCurrency(currencyCode: currencyCode),
                icon: Icons.south_west_rounded,
                onTap: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}', extra: TransactionType.income),
              ),
              AppSpacing.xxl.gapW,
              _MiniStat(
                label: 'spent'.tr(),
                value: expense.toCompactCurrency(currencyCode: currencyCode),
                icon: Icons.north_east_rounded,
                onTap: () => context.go('${AppRoutes.dashboard}/${AppRoutes.transactionForm}', extra: TransactionType.expense),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.08, curve: Curves.easeOutCubic);
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.icon, this.onTap});

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.all(AppSpacing.xs),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.xs)),
          child: Icon(icon, size: 14, color: Colors.white),
        ),
        AppSpacing.sm.gapW,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label, style: context.text.labelSmall?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
            Text(value, style: context.text.titleSmall?.copyWith(color: Colors.white)),
          ],
        ),
      ],
    );

    if (onTap != null) {
      return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: content);
    }
    return content;
  }
}
