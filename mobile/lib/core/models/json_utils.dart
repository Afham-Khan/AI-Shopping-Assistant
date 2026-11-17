/// Lenient JSON readers for hand-written `fromJson` factories.
///
/// The API is typed, but numbers can arrive as int/double/string (e.g.
/// Postgres DECIMAL → "4.60"). These never throw on a type mismatch.
abstract final class JsonX {
  static int asInt(Object? v, [int fallback = 0]) => switch (v) {
    final int i => i,
    final num n => n.toInt(),
    final String s => int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? fallback,
    _ => fallback,
  };

  static int? asIntOrNull(Object? v) => v == null ? null : asInt(v);

  static double asDouble(Object? v, [double fallback = 0]) => switch (v) {
    final num n => n.toDouble(),
    final String s => double.tryParse(s) ?? fallback,
    _ => fallback,
  };

  static double? asDoubleOrNull(Object? v) => v == null ? null : asDouble(v);

  static String asString(Object? v, [String fallback = '']) => v?.toString() ?? fallback;

  static String? asStringOrNull(Object? v) {
    final s = v?.toString();
    return (s == null || s.isEmpty) ? null : s;
  }

  static bool asBool(Object? v, [bool fallback = false]) => switch (v) {
    final bool b => b,
    final num n => n != 0,
    final String s => s == 'true' || s == '1',
    _ => fallback,
  };

  static DateTime? asDate(Object? v) => v is String ? DateTime.tryParse(v) : null;

  static List<String> asStringList(Object? v) =>
      v is List ? [for (final e in v) if (e != null) e.toString()] : const [];

  static Map<String, dynamic> asMap(Object? v) =>
      v is Map ? Map<String, dynamic>.from(v) : const {};

  static Map<String, dynamic>? asMapOrNull(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

  /// Decodes a list of objects, skipping malformed entries.
  static List<T> asList<T>(Object? v, T Function(Map<String, dynamic>) item) => v is List
      ? [for (final e in v) if (e is Map) item(Map<String, dynamic>.from(e))]
      : <T>[];
}
