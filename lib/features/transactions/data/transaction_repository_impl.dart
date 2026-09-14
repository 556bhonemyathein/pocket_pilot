import 'package:isar_community/isar.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/extensions/date_time_extensions.dart';
import '../../../core/storage/entities/category_entity.dart';
import '../../../core/storage/entities/transaction_entity.dart';
import '../../../core/storage/isar_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/utils/result.dart';
import '../../../shared/models/enums.dart';
import '../../../shared/models/transaction.dart';
import '../../../shared/models/transaction_query.dart';
import '../domain/transaction_repository.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._isar);

  final IsarService _isar;

  // ── Reads ───────────────────────────────────────────────────────────────────

  @override
  Stream<TransactionPage> watchPage(TransactionQuery query) async* {
    yield await _queryPage(query);
    await for (final void _ in _isar.transactions.watchLazy()) {
      yield await _queryPage(query);
    }
  }

  @override
  Future<Result<TransactionPage>> getPage(TransactionQuery query) => guard(() => _queryPage(query));

  Future<TransactionPage> _queryPage(TransactionQuery query) async {
    List<Transaction> matches = await _matching(query);
    final int total = matches.length;

    matches = _sorted(matches, query.sort);

    final int start = query.page * query.pageSize;
    if (start >= total) {
      return TransactionPage(items: const <Transaction>[], total: total, page: query.page, hasMore: false);
    }
    final int end = (start + query.pageSize).clamp(0, total);

    return TransactionPage(
      // Pagination is cumulative: page 2 returns rows 0..n so the list widget
      // can render one flat, scroll-stable list.
      items: matches.sublist(0, end),
      total: total,
      page: query.page,
      hasMore: end < total,
    );
  }

  /// Applies indexed filters in Isar, then the free-text pass in Dart.
  Future<List<Transaction>> _matching(TransactionQuery query) async {
    QueryBuilder<TransactionEntity, TransactionEntity, QAfterFilterCondition> builder = _isar.transactions.filter().isDeletedEqualTo(false);

    if (query.from != null) {
      builder = builder.and().dateGreaterThan(query.from!.startOfDay, include: true);
    }
    if (query.to != null) {
      builder = builder.and().dateLessThan(query.to!.endOfDay, include: true);
    }
    if (query.minAmount != null) {
      builder = builder.and().amountGreaterThan(query.minAmount!, include: true);
    }
    if (query.maxAmount != null) {
      builder = builder.and().amountLessThan(query.maxAmount!, include: true);
    }
    if (query.types.isNotEmpty) {
      builder = builder.and().anyOf<TransactionType, QAfterFilterCondition>(query.types, (q, TransactionType type) => q.typeEqualTo(type));
    }
    if (query.categoryIds.isNotEmpty) {
      builder = builder.and().anyOf<String, QAfterFilterCondition>(query.categoryIds, (q, String id) => q.categoryIdEqualTo(id));
    }

    final List<TransactionEntity> rows = await builder.findAll();
    final Iterable<Transaction> domain = rows.map((TransactionEntity e) => e.toDomain());

    final String search = query.search.trim().toLowerCase();
    if (search.isEmpty) return domain.toList();

    final List<CategoryEntity> catEntities = await _isar.categories.where().findAll();
    final Map<String, String> categoryNames = <String, String>{for (final CategoryEntity c in catEntities) c.uid: c.name.toLowerCase()};

    final String cleanSearch = search.replaceAll(RegExp(r'[\$,€,£,¥,₹]'), '').trim();
    final List<String> searchTokens = (cleanSearch.isNotEmpty ? cleanSearch : search)
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList();

    const List<String> monthNames = <String>[
      '',
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december',
    ];

    const List<String> shortMonthNames = <String>['', 'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

    return domain.where((Transaction t) {
      final String catName = categoryNames[t.categoryId] ?? '';
      final String amountStr = t.amount.toString();
      final String amountFixed = t.amount.toStringAsFixed(2);
      final String typeStr = t.type.name.toLowerCase();
      final String monthName = (t.date.month >= 1 && t.date.month <= 12) ? monthNames[t.date.month] : '';
      final String shortMonth = (t.date.month >= 1 && t.date.month <= 12) ? shortMonthNames[t.date.month] : '';
      final String yearStr = t.date.year.toString();

      final String fullHaystack = '${t.searchHaystack} $catName $amountStr $amountFixed $typeStr $monthName $shortMonth $yearStr'.toLowerCase();

      return searchTokens.every(fullHaystack.contains);
    }).toList();
  }

  List<Transaction> _sorted(List<Transaction> items, TransactionSort sort) {
    final List<Transaction> copy = List<Transaction>.of(items);
    copy.sort(
      (Transaction a, Transaction b) => switch (sort) {
        TransactionSort.dateDesc => b.date.compareTo(a.date),
        TransactionSort.dateAsc => a.date.compareTo(b.date),
        TransactionSort.amountDesc => b.amount.compareTo(a.amount),
        TransactionSort.amountAsc => a.amount.compareTo(b.amount),
      },
    );
    return copy;
  }

  @override
  Future<Result<Transaction?>> getById(String id) => guard(() async {
    final TransactionEntity? row = await _isar.transactions.filter().uidEqualTo(id).findFirst();
    return row?.toDomain();
  });

  @override
  Stream<TransactionSummary> watchSummary({required DateTime from, required DateTime to}) async* {
    Future<TransactionSummary> read() => _summary(from: from, to: to);

    yield await read();
    await for (final void _ in _isar.transactions.watchLazy()) {
      yield await read();
    }
  }

  Future<TransactionSummary> _summary({required DateTime from, required DateTime to}) async {
    final List<TransactionEntity> rows = await _inRange(from, to);

    double income = 0;
    double expense = 0;
    double transfers = 0;
    for (final TransactionEntity row in rows) {
      switch (row.type) {
        case TransactionType.income:
          income += row.amount;
        case TransactionType.expense:
          expense += row.amount;
        case TransactionType.transfer:
          transfers += row.amount;
      }
    }

    return TransactionSummary(income: income, expense: expense, transfers: transfers, count: rows.length);
  }

  @override
  Future<Result<Map<String, double>>> totalsByCategory({required DateTime from, required DateTime to, required bool expensesOnly}) => guard(() async {
    final List<TransactionEntity> rows = await _inRange(from, to);
    final Map<String, double> totals = <String, double>{};

    for (final TransactionEntity row in rows) {
      final bool wanted = expensesOnly ? row.type == TransactionType.expense : row.type == TransactionType.income;
      if (!wanted) continue;
      totals[row.categoryId] = (totals[row.categoryId] ?? 0) + row.amount;
    }

    // Sorted descending so the chart legend and the "top categories" list are
    // already in the order the UI wants to render them.
    final List<MapEntry<String, double>> sorted = totals.entries.toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) => b.value.compareTo(a.value));
    return Map<String, double>.fromEntries(sorted);
  });

  @override
  Future<Result<List<({DateTime day, double income, double expense})>>> dailyTotals({required DateTime from, required DateTime to}) =>
      guard(() async {
        final List<TransactionEntity> rows = await _inRange(from, to);

        final Map<DateTime, ({double income, double expense})> byDay = <DateTime, ({double income, double expense})>{};

        for (final TransactionEntity row in rows) {
          final DateTime day = row.date.dateOnly;
          final ({double income, double expense}) current = byDay[day] ?? (income: 0, expense: 0);
          byDay[day] = switch (row.type) {
            TransactionType.income => (income: current.income + row.amount, expense: current.expense),
            TransactionType.expense => (income: current.income, expense: current.expense + row.amount),
            TransactionType.transfer => current,
          };
        }

        // Zero-fill: a chart with gaps where nothing happened reads as missing
        // data rather than as a quiet day.
        final List<({DateTime day, double income, double expense})> series = <({DateTime day, double income, double expense})>[];
        for (DateTime day = from.dateOnly; !day.isAfter(to.dateOnly); day = day.add(const Duration(days: 1))) {
          final ({double income, double expense}) totals = byDay[day] ?? (income: 0, expense: 0);
          series.add((day: day, income: totals.income, expense: totals.expense));
        }
        return series;
      });

  Future<List<TransactionEntity>> _inRange(DateTime from, DateTime to) =>
      _isar.transactions.filter().isDeletedEqualTo(false).and().dateBetween(from.startOfDay, to.endOfDay).findAll();

  // ── Writes ──────────────────────────────────────────────────────────────────

  @override
  Future<Result<Transaction>> create(Transaction transaction) => guard(() async {
    _validate(transaction);

    final DateTime now = DateTime.now();
    final Transaction toSave = transaction.copyWith(
      amount: transaction.amount.abs(),
      createdAt: transaction.createdAt ?? now,
      updatedAt: now,
      syncStatus: SyncStatus.pendingCreate,
    );
    await _isar.isar.writeTxn(() => _isar.transactions.put(toSave.toEntity()));
    return toSave;
  });

  @override
  Future<Result<Transaction>> update(Transaction transaction) => guard(() async {
    _validate(transaction);

    final TransactionEntity? existing = await _isar.transactions.filter().uidEqualTo(transaction.id).findFirst();
    if (existing == null) {
      throw const NotFoundException('Transaction not found');
    }

    final Transaction toSave = transaction.copyWith(
      amount: transaction.amount.abs(),
      updatedAt: DateTime.now(),
      syncStatus: existing.syncStatus == SyncStatus.pendingCreate ? SyncStatus.pendingCreate : SyncStatus.pendingUpdate,
    );
    await _isar.isar.writeTxn(() => _isar.transactions.put(toSave.toEntity(isarId: existing.isarId)));
    return toSave;
  });

  @override
  Future<Result<void>> delete(String id) => guard(() async {
    final TransactionEntity? row = await _isar.transactions.filter().uidEqualTo(id).findFirst();
    if (row == null) throw const NotFoundException('Transaction not found');

    await _isar.isar.writeTxn(() async {
      if (row.syncStatus == SyncStatus.pendingCreate) {
        // Never pushed, so nobody else needs to hear about the deletion.
        await _isar.transactions.delete(row.isarId);
      } else {
        await _isar.transactions.put(
          row
            ..isDeleted = true
            ..syncStatus = SyncStatus.pendingDelete
            ..updatedAt = DateTime.now(),
        );
      }
    });
  });

  @override
  Future<Result<void>> restore(String id) => guard(() async {
    final TransactionEntity? row = await _isar.transactions.filter().uidEqualTo(id).findFirst();
    if (row == null) throw const NotFoundException('Transaction not found');

    await _isar.isar.writeTxn(
      () => _isar.transactions.put(
        row
          ..isDeleted = false
          ..syncStatus = SyncStatus.pendingUpdate
          ..updatedAt = DateTime.now(),
      ),
    );
  });

  @override
  Future<Result<int>> materialiseRecurring() => guard(() async {
    final DateTime now = DateTime.now();
    final List<TransactionEntity> recurring = await _isar.transactions
        .filter()
        .isDeletedEqualTo(false)
        .and()
        .not()
        .recurrenceEqualTo(RecurrenceRule.none)
        .findAll();

    final List<TransactionEntity> created = <TransactionEntity>[];

    for (final TransactionEntity template in recurring) {
      DateTime? next = template.recurrence.next(template.date);

      // Catch up on every occurrence that fell due while the app was closed,
      // capped so a long-dormant yearly rule cannot spawn thousands of rows.
      var guardCounter = 0;
      while (next != null && !next.isAfter(now) && guardCounter < 366) {
        final bool exists = await _isar.transactions
            .filter()
            .categoryIdEqualTo(template.categoryId)
            .and()
            .amountEqualTo(template.amount)
            .and()
            .dateEqualTo(next)
            .findFirst()
            .then((TransactionEntity? row) => row != null);

        if (!exists) {
          created.add(
            template
                .toDomain()
                .copyWith(
                  id: '${template.uid}-${next.millisecondsSinceEpoch}',
                  date: next,
                  createdAt: now,
                  updatedAt: now,
                  syncStatus: SyncStatus.pendingCreate,
                )
                .toEntity(),
          );
        }
        next = template.recurrence.next(next);
        guardCounter++;
      }
    }

    if (created.isEmpty) return 0;
    await _isar.isar.writeTxn(() => _isar.transactions.putAll(created));
    AppLogger.i('Materialised ${created.length} recurring transactions');
    return created.length;
  });

  // ── Sync ────────────────────────────────────────────────────────────────────

  @override
  Future<Result<List<Transaction>>> pendingSync() => guard(() async {
    final List<TransactionEntity> rows = await _isar.transactions.filter().not().syncStatusEqualTo(SyncStatus.synced).findAll();
    return rows.map((TransactionEntity e) => e.toDomain()).toList();
  });

  @override
  Future<Result<void>> markSynced(Iterable<String> ids) => guard(() async {
    await _isar.isar.writeTxn(() async {
      for (final String id in ids) {
        final TransactionEntity? row = await _isar.transactions.filter().uidEqualTo(id).findFirst();
        if (row == null) continue;

        if (row.syncStatus == SyncStatus.pendingDelete) {
          // The server has now accepted the deletion, so the tombstone has
          // done its job and can go.
          await _isar.transactions.delete(row.isarId);
        } else {
          await _isar.transactions.put(row..syncStatus = SyncStatus.synced);
        }
      }
    });
  });

  @override
  Future<Result<List<Transaction>>> exportAll() => guard(() async {
    final List<TransactionEntity> rows = await _isar.transactions.filter().isDeletedEqualTo(false).sortByDateDesc().findAll();
    return rows.map((TransactionEntity e) => e.toDomain()).toList();
  });

  @override
  Future<Result<int>> importAll(List<Transaction> transactions) => guard(() async {
    await _isar.isar.writeTxn(() => _isar.transactions.putAll(transactions.map((Transaction t) => t.toEntity()).toList(growable: false)));
    return transactions.length;
  });

  /// Business rules that must hold no matter which screen wrote the row.
  /// Enforcing them here (rather than only in the form) means an import or a
  /// sync payload cannot smuggle in invalid data.
  void _validate(Transaction transaction) {
    if (transaction.amount.abs() <= 0) {
      throw const ValidationException(
        'Enter an amount greater than zero',
        fieldErrors: <String, List<String>>{
          'amount': <String>['Enter an amount greater than zero'],
        },
      );
    }
    if (transaction.categoryId.isEmpty) {
      throw const ValidationException(
        'Choose a category',
        fieldErrors: <String, List<String>>{
          'category': <String>['Choose a category'],
        },
      );
    }
    if (transaction.type == TransactionType.transfer && (transaction.transferTo ?? '').trim().isEmpty) {
      throw const ValidationException(
        'Transfers need a destination',
        fieldErrors: <String, List<String>>{
          'transferTo': <String>['Transfers need a destination'],
        },
      );
    }
  }
}
