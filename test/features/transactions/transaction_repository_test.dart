import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:pocket_pilot/core/errors/failure.dart';
import 'package:pocket_pilot/core/storage/entities/category_entity.dart';
import 'package:pocket_pilot/core/storage/isar_service.dart';
import 'package:pocket_pilot/core/utils/result.dart';
import 'package:pocket_pilot/features/transactions/data/transaction_repository_impl.dart';
import 'package:pocket_pilot/features/transactions/domain/transaction_repository.dart';
import 'package:pocket_pilot/shared/models/enums.dart';
import 'package:pocket_pilot/shared/models/transaction.dart';
import 'package:pocket_pilot/shared/models/transaction_query.dart';

/// Repository tests against a **real** Isar database in a temp directory.
///
/// Mocking the database here would only prove the mock works. The behaviour
/// worth protecting — filters composing correctly, tombstones surviving,
/// sync status transitions — is exactly the behaviour a fake would fabricate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late IsarService isar;
  late TransactionRepository repository;

  setUpAll(() async {
    // `flutter test` stubs out HTTP, so Isar's own `download: true` cannot
    // fetch the native library. The binary is vendored in `.isar/` instead
    // (see README) and pointed at explicitly.
    await Isar.initializeIsarCore(
      libraries: <Abi, String>{
        Abi.windowsX64: r'.isar\libisar.dll',
        Abi.linuxX64: '.isar/libisar.so',
        Abi.macosX64: '.isar/libisar.dylib',
        Abi.macosArm64: '.isar/libisar.dylib',
      },
    );
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('pocketpilot-isar-test');
    isar = await IsarService.openForTest(tempDir.path);
    repository = TransactionRepositoryImpl(isar);
  });

  tearDown(() async {
    await isar.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Transaction make({
    required String id,
    TransactionType type = TransactionType.expense,
    double amount = 10,
    DateTime? date,
    String categoryId = 'cat-food',
    String note = '',
    List<String> tags = const <String>[],
    RecurrenceRule recurrence = RecurrenceRule.none,
    String? transferTo,
  }) => Transaction(
    id: id,
    type: type,
    amount: amount,
    date: date ?? DateTime(2026, 8, 5),
    categoryId: categoryId,
    note: note,
    tags: tags,
    recurrence: recurrence,
    transferTo: transferTo,
  );

  group('create', () {
    test('persists a row and marks it pending create', () async {
      final Result<Transaction> result = await repository.create(make(id: 'tx-1'));

      expect(result.isSuccess, isTrue);
      expect(result.dataOrNull?.syncStatus, SyncStatus.pendingCreate);

      final Result<Transaction?> fetched = await repository.getById('tx-1');
      expect(fetched.dataOrNull?.amount, 10);
    });

    test('stores the absolute amount so sign is derived from type', () async {
      final Result<Transaction> result = await repository.create(make(id: 'tx-1', amount: -50));

      expect(result.dataOrNull?.amount, 50);
      expect(result.dataOrNull?.signedAmount, -50);
    });

    test('rejects a zero amount', () async {
      final Result<Transaction> result = await repository.create(make(id: 'tx-1', amount: 0));

      final Failure? failure = result.failureOrNull;
      expect(failure, isA<ValidationFailure>());
      expect((failure! as ValidationFailure).errorFor('amount'), isNotNull);
    });

    test('rejects a transfer with no destination', () async {
      final Result<Transaction> result = await repository.create(make(id: 'tx-1', type: TransactionType.transfer));

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('accepts a transfer with a destination', () async {
      final Result<Transaction> result = await repository.create(make(id: 'tx-1', type: TransactionType.transfer, transferTo: 'Savings'));

      expect(result.isSuccess, isTrue);
    });
  });

  group('update', () {
    test('keeps pendingCreate for a row the server has never seen', () async {
      await repository.create(make(id: 'tx-1'));
      final Result<Transaction> updated = await repository.update(make(id: 'tx-1', amount: 99));

      // Promoting this to pendingUpdate would make the sync engine issue a
      // PUT for a row that does not exist remotely.
      expect(updated.dataOrNull?.syncStatus, SyncStatus.pendingCreate);
      expect(updated.dataOrNull?.amount, 99);
    });

    test('marks a synced row as pendingUpdate', () async {
      await repository.create(make(id: 'tx-1'));
      await repository.markSynced(<String>['tx-1']);

      final Result<Transaction> updated = await repository.update(make(id: 'tx-1', amount: 42));
      expect(updated.dataOrNull?.syncStatus, SyncStatus.pendingUpdate);
    });

    test('fails for a missing row', () async {
      final Result<Transaction> result = await repository.update(make(id: 'nope'));
      expect(result.failureOrNull, isA<NotFoundFailure>());
    });
  });

  group('delete and restore', () {
    test('hard-deletes a row that was never pushed', () async {
      await repository.create(make(id: 'tx-1'));
      await repository.delete('tx-1');

      // Nothing remote to reconcile, so no tombstone is needed.
      expect((await repository.getById('tx-1')).dataOrNull, isNull);
      expect((await repository.pendingSync()).dataOrNull, isEmpty);
    });

    test('tombstones a synced row so the deletion can be replayed', () async {
      await repository.create(make(id: 'tx-1'));
      await repository.markSynced(<String>['tx-1']);
      await repository.delete('tx-1');

      final List<Transaction> pending = (await repository.pendingSync()).dataOrNull!;
      expect(pending.single.syncStatus, SyncStatus.pendingDelete);

      // Tombstoned rows must not appear in the list.
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery());
      expect(page.dataOrNull?.items, isEmpty);
    });

    test('restore brings a tombstoned row back', () async {
      await repository.create(make(id: 'tx-1'));
      await repository.markSynced(<String>['tx-1']);
      await repository.delete('tx-1');
      await repository.restore('tx-1');

      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery());
      expect(page.dataOrNull?.items.single.id, 'tx-1');
    });

    test('markSynced removes an accepted tombstone entirely', () async {
      await repository.create(make(id: 'tx-1'));
      await repository.markSynced(<String>['tx-1']);
      await repository.delete('tx-1');
      await repository.markSynced(<String>['tx-1']);

      expect((await repository.pendingSync()).dataOrNull, isEmpty);
      expect((await repository.getById('tx-1')).dataOrNull, isNull);
    });
  });

  group('queries', () {
    setUp(() async {
      await repository.create(
        make(id: 'a', type: TransactionType.income, amount: 1000, categoryId: 'cat-salary', date: DateTime(2026, 8, 1), note: 'August salary'),
      );
      await repository.create(
        make(id: 'b', amount: 25, categoryId: 'cat-food', date: DateTime(2026, 8, 3), note: 'Team lunch', tags: const <String>['work']),
      );
      await repository.create(make(id: 'c', amount: 400, categoryId: 'cat-rent', date: DateTime(2026, 7, 28), note: 'Rent'));
    });

    test('returns everything with an empty query', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery());
      expect(page.dataOrNull?.total, 3);
    });

    test('filters by type', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery(types: <TransactionType>{TransactionType.income}));
      expect(page.dataOrNull?.items.single.id, 'a');
    });

    test('filters by category', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery(categoryIds: <String>{'cat-food'}));
      expect(page.dataOrNull?.items.single.id, 'b');
    });

    test('filters by date range inclusively', () async {
      final Result<TransactionPage> page = await repository.getPage(TransactionQuery(from: DateTime(2026, 8), to: DateTime(2026, 8, 31)));
      expect(page.dataOrNull?.items.map((Transaction t) => t.id).toSet(), <String>{'a', 'b'});
    });

    test('filters by amount range', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery(minAmount: 20, maxAmount: 500));
      expect(page.dataOrNull?.items.map((Transaction t) => t.id).toSet(), <String>{'b', 'c'});
    });

    test('searches notes case-insensitively', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery(search: 'LUNCH'));
      expect(page.dataOrNull?.items.single.id, 'b');
    });

    test('searches tags', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery(search: 'work'));
      expect(page.dataOrNull?.items.single.id, 'b');
    });

    test('combines filters with AND semantics', () async {
      final Result<TransactionPage> page = await repository.getPage(
        TransactionQuery(types: const <TransactionType>{TransactionType.expense}, from: DateTime(2026, 8), to: DateTime(2026, 8, 31)),
      );
      expect(page.dataOrNull?.items.single.id, 'b');
    });

    test('sorts by date descending by default', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery());
      expect(page.dataOrNull?.items.map((Transaction t) => t.id).toList(), <String>['b', 'a', 'c']);
    });

    test('sorts by amount', () async {
      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery(sort: TransactionSort.amountDesc));
      expect(page.dataOrNull?.items.map((Transaction t) => t.id).toList(), <String>['a', 'c', 'b']);
    });

    test('paginates cumulatively and reports hasMore', () async {
      final Result<TransactionPage> first = await repository.getPage(const TransactionQuery(pageSize: 2));
      expect(first.dataOrNull?.items, hasLength(2));
      expect(first.dataOrNull?.hasMore, isTrue);
      expect(first.dataOrNull?.total, 3);

      final Result<TransactionPage> second = await repository.getPage(const TransactionQuery(pageSize: 2, page: 1));
      // Page 2 returns rows 0..n so the list widget renders one flat list.
      expect(second.dataOrNull?.items, hasLength(3));
      expect(second.dataOrNull?.hasMore, isFalse);
    });
  });

  group('aggregates', () {
    setUp(() async {
      await repository.create(make(id: 'a', type: TransactionType.income, amount: 1000, date: DateTime(2026, 8, 1)));
      await repository.create(make(id: 'b', amount: 250, date: DateTime(2026, 8, 2)));
      await repository.create(make(id: 'c', type: TransactionType.transfer, amount: 500, transferTo: 'Savings', date: DateTime(2026, 8, 2)));
    });

    test('summary excludes transfers from the balance', () async {
      final TransactionSummary summary = await repository.watchSummary(from: DateTime(2026, 8), to: DateTime(2026, 8, 31)).first;

      expect(summary.income, 1000);
      expect(summary.expense, 250);
      expect(summary.transfers, 500);
      // A transfer moves money between the user's own pots — balance neutral.
      expect(summary.balance, 750);
      expect(summary.savingsRate, closeTo(0.75, 0.001));
    });

    test('savings rate is 0 rather than NaN with no income', () async {
      final TransactionSummary summary = await repository.watchSummary(from: DateTime(2026, 9), to: DateTime(2026, 9, 30)).first;

      expect(summary.savingsRate, 0);
    });

    test('totalsByCategory ranks descending', () async {
      await repository.create(make(id: 'd', amount: 900, categoryId: 'cat-rent', date: DateTime(2026, 8, 4)));

      final Result<Map<String, double>> totals = await repository.totalsByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        expensesOnly: true,
      );

      expect(totals.dataOrNull?.keys.first, 'cat-rent');
      expect(totals.dataOrNull?['cat-rent'], 900);
      expect(totals.dataOrNull?['cat-food'], 250);
    });

    test('dailyTotals zero-fills days with no activity', () async {
      final Result<List<({DateTime day, double income, double expense})>> series = await repository.dailyTotals(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 5),
      );

      final days = series.dataOrNull!;
      // A gap in a chart reads as missing data, not as a quiet day.
      expect(days, hasLength(5));
      expect(days[0].income, 1000);
      expect(days[2].income, 0);
      expect(days[2].expense, 0);
    });
  });

  group('recurring', () {
    test('materialises occurrences that fell due while the app was closed', () async {
      final DateTime twoMonthsAgo = DateTime.now().subtract(const Duration(days: 62));
      await repository.create(make(id: 'rent', amount: 900, date: twoMonthsAgo, recurrence: RecurrenceRule.monthly));

      final Result<int> created = await repository.materialiseRecurring();
      expect(created.dataOrNull, greaterThanOrEqualTo(1));

      final Result<TransactionPage> page = await repository.getPage(const TransactionQuery());
      expect(page.dataOrNull!.total, greaterThan(1));
    });

    test('is idempotent — a second run creates nothing new', () async {
      await repository.create(
        make(id: 'rent', amount: 900, date: DateTime.now().subtract(const Duration(days: 40)), recurrence: RecurrenceRule.monthly),
      );

      await repository.materialiseRecurring();
      final Result<int> second = await repository.materialiseRecurring();

      // Re-running on every launch must not duplicate the user's rent.
      expect(second.dataOrNull, 0);
    });

    test('ignores non-recurring rows', () async {
      await repository.create(make(id: 'tx-1'));
      final Result<int> created = await repository.materialiseRecurring();
      expect(created.dataOrNull, 0);
    });
  });

  group('export and import', () {
    test('round-trips through export/import', () async {
      await repository.create(make(id: 'tx-1', note: 'Coffee', tags: const <String>['cafe']));

      final List<Transaction> exported = (await repository.exportAll()).dataOrNull!;
      expect(exported, hasLength(1));

      await isar.clear();
      expect((await repository.exportAll()).dataOrNull, isEmpty);

      final Result<int> imported = await repository.importAll(exported);
      expect(imported.dataOrNull, 1);

      final Transaction restored = (await repository.getById('tx-1')).dataOrNull!;
      expect(restored.note, 'Coffee');
      expect(restored.tags, <String>['cafe']);
    });
  });

  group('watchPage', () {
    test('re-emits when a transaction is written', () async {
      final Stream<TransactionPage> stream = repository.watchPage(const TransactionQuery());

      // Take two emissions: the initial read, then the one triggered by the
      // write. This is the mechanism that keeps every list self-updating.
      final Future<List<TransactionPage>> collected = stream.take(2).toList();

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repository.create(make(id: 'tx-1'));

      final List<TransactionPage> pages = await collected;
      expect(pages.first.total, 0);
      expect(pages.last.total, 1);
    });
  });

  group('search and matching', () {
    setUp(() async {
      await isar.isar.writeTxn(() async {
        await isar.categories.put(
          CategoryEntity()
            ..uid = 'cat-food'
            ..name = 'Groceries & Food'
            ..iconCodePoint = 0
            ..colorValue = 0
            ..kind = CategoryKind.expense
            ..isDefault = true
            ..sortOrder = 0
            ..createdAt = DateTime(2026, 1, 1)
            ..updatedAt = DateTime(2026, 1, 1)
            ..syncStatus = SyncStatus.synced,
        );
        await isar.categories.put(
          CategoryEntity()
            ..uid = 'cat-salary'
            ..name = 'Salary'
            ..iconCodePoint = 0
            ..colorValue = 0
            ..kind = CategoryKind.income
            ..isDefault = true
            ..sortOrder = 1
            ..createdAt = DateTime(2026, 1, 1)
            ..updatedAt = DateTime(2026, 1, 1)
            ..syncStatus = SyncStatus.synced,
        );
      });

      await repository.create(
        make(
          id: 'tx-1',
          amount: 42.50,
          categoryId: 'cat-food',
          note: 'Dinner with Alice',
          tags: const <String>['restaurant', 'fun'],
          date: DateTime(2026, 8, 15),
        ),
      );

      await repository.create(
        make(id: 'tx-2', type: TransactionType.income, amount: 3000, categoryId: 'cat-salary', note: 'August paycheck', date: DateTime(2026, 8, 31)),
      );
    });

    test('finds transactions by note', () async {
      final Result<TransactionPage> result = await repository.getPage(const TransactionQuery(search: 'dinner'));
      expect(result.dataOrNull?.items, hasLength(1));
      expect(result.dataOrNull?.items.first.id, 'tx-1');
    });

    test('finds transactions by category name even without note matching', () async {
      final Result<TransactionPage> result = await repository.getPage(const TransactionQuery(search: 'groceries'));
      expect(result.dataOrNull?.items, hasLength(1));
      expect(result.dataOrNull?.items.first.id, 'tx-1');
    });

    test('finds transactions by amount with currency symbol or decimals', () async {
      final Result<TransactionPage> withCurrency = await repository.getPage(const TransactionQuery(search: r'$42.50'));
      expect(withCurrency.dataOrNull?.items, hasLength(1));
      expect(withCurrency.dataOrNull?.items.first.id, 'tx-1');

      final Result<TransactionPage> withNum = await repository.getPage(const TransactionQuery(search: '3000'));
      expect(withNum.dataOrNull?.items, hasLength(1));
      expect(withNum.dataOrNull?.items.first.id, 'tx-2');
    });

    test('finds transactions by type name', () async {
      final Result<TransactionPage> result = await repository.getPage(const TransactionQuery(search: 'income'));
      expect(result.dataOrNull?.items, hasLength(1));
      expect(result.dataOrNull?.items.first.id, 'tx-2');
    });

    test('multi-word query matches across category, note, and amount', () async {
      final Result<TransactionPage> result = await repository.getPage(const TransactionQuery(search: 'food 42.50'));
      expect(result.dataOrNull?.items, hasLength(1));
      expect(result.dataOrNull?.items.first.id, 'tx-1');
    });

    test('returns empty when no fields match', () async {
      final Result<TransactionPage> result = await repository.getPage(const TransactionQuery(search: 'nonexistent12345'));
      expect(result.dataOrNull?.items, isEmpty);
    });
  });
}
