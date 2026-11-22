/// Money is stored and computed as integer minor units (paise, cents, fils).
/// How many minor units make one major unit depends on the shop's currency
/// decimals (`BusinessProfile.currencyDecimals`). Never use double for
/// amounts: sums of doubles drift.
library;

/// ISO 4217 decimal places for the currencies offered in the pickers.
const currencyDecimals = <String, int>{
  'INR': 2, 'USD': 2, 'EUR': 2, 'GBP': 2, 'AED': 2, 'SAR': 2, 'QAR': 2,
  'SGD': 2, 'MYR': 2, 'AUD': 2, 'CAD': 2, 'BDT': 2, 'NPR': 2, 'LKR': 2,
  'PKR': 2, 'JPY': 0, 'KRW': 0, 'KWD': 3, 'BHD': 3, 'OMR': 3,
};

/// Parses, formats and edits amounts for one currency.
class MoneyFormat {
  final String currency;

  /// 0 to 3.
  final int decimals;

  const MoneyFormat(this.currency, this.decimals);

  static const fallback = MoneyFormat('INR', 2);

  int get _scale => const [1, 10, 100, 1000][decimals];

  /// Parses user input such as "12", "12.5" or "12.50" into minor units.
  /// Returns null for empty, negative, non-numeric input or too many decimals.
  int? parse(String input) {
    final pattern = decimals == 0
        ? RegExp(r'^\d{1,10}$')
        : RegExp('^\\d{1,10}(\\.\\d{0,$decimals})?\$');
    final s = input.trim();
    if (!pattern.hasMatch(s)) return null;
    final parts = s.split('.');
    final fraction = (parts.length > 1 ? parts[1] : '').padRight(decimals, '0');
    return int.parse(parts[0]) * _scale + (decimals == 0 ? 0 : int.parse(fraction));
  }

  /// Minor units as an editable number, e.g. 1250 -> "12.50" at 2 decimals.
  String toInput(int minor) {
    final sign = minor < 0 ? '-' : '';
    final abs = minor.abs();
    if (decimals == 0) return '$sign$abs';
    return '$sign${abs ~/ _scale}.${(abs % _scale).toString().padLeft(decimals, '0')}';
  }

  /// Minor units for display, e.g. "INR 9.99".
  String format(int minor) => '$currency ${toInput(minor)}';

  /// Validator message for [parse] failures.
  String get inputHint => decimals == 0
      ? 'Enter a whole amount'
      : 'Enter an amount with up to $decimals decimals';
}
