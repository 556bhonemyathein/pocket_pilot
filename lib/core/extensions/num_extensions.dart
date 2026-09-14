import 'package:intl/intl.dart';

/// Money and number formatting.
///
/// Amounts are stored as `double` in the *major* unit (e.g. 12.34 USD).
/// All display formatting funnels through here so a currency change in
/// settings instantly and consistently affects every screen.
extension NumX on num {
  /// `1234.5` → `$1,234.50`.
  String toCurrency({String currencyCode = 'USD', String? symbol, int decimalDigits = 2, String? locale}) {
    final format = NumberFormat.currency(
      locale: locale,
      name: currencyCode,
      symbol: symbol ?? currencySymbolFor(currencyCode),
      decimalDigits: decimalDigits,
    );
    return format.format(this);
  }

  /// `1234.5` → `$1.2K`. Used on dashboard cards and chart axis labels where
  /// horizontal space is scarce.
  String toCompactCurrency({String currencyCode = 'USD', String? symbol}) {
    final String sign = this < 0 ? '-' : '';
    final String prefix = symbol ?? currencySymbolFor(currencyCode);
    return '$sign$prefix${NumberFormat.compact().format(abs())}';
  }

  /// `0.4213` → `42%`.
  String toPercent({int decimalDigits = 0}) => '${(this * 100).toStringAsFixed(decimalDigits)}%';

  /// Prefixes an explicit sign — used for transaction amounts.
  String toSignedCurrency({String currencyCode = 'USD', String? symbol}) {
    final String prefix = this > 0 ? '+' : '';
    return '$prefix${toCurrency(currencyCode: currencyCode, symbol: symbol)}';
  }

  /// Clamps into 0..1 — handy for budget progress bars.
  double get asProgress => (this / 1).clamp(0.0, 1.0).toDouble();

  /// Symbol lookup with a graceful fallback to the ISO code itself.
  static String currencySymbolFor(String code) {
    return _symbols[code.toUpperCase()] ?? '${code.toUpperCase()} ';
  }

  static const Map<String, String> _symbols = {
    'USD': r'$',
    'EUR': '€',
    'GBP': '£',
    'JPY': '¥',
    'CNY': '¥',
    'INR': '₹',
    'IDR': 'Rp',
    'AUD': r'A$',
    'CAD': r'C$',
    'CHF': 'CHF ',
    'SGD': r'S$',
    'MYR': 'RM',
    'SAR': '﷼',
    'AED': 'د.إ',
    'TRY': '₺',
    'BRL': r'R$',
    'ZAR': 'R',
    'KRW': '₩',
    'NGN': '₦',
    'PKR': '₨',
    'MMK': 'K',
  };
}
