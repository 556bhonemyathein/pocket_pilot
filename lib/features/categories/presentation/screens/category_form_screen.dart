import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/glass_panel.dart';
import '../../../../shared/models/category.dart';
import '../../../../shared/models/category_icons.dart';
import '../../../../shared/models/enums.dart';
import '../providers/category_providers.dart';

/// Create or edit a category, with icon and colour pickers.
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({super.key, this.categoryId});

  final String? categoryId;

  @override
  ConsumerState<CategoryFormScreen> createState() =>
      _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();

  late int _iconCodePoint = CategoryIcons.pickerIcons.first.codePoint;
  late int _colorValue = AppColors.categorySwatches.first.toARGB32();
  CategoryKind _kind = CategoryKind.expense;

  Category? _existing;
  bool _submitting = false;
  bool _initialised = false;
  Map<String, List<String>> _fieldErrors = <String, List<String>>{};

  bool get _isEditing => widget.categoryId != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Seeds the form from the existing category once the list has loaded.
  ///
  /// Done in `build` (guarded by [_initialised]) rather than `initState`
  /// because the categories stream may not have emitted yet when the screen
  /// is first constructed.
  void _hydrate(Category? category) {
    if (_initialised || category == null) return;
    _initialised = true;
    _existing = category;
    _name.text = category.name;
    _iconCodePoint = category.iconCodePoint;
    _colorValue = category.colorValue;
    _kind = category.kind;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    context.unfocus();

    setState(() {
      _submitting = true;
      _fieldErrors = <String, List<String>>{};
    });

    final CategoryController controller = ref.read(
      categoryControllerProvider.notifier,
    );

    final Category category = (_existing ??
            Category(
              id: const Uuid().v4(),
              name: '',
              iconCodePoint: _iconCodePoint,
              colorValue: _colorValue,
            ))
        .copyWith(
          name: _name.text.trim(),
          iconCodePoint: _iconCodePoint,
          colorValue: _colorValue,
          kind: _kind,
        );

    final Failure? failure = _isEditing
        ? await controller.edit(category)
        : await controller.create(category);

    if (!mounted) return;
    setState(() {
      _submitting = false;
      if (failure is ValidationFailure) _fieldErrors = failure.fieldErrors;
    });

    if (failure == null) {
      AppFeedback.success(
        context,
        _isEditing ? 'category_updated'.tr() : 'category_created'.tr(),
      );
      Navigator.of(context).pop();
    } else if (failure is! ValidationFailure) {
      AppFeedback.error(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEditing) {
      _hydrate(ref.watch(categoryLookupProvider)[widget.categoryId]);
    }

    final Color color = Color(_colorValue);
    final IconData icon = CategoryIcons.resolve(_iconCodePoint);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'edit_category'.tr() : 'new_category'.tr()),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.page),
            children: <Widget>[
              // Live preview: the user sees the result of both pickers before
              // committing, which is faster than save-look-edit.
              Center(
                child: AnimatedContainer(
                  duration: 250.ms,
                  height: 88,
                  width: 88,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Icon(icon, size: 40, color: color),
                ),
              ),
              AppSpacing.xxl.gapH,

              AppTextField(
                controller: _name,
                label: 'name'.tr(),
                hint: 'category_name_hint'.tr(),
                prefixIcon: Icons.label_outline_rounded,
                errorText: _fieldErrors['name']?.firstOrNull,
                validator: (String? value) =>
                    (value ?? '').trim().length >= 2
                    ? null
                    : 'give_the_category_a_name'.tr(),
              ),
              AppSpacing.xl.gapH,

              Text('applies_to'.tr(), style: context.text.labelMedium),
              AppSpacing.sm.gapH,
              SegmentedButton<CategoryKind>(
                segments: <ButtonSegment<CategoryKind>>[
                  ButtonSegment<CategoryKind>(
                    value: CategoryKind.expense,
                    label: Text('expense'.tr()),
                  ),
                  ButtonSegment<CategoryKind>(
                    value: CategoryKind.income,
                    label: Text('income'.tr()),
                  ),
                  ButtonSegment<CategoryKind>(
                    value: CategoryKind.both,
                    label: Text('both'.tr()),
                  ),
                ],
                selected: <CategoryKind>{_kind},
                onSelectionChanged: (Set<CategoryKind> selection) =>
                    setState(() => _kind = selection.first),
              ),
              AppSpacing.xl.gapH,

              Text('colour'.tr(), style: context.text.labelMedium),
              AppSpacing.md.gapH,
              _ColorPicker(
                selected: _colorValue,
                onSelected: (int value) =>
                    setState(() => _colorValue = value),
              ),
              AppSpacing.xl.gapH,

              Text('icon'.tr(), style: context.text.labelMedium),
              AppSpacing.md.gapH,
              _IconPicker(
                selected: _iconCodePoint,
                color: color,
                onSelected: (int codePoint) =>
                    setState(() => _iconCodePoint = codePoint),
              ),
              AppSpacing.xxxl.gapH,

              AppButton(
                label: _isEditing ? 'save_changes'.tr() : 'create_category'.tr(),
                icon: Icons.check_rounded,
                isLoading: _submitting,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: <Widget>[
        for (final Color swatch in AppColors.categorySwatches)
          GestureDetector(
            onTap: () => onSelected(swatch.toARGB32()),
            child: AnimatedContainer(
              duration: 180.ms,
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: swatch,
                shape: BoxShape.circle,
                border: Border.all(
                  color: swatch.toARGB32() == selected
                      ? context.colors.onSurface
                      : Colors.transparent,
                  width: 3,
                ),
              ),
              child: swatch.toARGB32() == selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

class _IconPicker extends StatelessWidget {
  const _IconPicker({
    required this.selected,
    required this.color,
    required this.onSelected,
  });

  final int selected;
  final Color color;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final IconData icon in CategoryIcons.pickerIcons)
            GestureDetector(
              onTap: () => onSelected(icon.codePoint),
              child: AnimatedContainer(
                duration: 160.ms,
                height: 46,
                width: 46,
                decoration: BoxDecoration(
                  color: icon.codePoint == selected
                      ? color.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: icon.codePoint == selected
                        ? color
                        : context.colors.outlineVariant,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: icon.codePoint == selected
                      ? color
                      : context.colors.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
