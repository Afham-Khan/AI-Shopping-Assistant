import 'package:flutter/foundation.dart';

/// Sort options of `GET /products`.
enum ProductSort {
  relevance('relevance', 'Most relevant'),
  popular('popular', 'Most popular'),
  newest('newest', 'Newest first'),
  rating('rating', 'Top rated'),
  priceAsc('price_asc', 'Price: low to high'),
  priceDesc('price_desc', 'Price: high to low'),
  discount('discount', 'Biggest discount');

  const ProductSort(this.value, this.label);

  final String value;
  final String label;

  static ProductSort? parse(String? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return null;
  }
}

/// Immutable filter set for the products list — used as a provider family key,
/// so it implements value equality.
@immutable
class ProductQuery {
  const ProductQuery({
    this.q,
    this.category,
    this.department,
    this.brands = const [],
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.inStock = false,
    this.onSale = false,
    this.sort,
  });

  final String? q;
  final String? category;
  final String? department;
  final List<String> brands;
  final double? minPrice;
  final double? maxPrice;
  final double? minRating;
  final bool inStock;
  final bool onSale;
  final ProductSort? sort;

  /// Sort shown in the UI when none is chosen (search ranks by relevance).
  ProductSort get effectiveSort => sort ?? ((q?.isNotEmpty ?? false) ? ProductSort.relevance : ProductSort.popular);

  bool get hasPrice => minPrice != null || maxPrice != null;

  /// Number of user-adjustable filters in effect (badge on the Filter button).
  int get activeFilterCount =>
      brands.length + (hasPrice ? 1 : 0) + (minRating != null ? 1 : 0) + (inStock ? 1 : 0) + (onSale ? 1 : 0);

  Map<String, dynamic> toQuery({int page = 1, int limit = 24}) => {
    'q': q,
    'category': category,
    'department': department,
    'brand': brands,
    'minPrice': minPrice?.round(),
    'maxPrice': maxPrice?.round(),
    'minRating': minRating,
    'inStock': inStock ? true : null,
    'onSale': onSale ? true : null,
    'sort': sort?.value,
    'page': page,
    'limit': limit,
  };

  ProductQuery copyWith({
    List<String>? brands,
    double? Function()? minPrice,
    double? Function()? maxPrice,
    double? Function()? minRating,
    bool? inStock,
    bool? onSale,
    ProductSort? Function()? sort,
  }) {
    return ProductQuery(
      q: q,
      category: category,
      department: department,
      brands: brands ?? this.brands,
      minPrice: minPrice == null ? this.minPrice : minPrice(),
      maxPrice: maxPrice == null ? this.maxPrice : maxPrice(),
      minRating: minRating == null ? this.minRating : minRating(),
      inStock: inStock ?? this.inStock,
      onSale: onSale ?? this.onSale,
      sort: sort == null ? this.sort : sort(),
    );
  }

  /// Keeps the scope (q/category/department) and sort, drops filters.
  ProductQuery clearFilters() => ProductQuery(q: q, category: category, department: department, sort: sort);

  @override
  bool operator ==(Object other) =>
      other is ProductQuery &&
      other.q == q &&
      other.category == category &&
      other.department == department &&
      listEquals(other.brands, brands) &&
      other.minPrice == minPrice &&
      other.maxPrice == maxPrice &&
      other.minRating == minRating &&
      other.inStock == inStock &&
      other.onSale == onSale &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    q,
    category,
    department,
    Object.hashAll(brands),
    minPrice,
    maxPrice,
    minRating,
    inStock,
    onSale,
    sort,
  );
}
