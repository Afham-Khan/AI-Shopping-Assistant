import 'package:flutter/foundation.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/models/product.dart';
import '../../../core/utils/formatters.dart';

/// Live status the server computes for a watch (`status` on a PriceWatch).
@immutable
class PriceWatchStatus {
  const PriceWatchStatus({
    this.currentPrice,
    this.inStock = true,
    this.targetReached = false,
    this.dropSinceWatch = 0,
    this.summary = '',
  });

  factory PriceWatchStatus.fromJson(Map<String, dynamic> j) => PriceWatchStatus(
    currentPrice: JsonX.asDoubleOrNull(j['currentPrice']),
    inStock: JsonX.asBool(j['inStock'], true),
    targetReached: JsonX.asBool(j['targetReached']),
    dropSinceWatch: JsonX.asDouble(j['dropSinceWatch']),
    summary: JsonX.asString(j['summary']),
  );

  final double? currentPrice;
  final bool inStock;
  final bool targetReached;

  /// How much cheaper it is now than when the watch started (0 when not cheaper).
  final double dropSinceWatch;

  /// One friendly line from the server ("Rs 1,200 above your target of Rs 40,000").
  final String summary;
}

/// `GET /alerts/price-watch` row: `{ id, product, targetPrice, notifyRestock,
/// initialPrice, createdAt, lastNotifiedAt, status }`.
@immutable
class PriceWatch {
  const PriceWatch({
    required this.id,
    required this.product,
    this.targetPrice,
    this.notifyRestock = true,
    this.initialPrice,
    this.createdAt,
    this.lastNotifiedAt,
    this.status = const PriceWatchStatus(),
  });

  factory PriceWatch.fromJson(Map<String, dynamic> j) {
    // tolerate a missing product card: the watch's own id must not become the product id
    final productJson = JsonX.asMapOrNull(j['product']) ?? {...j, 'id': j['productId']};
    final target = JsonX.asDoubleOrNull(j['targetPrice']);
    return PriceWatch(
      id: JsonX.asInt(j['id']),
      product: ProductSummary.fromJson(productJson),
      targetPrice: target != null && target > 0 ? target : null,
      notifyRestock: JsonX.asBool(j['notifyRestock'], true),
      initialPrice: JsonX.asDoubleOrNull(j['initialPrice']),
      createdAt: JsonX.asDate(j['createdAt']),
      lastNotifiedAt: JsonX.asDate(j['lastNotifiedAt']),
      status: PriceWatchStatus.fromJson(JsonX.asMap(j['status'])),
    );
  }

  final int id;
  final ProductSummary product;

  /// Null = "any drop".
  final double? targetPrice;
  final bool notifyRestock;
  final double? initialPrice;
  final DateTime? createdAt;
  final DateTime? lastNotifiedAt;
  final PriceWatchStatus status;

  int get productId => product.id;
  bool get hasTarget => targetPrice != null;
  double get currentPrice => status.currentPrice ?? product.price;

  /// "Watching · target Rs 41,000" / "Watching · any drop".
  String get badgeLabel => hasTarget ? 'Watching · target ${Formatters.price(targetPrice)}' : 'Watching · any drop';

  /// What the user asked for, for a second line under "Watching".
  String get targetLabel => hasTarget ? 'Target ${Formatters.price(targetPrice)}' : 'Any drop';
}

/// The quick choices in the watch sheet.
enum WatchTargetKind { anyDrop, percent5, percent10, custom }

/// Pure helpers for the watch sheet (kept apart so they are easy to test).
abstract final class WatchTarget {
  static int _percent(WatchTargetKind kind) => switch (kind) {
    WatchTargetKind.percent5 => 5,
    WatchTargetKind.percent10 => 10,
    _ => 0,
  };

  /// Target price for a chip. Always strictly below [currentPrice] (the API
  /// rejects a target at or above today's price). `null` means "any drop".
  static double? forKind(WatchTargetKind kind, double currentPrice, {double? custom}) {
    switch (kind) {
      case WatchTargetKind.anyDrop:
        return null;
      case WatchTargetKind.custom:
        return custom;
      case WatchTargetKind.percent5:
      case WatchTargetKind.percent10:
        if (currentPrice <= 1) return null;
        final target = (currentPrice * (100 - _percent(kind)) / 100).floorToDouble();
        return target >= currentPrice ? currentPrice - 1 : target;
    }
  }

  /// Which chip an existing [target] corresponds to.
  static WatchTargetKind kindFor(double? target, double currentPrice) {
    if (target == null) return WatchTargetKind.anyDrop;
    for (final kind in [WatchTargetKind.percent5, WatchTargetKind.percent10]) {
      final expected = forKind(kind, currentPrice);
      if (expected != null && (expected - target).abs() < 1) return kind;
    }
    return WatchTargetKind.custom;
  }

  /// `"Rs 41,000"`, `"41000"`, `"41,000.50"` → 41000.5; null when unreadable.
  static double? parse(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Error text for a typed custom target (null when valid).
  static String? validateCustom(String text, double currentPrice) {
    final value = parse(text);
    if (value == null) return 'Enter an amount';
    if (value < 1) return 'Enter an amount above Rs 0';
    if (value >= currentPrice) return 'Pick a price below today\'s ${Formatters.price(currentPrice)}';
    return null;
  }

  /// "10% below today's price" for a target, or null when it isn't below.
  static String? percentBelow(double target, double currentPrice) {
    if (currentPrice <= 0 || target >= currentPrice) return null;
    final pct = ((currentPrice - target) / currentPrice * 100).round();
    return pct < 1 ? 'Under 1% below today\'s price' : '$pct% below today\'s price';
  }
}
