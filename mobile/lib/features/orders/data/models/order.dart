import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';
import '../../../profile/data/models/address.dart';

/// Order lifecycle. The happy path is the first five, in order.
enum OrderStatus {
  placed('placed', 'Placed', 'Order placed'),
  confirmed('confirmed', 'Confirmed', 'Order confirmed'),
  shipped('shipped', 'Shipped', 'Shipped'),
  outForDelivery('out_for_delivery', 'Out for delivery', 'Out for delivery'),
  delivered('delivered', 'Delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled', 'Cancelled');

  const OrderStatus(this.value, this.label, this.stepTitle);

  final String value;
  final String label;
  final String stepTitle;

  static OrderStatus parse(String? value) {
    for (final s in values) {
      if (s.value == value) return s;
    }
    return placed;
  }

  static const flow = [placed, confirmed, shipped, outForDelivery, delivered];

  bool get isActive => this != delivered && this != cancelled;
  bool get canCancel => this == placed || this == confirmed;
}

/// Row of `GET /orders`.
@immutable
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.total,
    required this.itemCount,
    this.placedAt,
    this.previewImages = const [],
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
    id: JsonX.asInt(json['id']),
    orderNumber: JsonX.asString(json['orderNumber']),
    status: OrderStatus.parse(JsonX.asStringOrNull(json['status'])),
    total: JsonX.asDouble(json['total']),
    itemCount: JsonX.asInt(json['itemCount']),
    placedAt: JsonX.asDate(json['placedAt']),
    previewImages: JsonX.asStringList(json['previewImages']),
  );

  final int id;
  final String orderNumber;
  final OrderStatus status;
  final double total;
  final int itemCount;
  final DateTime? placedAt;
  final List<String> previewImages;
}

@immutable
class OrderItem {
  const OrderItem({
    required this.productId,
    required this.title,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.thumbnail,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) => OrderItem(
    productId: JsonX.asInt(json['productId']),
    title: JsonX.asString(json['title']),
    thumbnail: JsonX.asStringOrNull(json['thumbnail']),
    unitPrice: JsonX.asDouble(json['unitPrice']),
    quantity: JsonX.asInt(json['quantity'], 1),
    lineTotal: JsonX.asDouble(json['lineTotal']),
  );

  final int productId;
  final String title;
  final String? thumbnail;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
}

@immutable
class OrderEvent {
  const OrderEvent({required this.status, this.note, this.createdAt});

  factory OrderEvent.fromJson(Map<String, dynamic> json) => OrderEvent(
    status: OrderStatus.parse(JsonX.asStringOrNull(json['status'])),
    note: JsonX.asStringOrNull(json['note']),
    createdAt: JsonX.asDate(json['createdAt']),
  );

  final OrderStatus status;
  final String? note;
  final DateTime? createdAt;
}

/// `GET /orders/:id`.
@immutable
class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.subtotal,
    required this.discount,
    required this.shippingFee,
    required this.total,
    this.cardLast4,
    this.couponCode,
    this.shippingAddress,
    this.notes,
    this.placedAt,
    this.deliveredAt,
    this.cancelledAt,
    this.estimatedDelivery,
    this.items = const [],
    this.timeline = const [],
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) {
    final address = JsonX.asMapOrNull(json['shippingAddress']);
    return OrderDetail(
      id: JsonX.asInt(json['id']),
      orderNumber: JsonX.asString(json['orderNumber']),
      status: OrderStatus.parse(JsonX.asStringOrNull(json['status'])),
      paymentMethod: JsonX.asString(json['paymentMethod'], 'cod'),
      paymentStatus: JsonX.asString(json['paymentStatus'], 'pending'),
      cardLast4: JsonX.asStringOrNull(json['cardLast4']),
      subtotal: JsonX.asDouble(json['subtotal']),
      discount: JsonX.asDouble(json['discount']),
      shippingFee: JsonX.asDouble(json['shippingFee']),
      total: JsonX.asDouble(json['total']),
      couponCode: JsonX.asStringOrNull(json['couponCode']),
      shippingAddress: address == null ? null : Address.fromJson(address),
      notes: JsonX.asStringOrNull(json['notes']),
      placedAt: JsonX.asDate(json['placedAt']),
      deliveredAt: JsonX.asDate(json['deliveredAt']),
      cancelledAt: JsonX.asDate(json['cancelledAt']),
      estimatedDelivery: JsonX.asDate(json['estimatedDelivery']),
      items: JsonX.asList(json['items'], OrderItem.fromJson),
      timeline: JsonX.asList(json['timeline'], OrderEvent.fromJson),
    );
  }

  final int id;
  final String orderNumber;
  final OrderStatus status;

  /// `cod` | `card`.
  final String paymentMethod;

  /// `pending` | `paid` | `refunded`.
  final String paymentStatus;
  final String? cardLast4;
  final double subtotal;
  final double discount;
  final double shippingFee;
  final double total;
  final String? couponCode;
  final Address? shippingAddress;
  final String? notes;
  final DateTime? placedAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final DateTime? estimatedDelivery;
  final List<OrderItem> items;
  final List<OrderEvent> timeline;

  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  String get paymentLabel =>
      paymentMethod == 'card' ? 'Card${cardLast4 == null ? '' : ' •••• $cardLast4'}' : 'Cash on delivery';

  /// Latest history entry for [s], if it happened.
  OrderEvent? eventFor(OrderStatus s) {
    OrderEvent? found;
    for (final e in timeline) {
      if (e.status == s) found = e;
    }
    return found;
  }
}
