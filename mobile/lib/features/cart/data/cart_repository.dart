import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'models/cart.dart';

/// A cart mutation's result: the full cart plus the server's optional note
/// (e.g. "Only 3 can be added (limited stock)").
typedef CartResponse = ({Cart cart, String? message});

/// Cart + coupon endpoints (all require auth).
class CartRepository {
  CartRepository(this._api);

  final ApiClient _api;

  Future<Cart> get() => _api.get('/cart', decode: (d) => Cart.fromJson(d as Json));

  Future<CartResponse> add(int productId, {int quantity = 1, String? source}) =>
      _send('POST', '/cart/items', {'productId': productId, 'quantity': quantity, 'source': ?source});

  Future<CartResponse> setQuantity(int productId, int quantity) =>
      _send('PATCH', '/cart/items/$productId', {'quantity': quantity});

  Future<CartResponse> remove(int productId) => _send('DELETE', '/cart/items/$productId');

  Future<CartResponse> clear() => _send('DELETE', '/cart');

  Future<CartResponse> applyCoupon(String code) => _send('POST', '/cart/coupon', {'code': code.trim().toUpperCase()});

  Future<CartResponse> removeCoupon() => _send('DELETE', '/cart/coupon');

  Future<List<Coupon>> coupons() => _api.get('/coupons', decode: (d) => decodeList(d, Coupon.fromJson));

  Future<CartResponse> _send(String method, String path, [Json? body]) async {
    final envelope = await _api.send(method, path, body: body);
    final data = envelope.data;
    if (data is! Map) throw const ApiException('Unexpected data from the server.', code: 'PARSE_ERROR');
    return (cart: Cart.fromJson(Map<String, dynamic>.from(data)), message: envelope.message);
  }
}

final cartRepositoryProvider = Provider<CartRepository>((ref) => CartRepository(ref.watch(apiClientProvider)));
