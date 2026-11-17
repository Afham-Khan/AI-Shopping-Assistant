import 'package:intl/intl.dart';

/// Display formatting for money, numbers and dates. Pure functions — easy to test.
abstract final class Formatters {
  static final _grouped = NumberFormat('#,##0', 'en_US');
  static final _compact = NumberFormat.compact(locale: 'en_US');
  static final _oneDecimal = NumberFormat('0.#', 'en_US');
  static final _day = DateFormat('MMM d', 'en_US');
  static final _date = DateFormat('MMM d, y', 'en_US');
  static final _dateTime = DateFormat('MMM d, y · h:mm a', 'en_US');
  static final _time = DateFormat('h:mm a', 'en_US');

  /// `45999` → `Rs 45,999` (PKR has no minor unit in this app).
  static String price(num? amount) => 'Rs ${_grouped.format((amount ?? 0).round())}';

  /// `279999` → `Rs 280K`, for tight spaces (chips, sliders).
  static String priceCompact(num? amount) => 'Rs ${_compact.format(amount ?? 0)}';

  /// `12800` → `12.8K`.
  static String compact(num? value) => _compact.format(value ?? 0);

  /// `1234` → `1,234`.
  static String number(num? value) => _grouped.format(value ?? 0);

  /// `4.567` → `4.6`, `4.0` → `4`.
  static String rating(num? value) => _oneDecimal.format(((value ?? 0) * 10).round() / 10);

  /// `9.7` → `-10%` (discount badge).
  static String discount(num? percent) => '-${(percent ?? 0).round()}%';

  /// `0.87` → `87%` (match score).
  static String percentFromRatio(num? ratio) => '${((ratio ?? 0) * 100).round()}%';

  /// `Nov 17, 2026`.
  static String date(DateTime? value) => value == null ? '' : _date.format(value.toLocal());

  /// `Nov 17, 2026 · 3:05 PM`.
  static String dateTime(DateTime? value) => value == null ? '' : _dateTime.format(value.toLocal());

  /// `3:05 PM`.
  static String time(DateTime? value) => value == null ? '' : _time.format(value.toLocal());

  /// Human relative time: `Just now`, `5m ago`, `3h ago`, `Yesterday`,
  /// `4d ago`, `Nov 12`, `Nov 12, 2025`. Pass [now] in tests.
  static String relative(DateTime? value, {DateTime? now}) {
    if (value == null) return '';
    final local = value.toLocal();
    final current = (now ?? DateTime.now()).toLocal();
    final diff = current.difference(local);

    if (diff.isNegative || diff.inSeconds < 45) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes < 1 ? 1 : diff.inMinutes}m ago';
    if (diff.inHours < 24 && local.day == current.day) return '${diff.inHours}h ago';

    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);
    final days = today.difference(day).inDays;
    if (days == 1) return 'Yesterday';
    if (days < 7) return '${days}d ago';
    if (local.year == current.year) return _day.format(local);
    return _date.format(local);
  }

  /// `1` → `1 item`, `3` → `3 items`.
  static String plural(int count, String singular, [String? plural]) =>
      '$count ${count == 1 ? singular : (plural ?? '${singular}s')}';

  /// Parses an ISO string safely (null on bad input).
  static DateTime? parseDate(Object? value) => value is String ? DateTime.tryParse(value) : null;
}
