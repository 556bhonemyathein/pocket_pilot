import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/models/category.dart';
import '../../../../shared/models/enums.dart';
import '../../../../shared/models/transaction.dart';
import '../../../auth/presentation/providers/auth_providers.dart';
import '../../../categories/presentation/providers/category_providers.dart';
import '../providers/transaction_providers.dart';

/// Create or edit a transaction.
///
/// One screen for both because the fields are identical — a separate "edit"
/// screen would be the same 300 lines with a different title and would drift
/// out of sync the first time a field is added.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({super.key, this.existing, this.initialType});

  /// `null` for create, populated for edit.
  final Transaction? existing;

  /// Default transaction type when creating a new transaction.
  final TransactionType? initialType;

  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late final TextEditingController _transferTo;
  final TextEditingController _tag = TextEditingController();

  late TransactionType _type;
  late DateTime _date;
  late RecurrenceRule _recurrence;
  late List<String> _tags;

  String? _categoryId;
  String? _receiptPath;
  bool _submitting = false;
  Map<String, List<String>> _fieldErrors = <String, List<String>>{};

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final Transaction? existing = widget.existing;

    _amount = TextEditingController(text: existing?.amount.toStringAsFixed(2) ?? '');
    _note = TextEditingController(text: existing?.note ?? '');
    _transferTo = TextEditingController(text: existing?.transferTo ?? '');
    _type = existing?.type ?? widget.initialType ?? TransactionType.expense;
    _date = existing?.date ?? DateTime.now();
    _recurrence = existing?.recurrence ?? RecurrenceRule.none;
    _tags = List<String>.of(existing?.tags ?? const <String>[]);
    _categoryId = existing?.categoryId;
    _receiptPath = existing?.receiptPath;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _transferTo.dispose();
    _tag.dispose();
    super.dispose();
  }

  /// Switching type can orphan the selected category (an income category is
  /// not valid for an expense), so the selection is cleared when it no longer
  /// applies rather than silently saving a mismatched pair.
  void _onTypeChanged(TransactionType type) {
    setState(() {
      _type = type;
      final Category? current = _categoryId == null ? null : ref.read(categoryLookupProvider)[_categoryId];
      if (current != null && !current.kind.allows(type)) _categoryId = null;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (picked == null || !mounted) return;

    final TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day, time?.hour ?? _date.hour, time?.minute ?? _date.minute);
    });
  }

  Future<void> _pickReceipt() async {
    final XFile? file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Receipts only need to be legible, not print quality — capping the size
      // keeps the Isar row and any future upload small.
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (file != null) setState(() => _receiptPath = file.path);
  }

  void _addTag() {
    final String value = _tag.text.trim();
    if (value.isEmpty || _tags.contains(value)) return;
    setState(() {
      _tags = <String>[..._tags, value];
      _tag.clear();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_categoryId == null) {
      setState(
        () => _fieldErrors = <String, List<String>>{
          'category': <String>['choose_a_category'.tr()],
        },
      );
      return;
    }
    context.unfocus();

    setState(() {
      _submitting = true;
      _fieldErrors = <String, List<String>>{};
    });

    final double amount = double.parse(_amount.text);
    final String currency = ref.read(currencyCodeProvider);
    final TransactionController controller = ref.read(transactionControllerProvider.notifier);

    final Failure? failure = _isEditing
        ? await controller.edit(
            widget.existing!.copyWith(
              type: _type,
              amount: amount,
              date: _date,
              categoryId: _categoryId!,
              note: _note.text.trim(),
              tags: _tags,
              receiptPath: _receiptPath,
              recurrence: _recurrence,
              transferTo: _type == TransactionType.transfer ? _transferTo.text.trim() : null,
            ),
          )
        : await controller.create(
            type: _type,
            amount: amount,
            date: _date,
            categoryId: _categoryId!,
            currencyCode: currency,
            note: _note.text.trim(),
            tags: _tags,
            receiptPath: _receiptPath,
            recurrence: _recurrence,
            transferTo: _type == TransactionType.transfer ? _transferTo.text.trim() : null,
          );

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (failure is ValidationFailure) _fieldErrors = failure.fieldErrors;
    });

    if (failure == null) {
      AppFeedback.success(context, _isEditing ? 'transaction_updated'.tr() : 'transaction_saved'.tr());
      Navigator.of(context).pop();
    } else if (failure is! ValidationFailure) {
      AppFeedback.error(context, failure);
    }
  }

  Future<void> _delete() async {
    final bool confirmed = await AppFeedback.confirm(
      context,
      title: 'delete_transaction'.tr(),
      message: 'this_cannot_be_undone_once_the_change_syncs'.tr(),
      confirmLabel: 'delete'.tr(),
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final Failure? failure = await ref.read(transactionControllerProvider.notifier).delete(widget.existing!.id);

    if (!mounted) return;
    if (failure != null) {
      AppFeedback.error(context, failure);
    } else {
      AppFeedback.success(context, 'transaction_deleted'.tr());
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Category> categories = ref.watch(categoriesByTypeProvider(_type));
    final String currency = ref.watch(currencyCodeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'edit_transaction'.tr() : 'new_transaction'.tr()),
        actions: <Widget>[if (_isEditing) IconButton(tooltip: 'delete'.tr(), onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded))],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: <Widget>[
              _TypeSelector(selected: _type, onChanged: _onTypeChanged),
              AppSpacing.xl.gapH,

              // ── Amount ────────────────────────────────────────────────────
              AppCard(
                child: Column(
                  children: <Widget>[
                    Text('amount'.tr(), style: context.text.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
                    AppSpacing.sm.gapH,
                    AppTextField.amount(
                      controller: _amount,
                      prefixText: currency,
                      errorText: _fieldErrors['amount']?.firstOrNull,
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                ),
              ),
              AppSpacing.xl.gapH,

              // ── Category ──────────────────────────────────────────────────
              Text('category'.tr(), style: context.text.labelMedium),
              AppSpacing.sm.gapH,
              _CategoryPicker(
                categories: categories,
                selectedId: _categoryId,
                onSelected: (String id) => setState(() {
                  _categoryId = id;
                  _fieldErrors = <String, List<String>>{};
                }),
              ),
              if (_fieldErrors['category'] != null) ...<Widget>[
                AppSpacing.sm.gapH,
                Text(_fieldErrors['category']!.first, style: context.text.bodySmall?.copyWith(color: context.colors.error)),
              ],
              AppSpacing.xl.gapH,

              // ── Date ──────────────────────────────────────────────────────
              _FormRow(icon: Icons.calendar_today_rounded, label: 'date'.tr(), value: _date.formattedWithTime, onTap: _pickDate),
              const Divider(height: AppSpacing.xxl),

              // ── Recurrence ────────────────────────────────────────────────
              _FormRow(
                icon: Icons.repeat_rounded,
                label: 'repeats'.tr(),
                value: _recurrence.label,
                onTap: () => AppFeedback.sheet<void>(
                  context,
                  child: AppBottomSheet(
                    title: 'repeat'.tr(),
                    // RadioGroup replaces the per-tile groupValue/onChanged
                    // pair deprecated in Flutter 3.32.
                    child: RadioGroup<RecurrenceRule>(
                      groupValue: _recurrence,
                      onChanged: (RecurrenceRule? value) {
                        setState(() => _recurrence = value ?? RecurrenceRule.none);
                        Navigator.of(context).pop();
                      },
                      child: Column(
                        children: <Widget>[
                          for (final RecurrenceRule rule in RecurrenceRule.values)
                            RadioListTile<RecurrenceRule>(value: rule, title: Text(rule.label)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: AppSpacing.xxl),

              // ── Transfer destination (conditional) ────────────────────────
              AnimatedSwitcher(
                duration: 220.ms,
                child: _type == TransactionType.transfer
                    ? Padding(
                        key: const ValueKey<String>('transfer'),
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: AppTextField(
                          controller: _transferTo,
                          label: 'transfer_to'.tr(),
                          hint: 'savings_account'.tr(),
                          prefixIcon: Icons.swap_horiz_rounded,
                          errorText: _fieldErrors['transferTo']?.firstOrNull,
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey<String>('no-transfer')),
              ),

              // ── Note ──────────────────────────────────────────────────────
              AppTextField(
                controller: _note,
                label: 'note'.tr(),
                hint: 'what_was_this_for'.tr(),
                prefixIcon: Icons.notes_rounded,
                maxLines: 3,
                maxLength: 200,
              ),
              AppSpacing.xl.gapH,

              // ── Tags ──────────────────────────────────────────────────────
              Text('tags'.tr(), style: context.text.labelMedium),
              AppSpacing.sm.gapH,
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: <Widget>[
                  for (final String tag in _tags)
                    InputChip(label: Text(tag), onDeleted: () => setState(() => _tags = _tags.where((String t) => t != tag).toList())),
                ],
              ),
              AppSpacing.sm.gapH,
              AppTextField(
                controller: _tag,
                hint: 'add_a_tag_and_press_enter'.tr(),
                prefixIcon: Icons.label_outline_rounded,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addTag(),
                suffix: IconButton(onPressed: _addTag, icon: const Icon(Icons.add_rounded, size: 20)),
              ),
              AppSpacing.xl.gapH,

              // ── Receipt ───────────────────────────────────────────────────
              _ReceiptField(path: _receiptPath, onPick: _pickReceipt, onClear: () => setState(() => _receiptPath = null)),
              AppSpacing.xxxl.gapH,

              AppButton(
                label: _isEditing ? 'save_changes'.tr() : 'add_transaction'.tr(),
                icon: Icons.check_rounded,
                isLoading: _submitting,
                onPressed: _submit,
              ),
              AppSpacing.xxl.gapH,
            ],
          ),
        ),
      ),
    );
  }
}

/// Segmented income / expense / transfer switch.
class _TypeSelector extends StatelessWidget {
  const _TypeSelector({required this.selected, required this.onChanged});

  final TransactionType selected;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    Color colorFor(TransactionType type) => switch (type) {
      TransactionType.income => context.finance.income,
      TransactionType.expense => context.finance.expense,
      TransactionType.transfer => context.finance.transfer,
    };

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          for (final TransactionType type in TransactionType.values)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(type),
                child: AnimatedContainer(
                  duration: 220.ms,
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: selected == type ? colorFor(type).withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Text(
                      type.label,
                      style: context.text.labelLarge?.copyWith(color: selected == type ? colorFor(type) : context.colors.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal category strip.
class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker({required this.categories, required this.selectedId, required this.onSelected});

  final List<Category> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) {
      return Text(
        'no_categories_for_this_type_yet_add_one_in_profi'.tr(),
        style: context.text.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, _) => AppSpacing.md.gapW,
        itemBuilder: (BuildContext context, int index) {
          final Category category = categories[index];
          final bool isSelected = category.id == selectedId;

          return GestureDetector(
            onTap: () => onSelected(category.id),
            child: AnimatedContainer(
              duration: 200.ms,
              width: 76,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: isSelected ? category.color.withValues(alpha: 0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: isSelected ? category.color : context.colors.outlineVariant, width: isSelected ? 1.6 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(category.icon, size: 22, color: category.color),
                  AppSpacing.sm.gapH,
                  Text(category.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: context.text.labelSmall),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.icon, required this.label, required this.value, required this.onTap});

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: context.colors.onSurfaceVariant),
            AppSpacing.md.gapW,
            Text(label, style: context.text.bodyMedium),
            const Spacer(),
            Text(value, style: context.text.bodyMedium?.copyWith(color: context.colors.onSurfaceVariant)),
            AppSpacing.sm.gapW,
            Icon(Icons.chevron_right_rounded, size: 18, color: context.colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ReceiptField extends StatelessWidget {
  const _ReceiptField({required this.path, required this.onPick, required this.onClear});

  final String? path;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('receipt'.tr(), style: context.text.labelMedium),
        AppSpacing.sm.gapH,
        if (path == null)
          OutlinedButton.icon(onPressed: onPick, icon: const Icon(Icons.attach_file_rounded, size: 18), label: Text('attach_a_photo'.tr()))
        else
          AppCard(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: <Widget>[
                Icon(Icons.image_outlined, color: context.colors.primary),
                AppSpacing.md.gapW,
                Expanded(
                  child: Text(path!.split(RegExp(r'[/\\]')).last, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall),
                ),
                IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded, size: 18)),
              ],
            ),
          ),
      ],
    );
  }
}
