import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../extensions/extensions.dart';
import '../theme/app_dimens.dart';

/// Keeps a text field to a well-formed decimal amount.
///
/// It *sanitises* rather than rejects: a naive
/// `FilteringTextInputFormatter.allow` anchored with `^` silently truncates a
/// pasted "12ab.99" to "12", losing the pence. This keeps every digit, the
/// first decimal point only, and at most two decimal places — so paste,
/// autofill and OCR'd amounts all behave.
class DecimalInputFormatter extends TextInputFormatter {
  const DecimalInputFormatter({this.decimalPlaces = 2});

  final int decimalPlaces;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final StringBuffer buffer = StringBuffer();
    var seenDot = false;
    var decimals = 0;

    for (final String char in newValue.text.split('')) {
      if (char == '.' || char == ',') {
        // Accept a comma as a decimal separator, but only the first one.
        if (seenDot || buffer.isEmpty) continue;
        seenDot = true;
        buffer.write('.');
        continue;
      }
      if (char.codeUnitAt(0) < 0x30 || char.codeUnitAt(0) > 0x39) continue;
      if (seenDot) {
        if (decimals >= decimalPlaces) continue;
        decimals++;
      }
      buffer.write(char);
    }

    final String text = buffer.toString();
    if (text == newValue.text) return newValue;

    // Keep the caret at the end of the sanitised text; trying to preserve the
    // original offset after removing characters is what produces the classic
    // "cursor jumps to the middle" bug.
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The app's one text field.
///
/// Wraps [TextFormField] to standardise label placement, error rendering and
/// the password visibility toggle. Keeping the obscure-text state *inside* the
/// widget is the one place `setState` is appropriate: it is pure UI state that
/// nothing outside this widget can observe or care about.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.controller,
    super.key,
    this.label,
    this.hint,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    this.enabled = true,
    this.inputFormatters,
    this.autofillHints,
  });

  /// Money input: numeric keyboard, two decimals, no stray characters.
  factory AppTextField.amount({
    required TextEditingController controller,
    Key? key,
    String? label,
    String? hint,
    String? errorText,
    String? prefixText,
    ValueChanged<String>? onChanged,
  }) => AppTextField(
    key: key,
    controller: controller,
    label: label,
    hint: hint ?? '0.00',
    errorText: errorText,
    onChanged: onChanged,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const <TextInputFormatter>[DecimalInputFormatter()],
    prefixIcon: null,
    suffix: prefixText == null ? null : Text(prefixText),
  );

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final IconData? prefixIcon;
  final Widget? suffix;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Server-side error for this field, pushed down from a `ValidationFailure`.
  final String? errorText;

  final int maxLines;
  final int? maxLength;
  final bool autofocus;
  final bool enabled;
  final List<TextInputFormatter>? inputFormatters;
  final List<String>? autofillHints;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _obscured = widget.obscureText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.label != null) ...<Widget>[
          Text(
            widget.label!,
            style: context.text.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          AppSpacing.sm.gapH,
        ],
        TextFormField(
          controller: widget.controller,
          obscureText: _obscured,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          validator: widget.validator,
          onChanged: widget.onChanged,
          onFieldSubmitted: widget.onSubmitted,
          maxLines: _obscured ? 1 : widget.maxLines,
          maxLength: widget.maxLength,
          inputFormatters: widget.inputFormatters,
          autofillHints: widget.autofillHints,
          style: context.text.bodyLarge,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            counterText: '',
            prefixIcon: widget.prefixIcon == null
                ? null
                : Icon(widget.prefixIcon, size: 20),
            suffixIcon: _buildSuffix(),
          ),
        ),
      ],
    );
  }

  Widget? _buildSuffix() {
    if (widget.obscureText) {
      return IconButton(
        tooltip: _obscured ? 'show_password'.tr() : 'hide_password'.tr(),
        icon: Icon(
          _obscured
              ? Icons.visibility_outlined
              : Icons.visibility_off_outlined,
          size: 20,
        ),
        onPressed: () => setState(() => _obscured = !_obscured),
      );
    }
    if (widget.suffix != null) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        child: Align(
          alignment: Alignment.centerRight,
          widthFactor: 1,
          child: widget.suffix,
        ),
      );
    }
    return null;
  }
}
