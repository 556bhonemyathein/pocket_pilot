import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../shared/models/category.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction_query.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../providers/transaction_providers.dart';

/// Filter editor.
///
/// Edits a *draft* copy and only commits on "Apply". Live-applying each toggle
/// would make the list thrash behind the sheet and would leave no way to
/// cancel — the user would have to undo each change by hand.
class TransactionFilterSheet extends ConsumerStatefulWidget {
  const TransactionFilterSheet({super.key});

  @override
  ConsumerState<TransactionFilterSheet> createState() =>
      _TransactionFilterSheetState();
}

class _TransactionFilterSheetState
    extends ConsumerState<TransactionFilterSheet> {
  late TransactionQuery _draft = ref.read(transactionQueryProvider);
  late final TextEditingController _min = TextEditingController(
    text: _draft.minAmount?.toStringAsFixed(2) ?? '',
  );
  late final TextEditingController _max = TextEditingController(
    text: _draft.maxAmount?.toStringAsFixed(2) ?? '',
  );

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  void _apply() {
    final TransactionQueryNotifier notifier = ref.read(
      transactionQueryProvider.notifier,
    );

    notifier
      ..setDateRange(_draft.from, _draft.to)
      ..setAmountRange(
        double.tryParse(_min.text),
        double.tryParse(_max.text),
      );

    // Reconcile the type/category sets by toggling the differences, so the
    // notifier stays the only thing that mutates query state.
    final TransactionQuery current = ref.read(transactionQueryProvider);
    for (final TransactionType type in TransactionType.values) {
      if (_draft.types.contains(type) != current.types.contains(type)) {
        notifier.toggleType(type);
      }
    }
    final Set<String> allIds = <String>{
      ..._draft.categoryIds,
      ...current.categoryIds,
    };
    for (final String id in allIds) {
      if (_draft.categoryIds.contains(id) !=
          ref.read(transactionQueryProvider).categoryIds.contains(id)) {
        notifier.toggleCategory(id);
      }
    }

    Navigator.of(context).pop();
  }

  Future<void> _pickRange() async {
    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _draft.from != null && _draft.to != null
          ? DateTimeRange(start: _draft.from!, end: _draft.to!)
          : null,
    );
    if (range != null) {
      setState(() => _draft = _draft.copyWith(from: range.start, to: range.end));
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Category> categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];

    return AppBottomSheet(
      title: 'filter_transactions'.tr(),
      actionLabel: 'apply_filters'.tr(),
      onAction: _apply,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _SectionLabel('type'.tr()),
          Wrap(
            spacing: AppSpacing.sm,
            children: <Widget>[
              for (final TransactionType type in TransactionType.values)
                FilterChip(
                  label: Text(type.label),
                  selected: _draft.types.contains(type),
                  onSelected: (bool selected) => setState(() {
                    final Set<TransactionType> next =
                        Set<TransactionType>.of(_draft.types);
                    selected ? next.add(type) : next.remove(type);
                    _draft = _draft.copyWith(types: next);
                  }),
                ),
            ],
          ),
          AppSpacing.xl.gapH,

          _SectionLabel('date_range'.tr()),
          OutlinedButton.icon(
            onPressed: _pickRange,
            icon: const Icon(Icons.calendar_today_rounded, size: 18),
            label: Text(
              _draft.from == null || _draft.to == null
                  ? 'any_date'.tr()
                  : '${_draft.from!.formatted} → ${_draft.to!.formatted}',
            ),
          ),
          if (_draft.from != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(
                  () => _draft = _draft.copyWith(from: null, to: null),
                ),
                child: Text('clear_dates'.tr()),
              ),
            ),
          AppSpacing.xl.gapH,

          _SectionLabel('amount'.tr()),
          Row(
            children: <Widget>[
              Expanded(
                child: AppTextField.amount(
                  controller: _min,
                  label: 'min'.tr(),
                ),
              ),
              AppSpacing.md.gapW,
              Expanded(
                child: AppTextField.amount(
                  controller: _max,
                  label: 'max'.tr(),
                ),
              ),
            ],
          ),
          AppSpacing.xl.gapH,

          _SectionLabel('categories'.tr()),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              for (final Category category in categories)
                FilterChip(
                  avatar: Icon(
                    category.icon,
                    size: 16,
                    color: category.color,
                  ),
                  label: Text(category.name),
                  selected: _draft.categoryIds.contains(category.id),
                  onSelected: (bool selected) => setState(() {
                    final Set<String> next =
                        Set<String>.of(_draft.categoryIds);
                    selected ? next.add(category.id) : next.remove(category.id);
                    _draft = _draft.copyWith(categoryIds: next);
                  }),
                ),
            ],
          ),
          AppSpacing.lg.gapH,

          AppButton.text(
            label: 'reset_all'.tr(),
            onPressed: () => setState(() {
              _draft = const TransactionQuery();
              _min.clear();
              _max.clear();
            }),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: context.text.labelMedium?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
