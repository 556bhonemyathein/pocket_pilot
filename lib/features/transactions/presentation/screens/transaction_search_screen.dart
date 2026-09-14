import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/app_routes.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/models/transaction_query.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/transaction_repository.dart';
import '../providers/transaction_providers.dart';
import '../widgets/transaction_tile.dart';

/// Realtime search with debounce and history.
///
/// The debounce lives in [TransactionQueryNotifier] rather than here, so the
/// same behaviour applies no matter which screen drives the search — and this
/// widget stays a thin view over provider state.
class TransactionSearchScreen extends ConsumerStatefulWidget {
  const TransactionSearchScreen({super.key});

  @override
  ConsumerState<TransactionSearchScreen> createState() => _TransactionSearchScreenState();
}

class _TransactionSearchScreenState extends ConsumerState<TransactionSearchScreen> {
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(transactionQueryProvider).search;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TransactionQuery query = ref.watch(transactionQueryProvider);
    final AsyncValue<TransactionPage> results = ref.watch(transactionPageProvider(TransactionQuery(search: query.search).withoutPaging));
    final List<String> history = ref.watch(searchHistoryProvider);
    final bool hasQuery = _controller.text.trim().isNotEmpty;

    return PopScope(
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) {
          ref.read(transactionQueryProvider.notifier).searchNow('');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              ref.read(transactionQueryProvider.notifier).searchNow('');
              context.pop();
            },
          ),
          title: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (String val) {
              ref.read(transactionQueryProvider.notifier).search(val);
            },
            onSubmitted: (String val) {
              ref.read(transactionQueryProvider.notifier).searchNow(val);
            },
            decoration: InputDecoration(
              hintText: 'Search notes, categories, amounts, tags…',
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _controller.clear();
                        ref.read(transactionQueryProvider.notifier).searchNow('');
                      },
                    ),
            ),
          ),
        ),
        body: SafeArea(
          child: !hasQuery
              ? _History(
                  history: history,
                  onSelected: (String term) {
                    _controller.text = term;
                    _controller.selection = TextSelection.fromPosition(TextPosition(offset: term.length));
                    ref.read(transactionQueryProvider.notifier).searchNow(term);
                  },
                )
              : (query.search.trim().isEmpty && _controller.text.trim().isNotEmpty)
              ? const Padding(padding: EdgeInsets.all(AppSpacing.page), child: TransactionListSkeleton())
              : results.when(
                  data: (TransactionPage page) => page.items.isEmpty
                      ? AppEmptyState(
                          icon: Icons.search_off_rounded,
                          title: 'No results',
                          message:
                              'Nothing matches "${query.search.isNotBlank ? query.search : _controller.text}". '
                              'Try searching by category, amount, note, or tag.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppSpacing.page),
                          itemCount: page.items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (BuildContext context, int index) {
                            final Transaction item = page.items[index];
                            return TransactionTile(
                              transaction: item,
                              showDate: true,
                              onTap: () => context.push(
                                '${AppRoutes.transactions}/'
                                '${AppRoutes.transactionForm}',
                                extra: item,
                              ),
                            ).animate(delay: (25 * index).ms).fadeIn();
                          },
                        ),
                  loading: () => const Padding(padding: EdgeInsets.all(AppSpacing.page), child: TransactionListSkeleton()),
                  error: (Object error, _) => Center(child: Text('$error')),
                ),
        ),
      ),
    );
  }
}

/// Recently used search terms.
class _History extends ConsumerWidget {
  const _History({required this.history, required this.onSelected});

  final List<String> history;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (history.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_rounded,
        title: 'Search your transactions',
        message: 'Find anything by note, category, amount, tag, or transfer destination.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.page),
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Recent searches', style: context.text.titleSmall),
            const Spacer(),
            TextButton(
              onPressed: () async {
                await ref.read(preferencesServiceProvider).clearSearchHistory();
                ref.invalidate(searchHistoryProvider);
              },
              child: const Text('Clear'),
            ),
          ],
        ),
        AppSpacing.md.gapH,
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Column(
            children: <Widget>[
              for (final String term in history)
                ListTile(
                  leading: const Icon(Icons.history_rounded, size: 20),
                  title: Text(term),
                  trailing: const Icon(Icons.north_west_rounded, size: 16),
                  onTap: () => onSelected(term),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
