import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';
import '../../../../core/models/product.dart';

/// A category inside a department (`/catalog/departments`).
@immutable
class CategorySummary {
  const CategorySummary({
    required this.id,
    required this.name,
    required this.slug,
    this.imageUrl,
    this.productCount = 0,
  });

  factory CategorySummary.fromJson(Map<String, dynamic> json) => CategorySummary(
    id: JsonX.asInt(json['id']),
    name: JsonX.asString(json['name']),
    slug: JsonX.asString(json['slug']),
    imageUrl: JsonX.asStringOrNull(json['imageUrl']),
    productCount: JsonX.asInt(json['productCount']),
  );

  final int id;
  final String name;
  final String slug;
  final String? imageUrl;
  final int productCount;
}

@immutable
class Department {
  const Department({
    required this.id,
    required this.name,
    required this.slug,
    this.icon,
    this.imageUrl,
    this.description,
    this.productCount = 0,
    this.categories = const [],
  });

  factory Department.fromJson(Map<String, dynamic> json) => Department(
    id: JsonX.asInt(json['id']),
    name: JsonX.asString(json['name']),
    slug: JsonX.asString(json['slug']),
    icon: JsonX.asStringOrNull(json['icon']),
    imageUrl: JsonX.asStringOrNull(json['imageUrl']),
    description: JsonX.asStringOrNull(json['description']),
    productCount: JsonX.asInt(json['productCount']),
    categories: JsonX.asList(json['categories'], CategorySummary.fromJson),
  );

  final int id;
  final String name;
  final String slug;

  /// Material icon name stored by the backend (see `CategoryIcons.of`).
  final String? icon;
  final String? imageUrl;
  final String? description;
  final int productCount;
  final List<CategorySummary> categories;
}

@immutable
class BrandFacet {
  const BrandFacet({required this.name, required this.count});

  factory BrandFacet.fromJson(Map<String, dynamic> json) =>
      BrandFacet(name: JsonX.asString(json['name']), count: JsonX.asInt(json['count']));

  final String name;
  final int count;
}

@immutable
class PriceRange {
  const PriceRange({required this.min, required this.max});

  static PriceRange? fromJsonOrNull(Object? json) {
    final map = JsonX.asMapOrNull(json);
    if (map == null || map['min'] == null || map['max'] == null) return null;
    return PriceRange(min: JsonX.asDouble(map['min']), max: JsonX.asDouble(map['max']));
  }

  final double min;
  final double max;

  bool get isUsable => max > min;
}

/// `meta.facets` of `GET /products`.
@immutable
class ProductFacets {
  const ProductFacets({this.brands = const [], this.priceRange});

  factory ProductFacets.fromMeta(Map<String, dynamic> meta) {
    final facets = JsonX.asMap(meta['facets']);
    return ProductFacets(
      brands: JsonX.asList(facets['brands'], BrandFacet.fromJson),
      priceRange: PriceRange.fromJsonOrNull(facets['priceRange']),
    );
  }

  final List<BrandFacet> brands;
  final PriceRange? priceRange;
}

/// `GET /catalog/categories/:slug`.
@immutable
class CategoryInfo {
  const CategoryInfo({
    required this.id,
    required this.name,
    required this.slug,
    this.description,
    this.imageUrl,
    this.department,
    this.brands = const [],
    this.priceRange,
  });

  factory CategoryInfo.fromJson(Map<String, dynamic> json) {
    final dept = JsonX.asMapOrNull(json['department']);
    return CategoryInfo(
      id: JsonX.asInt(json['id']),
      name: JsonX.asString(json['name']),
      slug: JsonX.asString(json['slug']),
      description: JsonX.asStringOrNull(json['description']),
      imageUrl: JsonX.asStringOrNull(json['imageUrl']),
      department: dept == null ? null : NamedRef.fromJson(dept),
      brands: JsonX.asList(json['brands'], BrandFacet.fromJson),
      priceRange: PriceRange.fromJsonOrNull(json['priceRange']),
    );
  }

  final int id;
  final String name;
  final String slug;
  final String? description;
  final String? imageUrl;
  final NamedRef? department;
  final List<BrandFacet> brands;
  final PriceRange? priceRange;
}

/// Where a banner / promo notification leads.
@immutable
class BannerTarget {
  const BannerTarget({required this.type, this.value});

  factory BannerTarget.fromJson(Map<String, dynamic> json) =>
      BannerTarget(type: JsonX.asString(json['type']), value: JsonX.asStringOrNull(json['value']));

  /// `category` | `department` | `search` | `assistant` (unknown types are ignored).
  final String type;
  final String? value;
}

@immutable
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.ctaLabel,
    this.target,
    this.theme,
  });

  factory HomeBanner.fromJson(Map<String, dynamic> json) {
    final target = JsonX.asMapOrNull(json['target']);
    return HomeBanner(
      id: JsonX.asInt(json['id']),
      title: JsonX.asString(json['title']),
      subtitle: JsonX.asStringOrNull(json['subtitle']),
      imageUrl: JsonX.asStringOrNull(json['imageUrl']),
      ctaLabel: JsonX.asStringOrNull(json['ctaLabel']),
      target: target == null ? null : BannerTarget.fromJson(target),
      theme: JsonX.asStringOrNull(json['theme']),
    );
  }

  final int id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? ctaLabel;
  final BannerTarget? target;

  /// indigo | violet | rose | emerald | amber …
  final String? theme;
}

/// `GET /catalog/home`.
@immutable
class HomeFeed {
  const HomeFeed({
    this.banners = const [],
    this.departments = const [],
    this.flashDeals = const [],
    this.trending = const [],
    this.topRated = const [],
    this.newArrivals = const [],
    this.dealEndsAt,
  });

  factory HomeFeed.fromJson(Map<String, dynamic> json) => HomeFeed(
    banners: JsonX.asList(json['banners'], HomeBanner.fromJson),
    departments: JsonX.asList(json['departments'], Department.fromJson),
    flashDeals: JsonX.asList(json['flashDeals'], ProductSummary.fromJson),
    trending: JsonX.asList(json['trending'], ProductSummary.fromJson),
    topRated: JsonX.asList(json['topRated'], ProductSummary.fromJson),
    newArrivals: JsonX.asList(json['newArrivals'], ProductSummary.fromJson),
    dealEndsAt: JsonX.asDate(json['dealEndsAt']),
  );

  final List<HomeBanner> banners;
  final List<Department> departments;
  final List<ProductSummary> flashDeals;
  final List<ProductSummary> trending;
  final List<ProductSummary> topRated;
  final List<ProductSummary> newArrivals;
  final DateTime? dealEndsAt;
}
