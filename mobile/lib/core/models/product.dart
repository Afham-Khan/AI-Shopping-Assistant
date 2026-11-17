import 'package:flutter/foundation.dart';

import 'json_utils.dart';

/// `{ id, name, slug }` — category / department / brand references.
@immutable
class NamedRef {
  const NamedRef({required this.id, required this.name, required this.slug});

  factory NamedRef.fromJson(Map<String, dynamic> json) => NamedRef(
    id: JsonX.asInt(json['id']),
    name: JsonX.asString(json['name']),
    slug: JsonX.asString(json['slug']),
  );

  final int id;
  final String name;
  final String slug;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'slug': slug};

  @override
  bool operator ==(Object other) => other is NamedRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Why the AI recommended a product: `{ score: 0.87, reasons: [...] }`.
@immutable
class ProductMatch {
  const ProductMatch({required this.score, this.reasons = const []});

  factory ProductMatch.fromJson(Map<String, dynamic> json) => ProductMatch(
    score: JsonX.asDouble(json['score']),
    reasons: JsonX.asStringList(json['reasons']),
  );

  /// 0..1
  final double score;
  final List<String> reasons;

  Map<String, dynamic> toJson() => {'score': score, 'reasons': reasons};
}

/// The API's `ProductCard` shape (lists, grids, rails, wishlist, cart lines).
///
/// `RecommendedProduct` is the same object plus [match]. The product-detail
/// model (commerce feature) should extend or compose this one.
@immutable
class ProductSummary {
  const ProductSummary({
    required this.id,
    required this.title,
    required this.slug,
    required this.price,
    this.brand,
    this.category,
    this.compareAtPrice,
    this.discountPercent = 0,
    this.rating = 0,
    this.ratingCount = 0,
    this.stock = 0,
    this.inStock = true,
    this.thumbnail,
    this.tags = const [],
    this.match,
  });

  factory ProductSummary.fromJson(Map<String, dynamic> json) {
    final category = JsonX.asMapOrNull(json['category']);
    final match = JsonX.asMapOrNull(json['match']);
    return ProductSummary(
      id: JsonX.asInt(json['id']),
      title: JsonX.asString(json['title']),
      slug: JsonX.asString(json['slug']),
      brand: JsonX.asStringOrNull(json['brand']),
      category: category == null ? null : NamedRef.fromJson(category),
      price: JsonX.asDouble(json['price']),
      compareAtPrice: JsonX.asDoubleOrNull(json['compareAtPrice']),
      discountPercent: JsonX.asDouble(json['discountPercent']),
      rating: JsonX.asDouble(json['rating']),
      ratingCount: JsonX.asInt(json['ratingCount']),
      stock: JsonX.asInt(json['stock']),
      inStock: JsonX.asBool(json['inStock'], true),
      thumbnail: JsonX.asStringOrNull(json['thumbnail']),
      tags: JsonX.asStringList(json['tags']),
      match: match == null ? null : ProductMatch.fromJson(match),
    );
  }

  final int id;
  final String title;
  final String slug;
  final String? brand;
  final NamedRef? category;
  final double price;
  final double? compareAtPrice;
  final double discountPercent;
  final double rating;
  final int ratingCount;
  final int stock;
  final bool inStock;

  /// May be server-relative — render with `AppNetworkImage`, which resolves it.
  final String? thumbnail;
  final List<String> tags;

  /// Present on AI recommendations only.
  final ProductMatch? match;

  bool get hasDiscount => compareAtPrice != null && compareAtPrice! > price;

  /// Discount from the API, or computed from the prices as a fallback.
  double get effectiveDiscount {
    if (discountPercent > 0) return discountPercent;
    if (!hasDiscount) return 0;
    return (compareAtPrice! - price) / compareAtPrice! * 100;
  }

  bool get isLowStock => inStock && stock > 0 && stock <= 5;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'slug': slug,
    'brand': brand,
    'category': category?.toJson(),
    'price': price,
    'compareAtPrice': compareAtPrice,
    'discountPercent': discountPercent,
    'rating': rating,
    'ratingCount': ratingCount,
    'stock': stock,
    'inStock': inStock,
    'thumbnail': thumbnail,
    'tags': tags,
    if (match != null) 'match': match!.toJson(),
  };

  @override
  bool operator ==(Object other) => other is ProductSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
