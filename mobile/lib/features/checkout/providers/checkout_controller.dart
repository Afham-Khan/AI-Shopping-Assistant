import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../cart/providers/cart_controller.dart';
import '../../notifications/providers/notifications_providers.dart';
import '../../orders/data/models/order.dart';
import '../../orders/data/orders_repository.dart';
import '../../orders/providers/orders_providers.dart';
import '../../profile/providers/profile_providers.dart';

/// Places orders and keeps the rest of the app in sync afterwards
/// (empty cart + badge, orders lists, stats, notification badge).
///
/// ```dart
/// final order = await ref.read(checkoutControllerProvider).placeOrder(addressId: 1, paymentMethod: 'cod');
/// ```
final checkoutControllerProvider = Provider<CheckoutController>(CheckoutController.new);

class CheckoutController {
  CheckoutController(this._ref);

  final Ref _ref;

  /// [cardLast4] only — the full number never leaves the device.
  /// Throws [ApiException]: 409 stock short, 400 empty cart / coupon, 404 address.
  Future<OrderDetail> placeOrder({
    required int addressId,
    required String paymentMethod,
    String? cardLast4,
    String? notes,
  }) async {
    try {
      final order = await _ref
          .read(ordersRepositoryProvider)
          .place(addressId: addressId, paymentMethod: paymentMethod, cardLast4: cardLast4, notes: notes);
      _ref.read(cartProvider.notifier).markEmpty();
      _ref
        ..invalidate(ordersProvider)
        ..invalidate(userStatsProvider);
      _ref.read(unreadNotificationsProvider.notifier).refresh();
      return order;
    } on ApiException catch (e) {
      // show the cart / addresses as the server sees them now
      if (e.isConflict || e.isValidation) _ref.read(cartProvider.notifier).refresh().catchError((_) {});
      if (e.isNotFound) _ref.invalidate(addressesProvider);
      rethrow;
    }
  }
}
