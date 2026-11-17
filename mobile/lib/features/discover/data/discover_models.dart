import 'package:flutter/foundation.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/models/product.dart';

/// The three answers a card can get. `value` is the API's spelling.
enum SwipeAction {
  like('like', 'Like'),
  pass('pass', 'Pass'),
  bag('bag', 'Bag');

  const SwipeAction(this.value, this.label);

  final String value;
  final String label;

  bool get positive => this != pass;
}

/// `{ name, share }` — one category's share of what the shopper keeps.
@immutable
class TasteShare {
  const TasteShare({required this.name, required this.share, this.slug});

  factory TasteShare.fromJson(Map<String, dynamic> j) => TasteShare(
    name: JsonX.asString(j['name'] ?? j['label'] ?? j['slug']),
    slug: JsonX.asStringOrNull(j['slug']),
    // accept 0..1 or 0..100
    share: _ratio(JsonX.asDouble(j['share'] ?? j['value'])),
  );

  final String name;
  final String? slug;

  /// 0..1
  final double share;

  static double _ratio(double v) => (v > 1 ? v / 100 : v).clamp(0.0, 1.0);
}

@immutable
class PriceAppetite {
  const PriceAppetite({this.min = 0, this.max = 0, this.avg = 0});

  factory PriceAppetite.fromJson(Map<String, dynamic> j) => PriceAppetite(
    min: JsonX.asDouble(j['min']),
    max: JsonX.asDouble(j['max']),
    avg: JsonX.asDouble(j['avg'] ?? j['average'] ?? j['median']),
  );

  final double min;
  final double max;
  final double avg;

  bool get isEmpty => max <= 0;
}

/// What the deck has learned so far (`taste` in the swipe response, or the
/// local estimate until the server answers).
@immutable
class TasteProfile {
  const TasteProfile({
    this.categories = const [],
    this.priceAppetite = const PriceAppetite(),
    this.confidence = 0,
    this.topSignals = const [],
  });

  factory TasteProfile.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final signals = j['topSignals'] is List ? j['topSignals'] as List : const [];
    return TasteProfile(
      categories: JsonX.asList(j['categories'], TasteShare.fromJson).where((c) => c.name.isNotEmpty).toList(),
      priceAppetite: PriceAppetite.fromJson(JsonX.asMap(j['priceAppetite'])),
      confidence: TasteShare._ratio(JsonX.asDouble(j['confidence'])),
      topSignals: [
        for (final s in signals)
          if (s is Map) JsonX.asString(s['label'] ?? s['name'] ?? s['text']) else JsonX.asString(s),
      ].where((s) => s.isNotEmpty).toList(),
    );
  }

  static const empty = TasteProfile();

  final List<TasteShare> categories;
  final PriceAppetite priceAppetite;

  /// 0..1
  final double confidence;
  final List<String> topSignals;

  bool get isEmpty => categories.isEmpty && priceAppetite.isEmpty;
}

/// `POST /discover/swipe` → `{ taste, next }`.
@immutable
class SwipeResponse {
  const SwipeResponse({this.taste, this.next = const []});

  factory SwipeResponse.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    return SwipeResponse(
      taste: j['taste'] is Map ? TasteProfile.fromJson(j['taste']) : null,
      next: JsonX.asList(j['next'], ProductSummary.fromJson).where((p) => p.id != 0).toList(),
    );
  }

  final TasteProfile? taste;
  final List<ProductSummary> next;
}

/// One department story (`GET /discover/reels`).
@immutable
class DiscoverReel {
  const DiscoverReel({
    required this.department,
    required this.slug,
    required this.headline,
    required this.products,
    this.coverImage,
  });

  factory DiscoverReel.fromJson(Map<String, dynamic> j) {
    final dept = j['department'];
    final name = dept is Map ? JsonX.asString(dept['name']) : JsonX.asString(dept);
    final slug = JsonX.asString(j['slug'] ?? (dept is Map ? dept['slug'] : null));
    return DiscoverReel(
      department: name.isEmpty ? slug : name,
      slug: slug,
      headline: JsonX.asString(j['headline'] ?? j['title'], 'Fresh picks in $name'),
      products: JsonX.asList(j['products'], ProductSummary.fromJson).where((p) => p.id != 0).toList(),
      coverImage: JsonX.asStringOrNull(j['coverImage']),
    );
  }

  final String department;
  final String slug;
  final String headline;
  final List<ProductSummary> products;

  /// Optional story cover; the first product's cut-out otherwise.
  final String? coverImage;

  String? get cover => coverImage ?? (products.isEmpty ? null : products.first.thumbnail);
}
