import 'package:flutter/foundation.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/utils/formatters.dart';

/// A category or brand Zel has noticed, with its share of your activity (0..1).
@immutable
class MemoryShare {
  const MemoryShare(this.name, this.share);

  factory MemoryShare.fromJson(Map<String, dynamic> j) {
    final raw = JsonX.asDouble(j['share']);
    return MemoryShare(JsonX.asString(j['name'] ?? j['label']), (raw > 1 ? raw / 100 : raw).clamp(0.0, 1.0));
  }

  final String name;
  final double share;
}

/// `GET /users/me/memory`: what Zelora remembers about the shopper, in plain
/// words plus the facts behind it.
@immutable
class ShoppingMemory {
  const ShoppingMemory({
    this.enabled = true,
    this.summary = const [],
    this.topCategories = const [],
    this.topBrands = const [],
    this.budgetLabel,
    this.recentSearches = const [],
    this.interactions = 0,
    this.searches = 0,
    this.chats = 0,
    this.lastActivityAt,
  });

  factory ShoppingMemory.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final band = JsonX.asMap(j['budgetBand']);
    final counts = JsonX.asMap(j['counts']);
    // other shapes: a flat `items` / `remembered` list of strings or { text, label }
    final rawItems = j['items'] ?? j['remembered'] ?? j['memories'];
    final extra = rawItems is List
        ? [
            for (final e in rawItems)
              if (e is Map) JsonX.asString(e['text'] ?? e['label'] ?? e['summary']) else JsonX.asString(e),
          ]
        : const <String>[];
    final budgetMin = JsonX.asDoubleOrNull(band['min']);
    final budgetMax = JsonX.asDoubleOrNull(band['max']);
    return ShoppingMemory(
      enabled: JsonX.asBool(j['enabled'], true),
      summary: [...JsonX.asStringList(j['summary']), ...extra].where((s) => s.trim().isNotEmpty).toList(),
      topCategories: JsonX.asList(j['topCategories'], MemoryShare.fromJson).where((s) => s.name.isNotEmpty).toList(),
      topBrands: JsonX.asList(j['topBrands'], MemoryShare.fromJson).where((s) => s.name.isNotEmpty).toList(),
      budgetLabel:
          JsonX.asStringOrNull(band['label']) ??
          (budgetMin != null && budgetMax != null ? '${Formatters.price(budgetMin)} to ${Formatters.price(budgetMax)}' : null),
      recentSearches: JsonX.asStringList(j['recentSearches']),
      interactions: JsonX.asInt(counts['interactions']),
      searches: JsonX.asInt(counts['searches']),
      chats: JsonX.asInt(counts['chats']),
      lastActivityAt: JsonX.asDate(j['lastActivityAt']),
    );
  }

  final bool enabled;

  /// Friendly sentences ("You browse mostly Smartphones and Laptops.").
  final List<String> summary;
  final List<MemoryShare> topCategories;
  final List<MemoryShare> topBrands;
  final String? budgetLabel;
  final List<String> recentSearches;
  final int interactions;
  final int searches;
  final int chats;
  final DateTime? lastActivityAt;

  /// Nothing learned yet (the server's own "nothing remembered" line doesn't count).
  bool get hasNothing =>
      topCategories.isEmpty &&
      topBrands.isEmpty &&
      budgetLabel == null &&
      recentSearches.isEmpty &&
      interactions == 0 &&
      searches == 0 &&
      chats == 0;

  ShoppingMemory copyWith({bool? enabled}) => ShoppingMemory(
    enabled: enabled ?? this.enabled,
    summary: summary,
    topCategories: topCategories,
    topBrands: topBrands,
    budgetLabel: budgetLabel,
    recentSearches: recentSearches,
    interactions: interactions,
    searches: searches,
    chats: chats,
    lastActivityAt: lastActivityAt,
  );

  /// The state right after "Forget everything".
  ShoppingMemory cleared() => ShoppingMemory(enabled: enabled);
}
