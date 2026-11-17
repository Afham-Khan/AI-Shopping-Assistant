import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'models/order.dart';

/// `active` | `delivered` | `cancelled` tabs of the orders screen.
enum OrderFilter {
  active('active', 'Active'),
  delivered('delivered', 'Delivered'),
  cancelled('cancelled', 'Cancelled');

  const OrderFilter(this.value, this.label);

  final String value;
  final String label;
}

/// Orders endpoints (all require auth).
class OrdersRepository {
  OrdersRepository(this._api);

  final ApiClient _api;

  Future<Paginated<OrderSummary>> list(OrderFilter filter, {int page = 1}) =>
      _api.getPage('/orders', query: {'status': filter.value, 'page': page, 'limit': 20}, item: OrderSummary.fromJson);

  Future<OrderDetail> detail(int id) => _api.get('/orders/$id', decode: (d) => OrderDetail.fromJson(d as Json));

  Future<OrderDetail> cancel(int id) =>
      _api.post('/orders/$id/cancel', decode: (d) => OrderDetail.fromJson(d as Json));

  /// [cardLast4] only — the full card number never leaves the device.
  Future<OrderDetail> place({
    required int addressId,
    required String paymentMethod,
    String? cardLast4,
    String? notes,
  }) => _api.post(
    '/orders',
    body: {
      'addressId': addressId,
      'paymentMethod': paymentMethod,
      if (cardLast4 != null) 'card': {'last4': cardLast4},
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    },
    decode: (d) => OrderDetail.fromJson(d as Json),
  );
}

final ordersRepositoryProvider = Provider<OrdersRepository>((ref) => OrdersRepository(ref.watch(apiClientProvider)));
