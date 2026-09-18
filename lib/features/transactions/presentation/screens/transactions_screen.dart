import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/models/transaction_query.dart';
import '../../domain/transaction_repository.dart';
import '../providers/transaction_providers.dart';
import '../widgets/filter_sheet.dart';
import '../widgets/transaction_tile.dart';

/// The full transaction list: filtered, sorted, paginated, swipe-deletable.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Infinite scroll: fetch the next page a screenful before the bottom, so
  /// the user never actually sees a loading indicator during a normal scroll.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final double remaining = _scrollController.position.maxScrollExtent - _scrollController.position.pixels;
    if (remaining > 400) return;

    final AsyncValue<TransactionPage> page = ref.read(transactionsProvider);
    if (page.isLoading) return;
    if (page.value?.hasMore ?? false) {
      ref.read(transactionQueryProvider.notifier).loadMore();
    }
  }

  Future<void> _delete(Transaction transaction) async {
    final Failure? failure = await ref.read(transactionControllerProvider.notifier).delete(transaction.id);

    if (!mounted) return;
    if (failure != null) {
      AppFeedback.error(context, failure);
      return;
    }

    // Optimistic delete + undo: the row is already gone from the list, and the
    // snackbar is the user's escape hatch for the next few seconds.
    AppFeedback.undo(
      context,
      message: 'transaction_deleted'.tr(),
      onUndo: () async {
        final Failure? restoreFailure = await ref.read(transactionControllerProvider.notifier).restore(transaction.id);
        if (restoreFailure != null && mounted) {
          AppFeedback.error(context, restoreFailure);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final TransactionQuery query = ref.watch(transactionQueryProvider);
    final AsyncValue<TransactionPage> page = ref.watch(transactionsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(transactionPageProvider),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverAppBar(
              floating: true,
              snap: true,
              titleSpacing: AppSpacing.page,
              title: Text('activity'.tr()),
              actions: <Widget>[
                IconButton(tooltip: 'search'.tr(), onPressed: () => context.goNamed(AppRoutes.search), icon: const Icon(Icons.search_rounded)),
                _SortButton(current: query.sort),
                _FilterButton(count: query.activeFilterCount),
                AppSpacing.sm.gapW,
              ],
            ),

            if (query.hasFilters || query.search.isNotBlank)
              SliverToBoxAdapter(
                child: _ActiveFilterBar(query: query, resultCount: page.value?.total ?? 0),
              ),

            ...page.when(
              data: _buildList,
              loading: () => <Widget>[
                const SliverPadding(
                  padding: EdgeInsets.all(AppSpacing.page),
                  sliver: SliverToBoxAdapter(child: TransactionListSkeleton(itemCount: 8)),
                ),
              ],
              error: (Object error, _) => <Widget>[
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: AppErrorState(failure: FailureMapper.from(error), onRetry: () => ref.invalidate(transactionPageProvider)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildList(TransactionPage data) {
    if (data.items.isEmpty) {
      final bool filtered = ref.read(transactionQueryProvider).hasFilters || ref.read(transactionQueryProvider).search.isNotBlank;

      return <Widget>[
        SliverFillRemaining(
          hasScrollBody: false,
          child: AppEmptyState(
            icon: filtered ? Icons.filter_alt_off_outlined : Icons.receipt_long_outlined,
            title: filtered ? 'no_matches'.tr() : 'nothing_here_yet'.tr(),
            message: filtered ? 'try_widening_your_filters_or_clearing_the_search'.tr() : 'add_your_first_transaction_to_get_started'.tr(),
            actionLabel: filtered ? 'clear_filters'.tr() : 'add_transaction'.tr(),
            onAction: filtered
                ? () => ref.read(transactionQueryProvider.notifier).reset()
                : () => context.go(
                    '${AppRoutes.transactions}/${AppRoutes.transactionForm}',
                  ),
          ),
        ),
      ];
    }

    // Group by calendar day so the list reads as a diary rather than a dump.
    final Map<DateTime, List<Transaction>> grouped = groupBy<Transaction, DateTime>(data.items, (Transaction t) => t.date.dateOnly);
    final List<DateTime> days = grouped.keys.toList()..sort((DateTime a, DateTime b) => b.compareTo(a));

    return <Widget>[
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.sm, AppSpacing.page, 120),
        sliver: SliverList.builder(
          itemCount: days.length + (data.hasMore ? 1 : 0),
          itemBuilder: (BuildContext context, int index) {
            if (index >= days.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.4))),
              );
            }

            final DateTime day = days[index];
            final List<Transaction> items = grouped[day]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.lg, AppSpacing.sm, AppSpacing.sm),
                  child: Row(
                    children: <Widget>[
                      Text(day.relativeLabel, style: context.text.labelLarge?.copyWith(color: context.colors.onSurfaceVariant)),
                      const Spacer(),
                      Text(_dayTotal(items), style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                    ],
                  ),
                ),
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < items.length; i++) ...<Widget>[
                        if (i > 0) const Divider(height: 1),
                        _SwipeableTile(transaction: items[i], onDelete: () => _delete(items[i])),
                      ],
                    ],
                  ),
                ),
              ],
            ).animate(delay: (30 * index).ms).fadeIn(duration: 250.ms);
          },
        ),
      ),
    ];
  }

  String _dayTotal(List<Transaction> items) {
    final double net = items.fold<double>(0, (double sum, Transaction t) => sum + t.signedAmount);
    return net.toSignedCurrency(currencyCode: items.first.currencyCode);
  }
}

/// Swipe-to-delete wrapper with a confirmation threshold.
class _SwipeableTile extends StatelessWidget {
  const _SwipeableTile({required this.transaction, required this.onDelete});

  final Transaction transaction;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey<String>(transaction.id),
      direction: DismissDirection.endToStart,
      // A generous threshold prevents accidental deletes during a fast scroll.
      dismissThresholds: const <DismissDirection, double>{DismissDirection.endToStart: 0.45},
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.xl),
        decoration: BoxDecoration(color: context.colors.errorContainer, borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Icon(Icons.delete_outline_rounded, color: context.colors.onErrorContainer),
      ),
      child: TransactionTile(
        transaction: transaction,
        onTap: () => context.go('${AppRoutes.transactions}/${AppRoutes.transactionForm}', extra: transaction),
      ),
    );
  }
}

class _SortButton extends ConsumerWidget {
  const _SortButton({required this.current});

  final TransactionSort current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<TransactionSort>(
      tooltip: 'sort'.tr(),
      icon: const Icon(Icons.swap_vert_rounded),
      initialValue: current,
      onSelected: (TransactionSort sort) => ref.read(transactionQueryProvider.notifier).setSort(sort),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<TransactionSort>>[
        for (final TransactionSort sort in TransactionSort.values) PopupMenuItem<TransactionSort>(value: sort, child: Text(sort.label)),
      ],
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'filter'.tr(),
      onPressed: () => AppFeedback.sheet<void>(context, child: const TransactionFilterSheet()),
      icon: Badge(isLabelVisible: count > 0, label: Text('$count'), child: const Icon(Icons.tune_rounded)),
    );
  }
}

/// Summary strip shown while filters are active.
class _ActiveFilterBar extends ConsumerWidget {
  const _ActiveFilterBar({required this.query, required this.resultCount});

  final TransactionQuery query;
  final int resultCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String results = 'results_count'.plural(resultCount);
    final String label = query.search.isNotBlank ? 'search_results_label'.tr(namedArgs: <String, String>{'search': query.search, 'results': results}) : results;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              ref.read(transactionQueryProvider.notifier).clearFilters();
              ref.read(transactionQueryProvider.notifier).searchNow('');
            },
            icon: const Icon(Icons.close_rounded, size: 16),
            label: Text('clear_all'.tr()),
          ),
        ],
      ),
    );
  }
}
