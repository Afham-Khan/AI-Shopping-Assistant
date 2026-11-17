import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';

/// One recorded price: the price that held from [at] until the next point.
@immutable
class PricePoint {
  const PricePoint({required this.at, required this.price, this.compareAt});

  factory PricePoint.fromJson(Map<String, dynamic> j) => PricePoint(
    at: JsonX.asDate(j['recordedAt'] ?? j['at'] ?? j['date'] ?? j['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    price: JsonX.asDouble(j['price']),
    compareAt: JsonX.asDoubleOrNull(j['compareAtPrice']),
  );

  final DateTime at;
  final double price;
  final double? compareAt;
}

/// `GET /products/:id/price-history?days=90` — only real recorded changes.
@immutable
class PriceHistory {
  const PriceHistory({
    required this.currentPrice,
    this.days = 90,
    this.points = const [],
    this.lowest,
    this.highest,
    this.average,
    this.trend = 'flat',
    this.insight,
  });

  factory PriceHistory.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final stats = JsonX.asMap(j['stats']);
    final current = JsonX.asMap(j['current']);
    final points =
        JsonX.asList(j['points'] ?? j['history'], PricePoint.fromJson).where((p) => p.price > 0).toList()
          ..sort((a, b) => a.at.compareTo(b.at));
    final currentPrice = JsonX.asDouble(current['price'] ?? j['currentPrice'], points.isEmpty ? 0 : points.last.price);
    return PriceHistory(
      currentPrice: currentPrice,
      days: JsonX.asInt(j['days'], 90),
      points: points,
      lowest: JsonX.asDoubleOrNull(stats['lowest']),
      highest: JsonX.asDoubleOrNull(stats['highest']),
      average: JsonX.asDoubleOrNull(stats['average']),
      trend: JsonX.asString(j['trend'], 'flat'),
      insight: JsonX.asStringOrNull(j['insight']),
    );
  }

  final double currentPrice;
  final int days;

  /// Oldest first.
  final List<PricePoint> points;
  final double? lowest;
  final double? highest;
  final double? average;

  /// `down` | `up` | `flat`
  final String trend;

  /// A server-written line ("Lowest price in the last 90 days.").
  final String? insight;

  /// The chart line: every recorded point, then today's price (so the last
  /// step runs up to now).
  List<PricePoint> series({DateTime? now}) {
    if (points.isEmpty) return const [];
    final out = [...points];
    if (currentPrice > 0) {
      final stamp = now ?? DateTime.now();
      out.add(PricePoint(at: stamp.isBefore(out.last.at) ? out.last.at : stamp, price: currentPrice));
    }
    return out;
  }

  /// At least two different prices were recorded, so a chart says something.
  bool get hasChanges {
    final prices = {for (final p in series()) p.price};
    return prices.length >= 2;
  }

  /// Nothing recorded yet: the honest "tracking started today" state.
  bool get isEmpty => points.isEmpty;

  double get low => lowest ?? _min();
  double get high => highest ?? _max();

  double _min() {
    final all = series();
    return all.isEmpty ? currentPrice : all.map((p) => p.price).reduce((a, b) => a < b ? a : b);
  }

  double _max() {
    final all = series();
    return all.isEmpty ? currentPrice : all.map((p) => p.price).reduce((a, b) => a > b ? a : b);
  }

  /// Number of price changes among the recorded points.
  int get changes {
    var n = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].price != points[i - 1].price) n++;
    }
    if (points.isNotEmpty && points.last.price != currentPrice) n++;
    return n;
  }
}
