import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/date_time_extensions.dart';
import '../../../../core/utils/result.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../../shared/models/transaction_query.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/transaction_repository_impl.dart';
import '../../domain/transaction_repository.dart';

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (Ref ref) => TransactionRepositoryImpl(ref.watch(isarServiceProvider)),
  name: 'transactionRepository',
);

// ── Query state ───────────────────────────────────────────────────────────────

/// The live search/filter/sort/page state of the transactions screen.
///
/// One [Notifier] owning the whole [TransactionQuery] means "change the filter
/// and reset to page 1" is a single atomic transition — the class of bug where
/// a filter changes but the page index does not simply cannot occur.
class TransactionQueryNotifier extends Notifier<TransactionQuery> {
  Timer? _debounce;

  @override
  TransactionQuery build() {
    ref.onDispose(() => _debounce?.cancel());
    return const TransactionQuery();
  }

  /// Debounced so typing "groceries" issues one query, not nine.
  void search(String term) {
    _debounce?.cancel();
    _debounce = Timer(AppConstants.searchDebounce, () {
      state = state.copyWith(search: term).resetPage;
      if (term.trim().length >= 2) {
        unawaited(
          ref.read(preferencesServiceProvider).pushSearchTerm(term).then((_) {
            ref.invalidate(searchHistoryProvider);
          }),
        );
      }
    });
  }

  /// Bypasses the debounce — used when a search-history chip is tapped or form submitted.
  void searchNow(String term) {
    _debounce?.cancel();
    state = state.copyWith(search: term).resetPage;
    if (term.trim().length >= 2) {
      unawaited(
        ref.read(preferencesServiceProvider).pushSearchTerm(term).then((_) {
          ref.invalidate(searchHistoryProvider);
        }),
      );
    }
  }

  void toggleType(TransactionType type) {
    final Set<TransactionType> next = Set<TransactionType>.of(state.types);
    next.contains(type) ? next.remove(type) : next.add(type);
    state = state.copyWith(types: next).resetPage;
  }

  void toggleCategory(String id) {
    final Set<String> next = Set<String>.of(state.categoryIds);
    next.contains(id) ? next.remove(id) : next.add(id);
    state = state.copyWith(categoryIds: next).resetPage;
  }

  void setDateRange(DateTime? from, DateTime? to) => state = state.copyWith(from: from, to: to).resetPage;

  void setAmountRange(double? min, double? max) => state = state.copyWith(minAmount: min, maxAmount: max).resetPage;

  void setSort(TransactionSort sort) => state = state.copyWith(sort: sort).resetPage;

  /// Infinite scroll: bump the page, keep everything else.
  void loadMore() => state = state.copyWith(page: state.page + 1);

  void clearFilters() => state = TransactionQuery(search: state.search, sort: state.sort);

  void reset() => state = const TransactionQuery();
}

final transactionQueryProvider = NotifierProvider<TransactionQueryNotifier, TransactionQuery>(TransactionQueryNotifier.new, name: 'transactionQuery');

// ── Reads ─────────────────────────────────────────────────────────────────────

/// Results for an arbitrary query.
///
/// A `family` over the whole query object: because [TransactionQuery] is a
/// Freezed value type, two callers passing equal filters share one Isar
/// subscription instead of opening two.
final transactionPageProvider = StreamProvider.family<TransactionPage, TransactionQuery>(
  (Ref ref, TransactionQuery query) => ref.watch(transactionRepositoryProvider).watchPage(query),
  name: 'transactionPage',
);

/// What the transactions screen renders: the results for the *current* query.
final transactionsProvider = Provider<AsyncValue<TransactionPage>>((Ref ref) {
  final TransactionQuery query = ref.watch(transactionQueryProvider);
  return ref.watch(transactionPageProvider(query));
}, name: 'transactions');

final transactionByIdProvider = FutureProvider.family<Transaction?, String>((Ref ref, String id) async {
  final Result<Transaction?> result = await ref.watch(transactionRepositoryProvider).getById(id);
  return result.dataOrNull;
}, name: 'transactionById');

/// A named date window, so summaries can be requested declaratively.
typedef DateRange = ({DateTime from, DateTime to});

final summaryProvider = StreamProvider.family<TransactionSummary, DateRange>(
  (Ref ref, DateRange range) => ref.watch(transactionRepositoryProvider).watchSummary(from: range.from, to: range.to),
  name: 'summary',
);

/// Lifetime balance — the number on the dashboard's hero card.
final lifetimeRange = (from: DateTime(2000), to: DateTime(2100));

final currentMonthRange = Provider<DateRange>((Ref ref) {
  final DateTime now = DateTime.now();
  return (from: now.startOfMonth, to: now.endOfMonth);
}, name: 'currentMonthRange');

final recentTransactionsProvider = Provider<AsyncValue<List<Transaction>>>((Ref ref) {
  const TransactionQuery query = TransactionQuery(pageSize: 5);
  return ref.watch(transactionPageProvider(query)).whenData((TransactionPage page) => page.items);
}, name: 'recentTransactions');

/// Persisted search history, exposed for the search screen's suggestion chips.
final searchHistoryProvider = Provider<List<String>>((Ref ref) => ref.watch(preferencesServiceProvider).searchHistory, name: 'searchHistory');

// ── Writes ────────────────────────────────────────────────────────────────────

/// Commands for creating, editing, deleting and undoing transactions.
class TransactionController extends AsyncNotifier<void> {
  static const Uuid _uuid = Uuid();

  @override
  Future<void> build() async {}

  TransactionRepository get _repository => ref.read(transactionRepositoryProvider);

  /// Creates a transaction, generating the client-side id.
  ///
  /// The id is minted here rather than by the server so the row exists — and
  /// is referenceable — the instant the user taps Save, online or not.
  Future<Failure?> create({
    required TransactionType type,
    required double amount,
    required DateTime date,
    required String categoryId,
    required String currencyCode,
    String note = '',
    List<String> tags = const <String>[],
    String? receiptPath,
    RecurrenceRule recurrence = RecurrenceRule.none,
    String? transferTo,
  }) async {
    final Transaction transaction = Transaction(
      id: _uuid.v4(),
      type: type,
      amount: amount,
      date: date,
      categoryId: categoryId,
      currencyCode: currencyCode,
      note: note,
      tags: tags,
      receiptPath: receiptPath,
      recurrence: recurrence,
      transferTo: transferTo,
    );
    return _execute(() => _repository.create(transaction));
  }

  /// Named `edit` rather than `update` because `AsyncNotifier` already
  /// declares an `update` member with a different signature.
  Future<Failure?> edit(Transaction transaction) => _execute(() => _repository.update(transaction));

  Future<Failure?> delete(String id) => _execute(() => _repository.delete(id));

  /// Restores a row deleted within the undo window.
  Future<Failure?> restore(String id) => _execute(() => _repository.restore(id));

  Future<Failure?> _execute(Future<Result<Object?>> Function() action) async {
    state = const AsyncLoading<void>();
    final Result<Object?> result = await action();
    state = const AsyncData<void>(null);
    return result.failureOrNull;
  }
}

final transactionControllerProvider = AsyncNotifierProvider<TransactionController, void>(TransactionController.new, name: 'transactionController');
