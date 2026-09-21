import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shimmer/shimmer.dart';

import '../errors/failure.dart';
import '../extensions/extensions.dart';
import '../theme/app_dimens.dart';
import 'app_button.dart';

/// Skeleton placeholder.
///
/// Skeletons beat spinners for list content: they preserve layout, so the page
/// does not jump when data lands, and they communicate *shape* while loading.
class AppShimmer extends StatelessWidget {
  const AppShimmer({
    required this.child,
    super.key,
  });

  /// A single grey block — the building material for bespoke skeletons.
  AppShimmer.box({
    required double height,
    double width = double.infinity,
    double radius = AppRadius.sm,
    super.key,
  }) : child = _ShimmerBox(height: height, width: width, radius: radius);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.05),
      highlightColor: context.isDark
          ? Colors.white.withValues(alpha: 0.14)
          : Colors.black.withValues(alpha: 0.02),
      child: child,
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.height,
    required this.width,
    required this.radius,
  });

  final double height;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Skeleton matching the transaction tile's layout.
class TransactionListSkeleton extends StatelessWidget {
  const TransactionListSkeleton({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Column(
        children: List<Widget>.generate(
          itemCount,
          (_) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: <Widget>[
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: SizedBox(height: 44, width: 44),
                ),
                AppSpacing.md.gapW,
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _ShimmerBox(height: 12, width: 140, radius: 6),
                      SizedBox(height: 8),
                      _ShimmerBox(height: 10, width: 80, radius: 6),
                    ],
                  ),
                ),
                const _ShimmerBox(height: 14, width: 64, radius: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown when a query legitimately returned nothing.
///
/// Distinguishing "empty" from "error" matters: an empty state invites an
/// action, an error state offers a retry. Conflating them is how apps end up
/// telling users something broke when nothing did.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.title,
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 88,
              width: 88,
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: context.colors.primary),
            ),
            AppSpacing.xl.gapH,
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            if (message != null) ...<Widget>[
              AppSpacing.sm.gapH,
              Text(
                message!,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...<Widget>[
              AppSpacing.xl.gapH,
              AppButton(
                label: actionLabel!,
                onPressed: onAction,
                expanded: false,
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.08),
    );
  }
}

/// Shown when something actually failed.
///
/// Renders the [Failure]'s user-facing message and offers Retry only when the
/// failure is retryable — a validation error will not fix itself, so offering
/// the button would be a lie.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    required this.failure,
    super.key,
    this.onRetry,
    this.compact = false,
  });

  final Failure failure;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final IconData icon = switch (failure) {
      NetworkFailure() => Icons.wifi_off_rounded,
      TimeoutFailure() => Icons.timer_off_outlined,
      UnauthorizedFailure() => Icons.lock_outline_rounded,
      NotFoundFailure() => Icons.search_off_rounded,
      _ => Icons.error_outline_rounded,
    };

    if (compact) {
      return Row(
        children: <Widget>[
          Icon(icon, size: 18, color: context.colors.error),
          AppSpacing.sm.gapW,
          Expanded(
            child: Text(
              failure.message,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
          ),
          if (onRetry != null && failure.isRetryable)
            TextButton(onPressed: onRetry, child: Text('retry'.tr())),
        ],
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              height: 88,
              width: 88,
              decoration: BoxDecoration(
                color: context.colors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: context.colors.error),
            ),
            AppSpacing.xl.gapH,
            Text(
              'something_went_wrong'.tr(),
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
            AppSpacing.sm.gapH,
            Text(
              failure.message,
              textAlign: TextAlign.center,
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (onRetry != null && failure.isRetryable) ...<Widget>[
              AppSpacing.xl.gapH,
              AppButton(
                label: 'try_again'.tr(),
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
                expanded: false,
              ),
            ],
          ],
        ),
      ).animate().fadeIn(duration: 300.ms),
    );
  }
}
