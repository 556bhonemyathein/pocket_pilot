import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/category.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../categories/presentation/providers/category_providers.dart';

/// One row in the transaction list.
///
/// A [ConsumerWidget] so it can resolve its own category from the shared
/// lookup map. That keeps the parent list dumb — it passes a [Transaction] and
/// nothing else — and means a category rename repaints only the affected rows.
class TransactionTile extends ConsumerWidget {
  const TransactionTile({
    required this.transaction,
    super.key,
    this.onTap,
    this.showDate = false,
  });

  final Transaction transaction;
  final VoidCallback? onTap;

  /// Set on flat lists (search results); false when the list is already
  /// grouped under date headers.
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Category category = ref.watch(
      categoryByIdProvider(transaction.categoryId),
    );

    final Color amountColor = switch (transaction.type) {
      TransactionType.income => context.finance.income,
      TransactionType.expense => context.finance.expense,
      TransactionType.transfer => context.finance.transfer,
    };

    final String prefix = switch (transaction.type) {
      TransactionType.income => '+',
      TransactionType.expense => '−',
      TransactionType.transfer => '',
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: <Widget>[
            // Hero tag ties the icon to the detail screen's header for a
            // continuous transition.
            Hero(
              tag: 'tx-icon-${transaction.id}',
              child: Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: category.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(category.icon, size: 20, color: category.color),
              ),
            ),
            AppSpacing.md.gapW,

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    transaction.note.isNotBlank
                        ? transaction.note
                        : category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.titleSmall,
                  ),
                  AppSpacing.xxs.gapH,
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          showDate
                              ? '${category.name} · ${transaction.date.relativeLabel}'
                              : category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.bodySmall?.copyWith(
                            color: context.colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (transaction.isRecurring)
                        _Badge(
                          icon: Icons.repeat_rounded,
                          color: context.colors.primary,
                        ),
                      if (transaction.hasAttachments)
                        _Badge(
                          icon: Icons.attach_file_rounded,
                          color: context.colors.onSurfaceVariant,
                        ),
                      if (transaction.syncStatus.isPending)
                        _Badge(
                          icon: Icons.cloud_upload_outlined,
                          color: context.finance.savings,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            AppSpacing.md.gapW,

            Text(
              '$prefix${transaction.amount.toCurrency(
                currencyCode: transaction.currencyCode,
              )}',
              style: context.text.titleSmall?.copyWith(
                color: amountColor,
                fontFeatures: AppTypography.tabularFigures,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small inline status marker (recurring, attachment, pending sync).
class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Icon(icon, size: 12, color: color),
    );
  }
}
