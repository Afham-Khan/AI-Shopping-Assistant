import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';
import '../../../../core/models/product.dart';

@immutable
class CartItem {
  const CartItem({required this.productId, required this.product, required this.quantity, required this.lineTotal});

  factory CartItem.fromJson(Map<String, dynamic> json) {
    final product = ProductSummary.fromJson(JsonX.asMap(json['product']));
    return CartItem(
      productId: JsonX.asInt(json['productId'], product.id),
      product: product,
      quantity: JsonX.asInt(json['quantity'], 1),
      lineTotal: JsonX.asDouble(json['lineTotal']),
    );
  }

  final int productId;
  final ProductSummary product;
  final int quantity;

  /// 0 when the product went out of stock (excluded from totals).
  final double lineTotal;

  /// The most this line can hold (stock, max 10 per item).
  int get maxQuantity => product.stock <= 0 ? quantity : (product.stock < 10 ? product.stock : 10);

  CartItem withQuantity(int q) =>
      CartItem(productId: productId, product: product, quantity: q, lineTotal: product.price * q);
}

@immutable
class AppliedCoupon {
  const AppliedCoupon({required this.code, this.description});

  final String code;
  final String? description;
}

@immutable
class CartSummary {
  const CartSummary({
    this.itemCount = 0,
    this.subtotal = 0,
    this.discount = 0,
    this.shippingFee = 0,
    this.total = 0,
    this.freeShippingThreshold = 5000,
    this.coupon,
    this.savings = 0,
  });

  factory CartSummary.fromJson(Map<String, dynamic> json) {
    final coupon = JsonX.asMapOrNull(json['coupon']);
    return CartSummary(
      itemCount: JsonX.asInt(json['itemCount']),
      subtotal: JsonX.asDouble(json['subtotal']),
      discount: JsonX.asDouble(json['discount']),
      shippingFee: JsonX.asDouble(json['shippingFee']),
      total: JsonX.asDouble(json['total']),
      freeShippingThreshold: JsonX.asDouble(json['freeShippingThreshold'], 5000),
      coupon: coupon == null
          ? null
          : AppliedCoupon(code: JsonX.asString(coupon['code']), description: JsonX.asStringOrNull(coupon['description'])),
      savings: JsonX.asDouble(json['savings']),
    );
  }

  final int itemCount;
  final double subtotal;
  final double discount;
  final double shippingFee;
  final double total;
  final double freeShippingThreshold;
  final AppliedCoupon? coupon;

  /// Compare-at savings + coupon discount.
  final double savings;

  /// Amount still needed for free delivery (0 when it already applies).
  double get remainingForFreeShipping {
    final left = freeShippingThreshold - (subtotal - discount);
    return left > 0 ? left : 0;
  }

  double get freeShippingProgress =>
      freeShippingThreshold <= 0 ? 1 : ((subtotal - discount) / freeShippingThreshold).clamp(0, 1).toDouble();
}

@immutable
class Cart {
  const Cart({this.items = const [], this.summary = const CartSummary()});

  factory Cart.fromJson(Map<String, dynamic> json) => Cart(
    items: JsonX.asList(json['items'], CartItem.fromJson),
    summary: CartSummary.fromJson(JsonX.asMap(json['summary'])),
  );

  static const empty = Cart();

  final List<CartItem> items;
  final CartSummary summary;

  bool get isEmpty => items.isEmpty;

  /// Lines that block checkout (out of stock).
  List<CartItem> get unavailable => [for (final i in items) if (!i.product.inStock) i];

  int quantityOf(int productId) {
    for (final i in items) {
      if (i.productId == productId) return i.quantity;
    }
    return 0;
  }

  /// Local optimistic edit; the server's cart replaces it right after.
  Cart withQuantity(int productId, int quantity) {
    final next = <CartItem>[
      for (final i in items)
        if (i.productId != productId)
          i
        else if (quantity > 0)
          i.withQuantity(quantity),
    ];
    final count = next.fold<int>(0, (sum, i) => sum + i.quantity);
    return Cart(
      items: next,
      summary: CartSummary(
        itemCount: count,
        subtotal: summary.subtotal,
        discount: summary.discount,
        shippingFee: summary.shippingFee,
        total: summary.total,
        freeShippingThreshold: summary.freeShippingThreshold,
        coupon: summary.coupon,
        savings: summary.savings,
      ),
    );
  }
}

/// `GET /coupons`.
@immutable
class Coupon {
  const Coupon({
    required this.code,
    required this.description,
    required this.discountType,
    required this.value,
    this.minOrderAmount = 0,
    this.maxDiscount,
    this.expiresAt,
  });

  factory Coupon.fromJson(Map<String, dynamic> json) => Coupon(
    code: JsonX.asString(json['code']),
    description: JsonX.asString(json['description']),
    discountType: JsonX.asString(json['discountType'], 'percent'),
    value: JsonX.asDouble(json['value']),
    minOrderAmount: JsonX.asDouble(json['minOrderAmount']),
    maxDiscount: JsonX.asDoubleOrNull(json['maxDiscount']),
    expiresAt: JsonX.asDate(json['expiresAt']),
  );

  final String code;
  final String description;

  /// `percent` | `fixed`.
  final String discountType;
  final double value;
  final double minOrderAmount;
  final double? maxDiscount;
  final DateTime? expiresAt;

  bool get isPercent => discountType == 'percent';
}
