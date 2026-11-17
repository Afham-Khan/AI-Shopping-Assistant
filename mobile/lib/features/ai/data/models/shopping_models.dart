import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';
import '../../../../core/models/product.dart';

/// Parses one recommended product leniently. Accepts a plain card
/// (`{ id, title, …, match }`) or a wrapper (`{ product, score, reasons }`).
ProductSummary parseRecommended(Map<String, dynamic> j) {
  final inner = JsonX.asMapOrNull(j['product']);
  if (inner == null) return ProductSummary.fromJson(j);
  final reasons = j['reasons'];
  final hasMatch = inner['match'] is Map;
  return ProductSummary.fromJson({
    ...inner,
    if (!hasMatch && (j['score'] != null || reasons is List)) 'match': {'score': j['score'] ?? 0, 'reasons': reasons ?? const []},
  });
}

List<ProductSummary> parseRecommendedList(Object? v) =>
    JsonX.asList(v, parseRecommended).where((p) => p.id != 0).toList();

/// "womens-shoes" → "Shoes": the short role label shown on an outfit card.
String lookRoleFor({String? categorySlug, String? categoryName}) {
  switch (categorySlug) {
    case 'womens-shoes':
    case 'mens-shoes':
      return 'Shoes';
    case 'womens-bags':
      return 'Bag';
    case 'womens-jewellery':
      return 'Jewellery';
    case 'womens-watches':
    case 'mens-watches':
      return 'Watch';
    case 'sunglasses':
      return 'Sunglasses';
    case 'fragrances':
      return 'Fragrance';
    case 'womens-dresses':
      return 'Dress';
    case 'tops':
      return 'Top';
    case 'mens-shirts':
      return 'Shirt';
  }
  final name = categoryName?.trim();
  return name == null || name.isEmpty ? 'Accessory' : name;
}

const _fashionCategories = {
  'mens-shirts',
  'mens-shoes',
  'mens-watches',
  'tops',
  'womens-dresses',
  'womens-shoes',
  'womens-bags',
  'womens-jewellery',
  'womens-watches',
  'sunglasses',
};

/// Complete-the-look only makes sense for fashion items.
bool isFashionProduct({String? departmentSlug, String? categorySlug}) =>
    (departmentSlug ?? '').contains('fashion') || _fashionCategories.contains(categorySlug);

/// One piece of an outfit with the role it plays ("Bag", "Shoes"…).
@immutable
class LookItem {
  const LookItem({required this.role, required this.product, this.alternatives = const []});

  final String role;
  final ProductSummary product;
  final List<ProductSummary> alternatives;
}

/// `GET /ai/complete-look/:productId`.
///
/// Accepts a bare list of recommended products, or
/// `{ title, kind, palette, look: [{ role, item | product, alternatives }], items }`.
@immutable
class CompleteLook {
  const CompleteLook({this.title = 'Complete the look', this.kind = 'outfit', this.items = const [], this.paletteTip});

  factory CompleteLook.fromJson(Object? data) {
    if (data is List) return CompleteLook(items: _flat(data, <int>{}));
    final j = JsonX.asMap(data);
    final out = <LookItem>[];
    final seen = <int>{};

    for (final row in JsonX.asList(j['look'], (m) => m)) {
      final item = JsonX.asMapOrNull(row['item']) ?? row;
      final product = parseRecommended(item);
      if (product.id == 0 || !seen.add(product.id)) continue;
      final category = JsonX.asMap(row['category']);
      out.add(
        LookItem(
          role: JsonX.asStringOrNull(row['role']) ??
              lookRoleFor(
                categorySlug: JsonX.asStringOrNull(category['slug']) ?? product.category?.slug,
                categoryName: JsonX.asStringOrNull(category['name']) ?? product.category?.name,
              ),
          product: product,
          alternatives: parseRecommendedList(row['alternatives']),
        ),
      );
    }
    // flat items (or `products`) after the role rows: strong runners-up
    out.addAll(_flat(j['items'] ?? j['products'], seen));

    final palette = JsonX.asMap(j['palette']);
    return CompleteLook(
      title: JsonX.asStringOrNull(j['title']) ?? 'Complete the look',
      kind: JsonX.asStringOrNull(j['kind']) ?? 'outfit',
      items: out.take(8).toList(),
      paletteTip: JsonX.asStringOrNull(palette['tip'] ?? j['tip']),
    );
  }

  static List<LookItem> _flat(Object? v, Set<int> seen) => [
    for (final p in parseRecommendedList(v))
      if (seen.add(p.id))
        LookItem(role: lookRoleFor(categorySlug: p.category?.slug, categoryName: p.category?.name), product: p),
  ];

  final String title;

  /// `outfit` for fashion items; `complementary` when the server fell back to
  /// "goes well with" (the page already has Bought together for that).
  final String kind;
  final List<LookItem> items;

  /// One styling tip about the colours ("Black is a neutral base…").
  final String? paletteTip;

  bool get isOutfit => kind != 'complementary' && items.isNotEmpty;

  List<ProductSummary> get products => [for (final i in items) i.product];

  /// Sum of the in-stock picks.
  double get total => items.where((i) => i.product.inStock).fold(0, (sum, i) => sum + i.product.price);
}

/// 1..5 → "Basic" … "Excellent".
String specLevelLabel(int level) => switch (level) {
  1 => 'Basic',
  2 => 'Fair',
  3 => 'Good',
  4 => 'Great',
  5 => 'Excellent',
  _ => '',
};

/// One spec in plain words: what it is, what it means, and a 1..5 level.
@immutable
class SpecExplanation {
  const SpecExplanation({
    required this.label,
    required this.value,
    this.meaning = '',
    this.headline,
    this.level = 0,
    this.levelLabel,
    this.scale,
  });

  factory SpecExplanation.fromJson(Map<String, dynamic> j) {
    final level = JsonX.asInt(j['level']).clamp(0, 5);
    return SpecExplanation(
      label: JsonX.asString(j['label'] ?? j['key'] ?? j['name']),
      value: JsonX.asString(j['value']),
      meaning: JsonX.asString(j['meaning'] ?? j['explanation'] ?? j['plain']),
      headline: JsonX.asStringOrNull(j['title']),
      level: level,
      levelLabel: JsonX.asStringOrNull(j['levelLabel']) ?? (level == 0 ? null : specLevelLabel(level)),
      scale: JsonX.asStringOrNull(j['scale']),
    );
  }

  final String label;
  final String value;

  /// "Good for students and office work: browsing, documents, video calls."
  final String meaning;

  /// Server-written one-liner ("8 GB RAM: smooth everyday use"), if any.
  final String? headline;

  /// 0 = not rated.
  final int level;
  final String? levelLabel;

  /// What the bar measures ("Multitasking").
  final String? scale;

  bool get isRated => level >= 1 && level <= 5;
}

/// `GET /ai/explain/:productId` (also `meta.explain` in a chat reply).
@immutable
class SpecExplainer {
  const SpecExplainer({
    this.productTitle,
    this.summary = '',
    this.whoFor = const [],
    this.specs = const [],
    this.others = const [],
    this.overallLevel,
    this.overallLabel,
  });

  factory SpecExplainer.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final product = JsonX.asMap(j['product']);
    final who = j['whoItsFor'] ?? j['whoFor'] ?? j['who'];
    final overall = JsonX.asMap(j['overall']);
    final specs = JsonX.asList(j['specs'], SpecExplanation.fromJson).where((s) => s.label.isNotEmpty).toList();
    return SpecExplainer(
      productTitle: JsonX.asStringOrNull(product['title'] ?? j['title']),
      // "who it's for" may be a sentence or a list of personas
      summary: JsonX.asString(j['summary'] ?? (who is String ? who : null)),
      whoFor: who is List ? JsonX.asStringList(who) : const [],
      specs: specs,
      others: [
        for (final o in JsonX.asList(j['others'], (m) => m))
          MapEntry(JsonX.asString(o['key'] ?? o['label']), JsonX.asString(o['value'])),
      ].where((e) => e.key.isNotEmpty && e.value.isNotEmpty).toList(),
      overallLevel: JsonX.asDoubleOrNull(overall['level']),
      overallLabel: JsonX.asStringOrNull(overall['label']),
    );
  }

  final String? productTitle;

  /// The "Who it's for" paragraph.
  final String summary;
  final List<String> whoFor;
  final List<SpecExplanation> specs;

  /// Specs the server could not explain: plain key/value.
  final List<MapEntry<String, String>> others;
  final double? overallLevel;
  final String? overallLabel;

  bool get isEmpty => specs.isEmpty && summary.isEmpty;

  /// The strongest rated specs, for the compact chat card.
  List<SpecExplanation> get highlights {
    final rated = specs.where((s) => s.isRated).toList()..sort((a, b) => b.level.compareTo(a.level));
    return rated.take(3).toList();
  }
}

/// `POST /ai/gift` → `{ title, products | items, note }`.
@immutable
class GiftResult {
  const GiftResult({required this.title, this.note = '', this.products = const []});

  factory GiftResult.fromJson(Object? data) {
    if (data is List) return GiftResult(title: 'Gift ideas', products: parseRecommendedList(data));
    final j = JsonX.asMap(data);
    return GiftResult(
      title: JsonX.asStringOrNull(j['title']) ?? 'Gift ideas',
      note: JsonX.asString(j['note'] ?? j['summary']),
      products: parseRecommendedList(j['products'] ?? j['items']),
    );
  }

  final String title;
  final String note;
  final List<ProductSummary> products;

  bool get isEmpty => products.isEmpty;
}
