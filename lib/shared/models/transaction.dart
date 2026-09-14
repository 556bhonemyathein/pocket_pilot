import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'transaction.freezed.dart';
part 'transaction.g.dart';

/// Domain model for a money movement.
///
/// This is what the UI and the business rules speak. It is deliberately
/// decoupled from the Isar row (`TransactionEntity`) and from the wire format:
/// the database can gain an index and the API can rename a field without a
/// single widget changing.
@freezed
abstract class Transaction with _$Transaction {
  const factory Transaction({
    /// Client-generated UUID — stable across offline creation and later sync,
    /// which is what lets the app create rows without waiting for a server id.
    required String id,
    required TransactionType type,
    required double amount,
    required DateTime date,
    required String categoryId,
    @Default('USD') String currencyCode,
    @Default('') String note,
    @Default(<String>[]) List<String> tags,
    String? receiptPath,
    @Default(<String>[]) List<String> attachments,
    @Default(RecurrenceRule.none) RecurrenceRule recurrence,

    /// For transfers: the destination pot/account label.
    String? transferTo,
    DateTime? createdAt,
    DateTime? updatedAt,
    @Default(SyncStatus.pendingCreate) SyncStatus syncStatus,
  }) = _Transaction;

  const Transaction._();

  factory Transaction.fromJson(Map<String, dynamic> json) => _$TransactionFromJson(json);

  /// Amount signed by type — the single definition of "effect on balance".
  double get signedAmount => amount.abs() * type.sign;

  bool get isRecurring => recurrence != RecurrenceRule.none;

  bool get hasAttachments => receiptPath != null || attachments.isNotEmpty;

  /// Free-text haystack used by realtime search.
  String get searchHaystack => '$note ${tags.join(' ')} ${transferTo ?? ''} $amount ${amount.toStringAsFixed(2)} ${type.name}'.toLowerCase();
}
