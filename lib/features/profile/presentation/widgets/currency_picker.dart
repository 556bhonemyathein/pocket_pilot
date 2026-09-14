import 'package:flutter/material.dart';

import '../../../../core/extensions/extensions.dart';
import '../../../../core/theme/app_dimens.dart';
import '../../../../core/widgets/app_feedback.dart';

/// Currencies offered by the picker.
///
/// A curated list rather than every ISO 4217 code: a 180-row list is hostile
/// to scroll, and the long tail can be added on demand.
const List<({String code, String name})> kSupportedCurrencies = <({String code, String name})>[
  (code: 'USD', name: 'US Dollar'),
  (code: 'MMK', name: 'Myanmar Kyat'),
  (code: 'EUR', name: 'Euro'),
  (code: 'GBP', name: 'British Pound'),
  (code: 'JPY', name: 'Japanese Yen'),
  (code: 'CNY', name: 'Chinese Yuan'),
  (code: 'INR', name: 'Indian Rupee'),
  (code: 'IDR', name: 'Indonesian Rupiah'),
  (code: 'AUD', name: 'Australian Dollar'),
  (code: 'CAD', name: 'Canadian Dollar'),
  (code: 'CHF', name: 'Swiss Franc'),
  (code: 'SGD', name: 'Singapore Dollar'),
  (code: 'MYR', name: 'Malaysian Ringgit'),
  (code: 'AED', name: 'UAE Dirham'),
  (code: 'SAR', name: 'Saudi Riyal'),
  (code: 'TRY', name: 'Turkish Lira'),
  (code: 'BRL', name: 'Brazilian Real'),
  (code: 'ZAR', name: 'South African Rand'),
  (code: 'KRW', name: 'South Korean Won'),
  (code: 'NGN', name: 'Nigerian Naira'),
  (code: 'PKR', name: 'Pakistani Rupee'),
];

/// Tappable field that opens the currency sheet.
class CurrencyPickerField extends StatelessWidget {
  const CurrencyPickerField({required this.selected, required this.onSelected, super.key});

  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final ({String code, String name}) current = kSupportedCurrencies.firstWhere(
      (({String code, String name}) c) => c.code == selected,
      orElse: () => (code: selected, name: selected),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () async {
        final String? picked = await AppFeedback.sheet<String>(context, child: CurrencySheet(selected: selected));
        if (picked != null) onSelected(picked);
      },
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: context.theme.inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            Text(NumX.currencySymbolFor(current.code), style: context.text.titleMedium),
            AppSpacing.md.gapW,
            Expanded(child: Text('${current.code} · ${current.name}', style: context.text.bodyLarge)),
            const Icon(Icons.expand_more_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}

class CurrencySheet extends StatelessWidget {
  const CurrencySheet({required this.selected, super.key});

  final String selected;

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      title: 'Choose currency',
      child: Column(
        children: <Widget>[
          for (final ({String code, String name}) currency in kSupportedCurrencies)
            ListTile(
              leading: SizedBox(width: 36, child: Text(NumX.currencySymbolFor(currency.code), style: context.text.titleMedium)),
              title: Text(currency.name),
              subtitle: Text(currency.code),
              trailing: currency.code == selected ? Icon(Icons.check_circle_rounded, color: context.colors.primary) : null,
              onTap: () => Navigator.of(context).pop(currency.code),
            ),
        ],
      ),
    );
  }
}
