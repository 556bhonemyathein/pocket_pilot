import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/glass_panel.dart';

/// Income / expense / savings tile.
class StatCard extends StatelessWidget {
  const StatCard({
    required this.label,
    required this.amount,
    required this.currencyCode,
    required this.color,
    required this.icon,
    super.key,
    this.caption,
    this.onTap,
  });

  final String label;
  final double amount;
  final String currencyCode;
  final Color color;
  final IconData icon;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          AppSpacing.md.gapH,
          Text(
            label,
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          AppSpacing.xxs.gapH,
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount.toCurrency(currencyCode: currencyCode),
              style: context.text.titleMedium?.copyWith(
                color: color,
                fontFeatures: AppTypography.tabularFigures,
              ),
            ),
          ),
          if (caption != null) ...<Widget>[
            AppSpacing.xxs.gapH,
            Text(
              caption!,
              style: context.text.labelSmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Monthly budget progress.
///
/// Turns amber at 80% and red past 100% — the colour *is* the warning, so the
/// user gets the signal without reading a number.
class BudgetProgressCard extends StatelessWidget {
  const BudgetProgressCard({
    required this.spent,
    required this.budget,
    required this.currencyCode,
    super.key,
    this.onTap,
  });

  final double spent;
  final double budget;
  final String currencyCode;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double ratio = budget <= 0 ? 0 : (spent / budget);
    final double clamped = ratio.clamp(0.0, 1.0);
    final double remaining = budget - spent;

    final Color color = switch (ratio) {
      >= 1 => context.finance.expense,
      >= 0.8 => context.finance.savings,
      _ => context.finance.income,
    };

    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('monthly_budget'.tr(), style: context.text.titleSmall),
              const Spacer(),
              Text(
                ratio.toPercent(),
                style: context.text.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
          AppSpacing.md.gapH,

          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: TweenAnimationBuilder<double>(
              duration: 800.ms,
              curve: Curves.easeOutCubic,
              tween: Tween<double>(begin: 0, end: clamped),
              builder: (BuildContext context, double value, _) =>
                  LinearProgressIndicator(
                    value: value,
                    minHeight: 10,
                    color: color,
                    backgroundColor: context.colors.outlineVariant,
                  ),
            ),
          ),
          AppSpacing.md.gapH,

          Text(
            remaining >= 0
                ? '${remaining.toCurrency(currencyCode: currencyCode)} left of ${budget.toCurrency(currencyCode: currencyCode)}'
                : '${remaining.abs().toCurrency(currencyCode: currencyCode)} over budget',
            style: context.text.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
