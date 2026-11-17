import 'package:flutter/services.dart';

/// Card networks we recognise from the number prefix.
enum CardBrand {
  visa('Visa', 16, 3),
  mastercard('Mastercard', 16, 3),
  amex('American Express', 15, 4),
  unionPay('UnionPay', 16, 3),
  unknown('Card', 16, 3);

  const CardBrand(this.label, this.length, this.cvvLength);

  final String label;
  final int length;
  final int cvvLength;

  static CardBrand detect(String digits) {
    if (digits.isEmpty) return unknown;
    if (digits.startsWith('4')) return visa;
    if (RegExp(r'^3[47]').hasMatch(digits)) return amex;
    if (RegExp(r'^62').hasMatch(digits)) return unionPay;
    if (RegExp(r'^(5[1-5]|222[1-9]|22[3-9]\d|2[3-6]\d{2}|27[01]\d|2720)').hasMatch(digits)) return mastercard;
    return unknown;
  }
}

abstract final class CardValidators {
  static String digitsOf(String v) => v.replaceAll(RegExp(r'\D'), '');

  /// Luhn checksum.
  static bool luhn(String digits) {
    if (digits.length < 12) return false;
    var sum = 0;
    var alt = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = digits.codeUnitAt(i) - 48;
      if (alt) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      alt = !alt;
    }
    return sum % 10 == 0;
  }

  static String? number(String? value) {
    final d = digitsOf(value ?? '');
    if (d.isEmpty) return 'Card number is required';
    final brand = CardBrand.detect(d);
    if (d.length != brand.length && !(brand == CardBrand.unknown && d.length >= 13 && d.length <= 19)) {
      return 'Enter the full card number';
    }
    if (!luhn(d)) return 'This card number isn\'t valid';
    return null;
  }

  /// `MM/YY`, not in the past. [now] for tests.
  static String? expiry(String? value, {DateTime? now}) {
    final v = (value ?? '').trim();
    final m = RegExp(r'^(\d{2})/(\d{2})$').firstMatch(v);
    if (m == null) return 'Use MM/YY';
    final month = int.parse(m.group(1)!);
    final year = 2000 + int.parse(m.group(2)!);
    if (month < 1 || month > 12) return 'Invalid month';
    final today = now ?? DateTime.now();
    // valid through the last day of the expiry month
    final end = DateTime(year, month + 1);
    if (!end.isAfter(today)) return 'This card has expired';
    if (year > today.year + 20) return 'Check the year';
    return null;
  }

  static String? cvv(String? value, CardBrand brand) {
    final d = digitsOf(value ?? '');
    if (d.length != brand.cvvLength) return '${brand.cvvLength} digits';
    return null;
  }
}

/// Groups card digits as you type: `4242 4242 4242 4242` (Amex `3782 822463 10005`).
class CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = CardValidators.digitsOf(newValue.text);
    final brand = CardBrand.detect(digits);
    final maxLen = brand == CardBrand.unknown ? 19 : brand.length;
    if (digits.length > maxLen) digits = digits.substring(0, maxLen);
    final groups = brand == CardBrand.amex ? const [4, 6, 5] : const [4, 4, 4, 4, 3];
    final buf = StringBuffer();
    var i = 0;
    for (final g in groups) {
      if (i >= digits.length) break;
      if (buf.isNotEmpty) buf.write(' ');
      final end = (i + g).clamp(0, digits.length);
      buf.write(digits.substring(i, end));
      i = end;
    }
    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// `MMYY` → `MM/YY` as you type.
class ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var digits = CardValidators.digitsOf(newValue.text);
    if (digits.length > 4) digits = digits.substring(0, 4);
    // "4" → "04/" feels natural for months 2-9
    if (digits.length == 1 && int.parse(digits) > 1) digits = '0$digits';
    final deleting = newValue.text.length < oldValue.text.length;
    final text = digits.length >= 3
        ? '${digits.substring(0, 2)}/${digits.substring(2)}'
        : (digits.length == 2 && !deleting ? '$digits/' : digits);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
