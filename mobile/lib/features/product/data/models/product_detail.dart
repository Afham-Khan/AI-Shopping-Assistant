import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';
import '../../../../core/models/product.dart';

/// `GET /products/:idOrSlug` — the card fields ([summary]) plus details.
@immutable
class ProductDetail {
  const ProductDetail({
    required this.summary,
    this.description,
    this.department,
    this.images = const [],
    this.highlights = const [],
    this.specs = const [],
    this.color,
    this.warranty,
    this.shippingInfo,
    this.returnPolicy,
    this.soldCount = 0,
    this.ratingBreakdown = const {},
  });

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    final dept = JsonX.asMapOrNull(json['department']);
    final specs = JsonX.asMap(json['specs']);
    final breakdown = JsonX.asMap(json['ratingBreakdown']);
    return ProductDetail(
      summary: ProductSummary.fromJson(json),
      description: JsonX.asStringOrNull(json['description']),
      department: dept == null ? null : NamedRef.fromJson(dept),
      images: JsonX.asStringList(json['images']),
      highlights: JsonX.asStringList(json['highlights']),
      // a JSON object keeps insertion order in Dart maps
      specs: [
        for (final e in specs.entries)
          if (e.value != null && '${e.value}'.isNotEmpty) MapEntry(e.key, '${e.value}'),
      ],
      color: JsonX.asStringOrNull(json['color']),
      warranty: JsonX.asStringOrNull(json['warranty']),
      shippingInfo: JsonX.asStringOrNull(json['shippingInfo']),
      returnPolicy: JsonX.asStringOrNull(json['returnPolicy']),
      soldCount: JsonX.asInt(json['soldCount']),
      ratingBreakdown: {for (var star = 1; star <= 5; star++) star: JsonX.asInt(breakdown['$star'])},
    );
  }

  final ProductSummary summary;
  final String? description;
  final NamedRef? department;
  final List<String> images;
  final List<String> highlights;

  /// Ordered key → value pairs.
  final List<MapEntry<String, String>> specs;
  final String? color;
  final String? warranty;
  final String? shippingInfo;
  final String? returnPolicy;
  final int soldCount;

  /// star (1-5) → count.
  final Map<int, int> ratingBreakdown;

  int get id => summary.id;

  /// Gallery images, falling back to the thumbnail.
  List<String> get gallery {
    if (images.isNotEmpty) return images;
    final thumb = summary.thumbnail;
    return thumb == null ? const [] : [thumb];
  }
}

/// One review (`GET /products/:id/reviews`).
@immutable
class Review {
  const Review({
    required this.id,
    required this.rating,
    required this.comment,
    this.title,
    this.isVerified = false,
    this.helpfulCount = 0,
    this.createdAt,
    this.userName = 'Shopper',
    this.userInitials = '?',
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    final user = JsonX.asMap(json['user']);
    return Review(
      id: JsonX.asInt(json['id']),
      rating: JsonX.asInt(json['rating']),
      title: JsonX.asStringOrNull(json['title']),
      comment: JsonX.asString(json['comment']),
      isVerified: JsonX.asBool(json['isVerified']),
      helpfulCount: JsonX.asInt(json['helpfulCount']),
      createdAt: JsonX.asDate(json['createdAt']),
      userName: JsonX.asString(user['name'], 'Shopper'),
      userInitials: JsonX.asString(user['initials'], '?'),
    );
  }

  final int id;
  final int rating;
  final String? title;
  final String comment;
  final bool isVerified;
  final int helpfulCount;
  final DateTime? createdAt;
  final String userName;
  final String userInitials;
}

/// `meta.summary` of the reviews endpoint.
@immutable
class ReviewStats {
  const ReviewStats({this.average = 0, this.count = 0, this.breakdown = const {}});

  factory ReviewStats.fromMeta(Map<String, dynamic> meta) {
    final s = JsonX.asMap(meta['summary']);
    final b = JsonX.asMap(s['breakdown']);
    return ReviewStats(
      average: JsonX.asDouble(s['average']),
      count: JsonX.asInt(s['count']),
      breakdown: {for (var star = 1; star <= 5; star++) star: JsonX.asInt(b['$star'])},
    );
  }

  final double average;
  final int count;
  final Map<int, int> breakdown;
}

enum ReviewSort {
  recent('recent', 'Most recent'),
  helpful('helpful', 'Most helpful'),
  ratingHigh('rating_high', 'Highest rating'),
  ratingLow('rating_low', 'Lowest rating');

  const ReviewSort(this.value, this.label);

  final String value;
  final String label;
}
