import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/cart_repository.dart';
import '../data/models/cart.dart';
import 'cart_provider.dart';

/// The full cart. Empty for guests; reloads on login/logout.
///
/// Every mutation pushes the new item count to [cartCountProvider] (tab badge).
/// ```dart
/// final res = await ref.read(cartProvider.notifier).add(product.id, quantity: 2);
/// if (res.message != null) AppSnack.info(context, res.message!);
/// ```
final cartProvider = AsyncNotifierProvider<CartController, Cart>(CartController.new);

/// Available coupons (`GET /coupons`), loaded when the sheet opens.
final couponsProvider = FutureProvider.autoDispose<List<Coupon>>(
  (ref) => ref.watch(cartRepositoryProvider).coupons(),
);

class CartController extends AsyncNotifier<Cart> {
  CartRepository get _repo => ref.read(cartRepositoryProvider);

  /// Last cart confirmed by the server (rollback target for optimistic edits).
  Cart _confirmed = Cart.empty;

  /// Bumped per request so out-of-order responses never overwrite newer state.
  int _version = 0;

  @override
  Future<Cart> build() async {
    final signedIn = ref.watch(isAuthenticatedProvider);
    _version++;
    if (!signedIn) {
      _confirmed = Cart.empty;
      return Cart.empty;
    }
    final cart = await ref.watch(cartRepositoryProvider).get();
    _confirmed = cart;
    _pushCount(cart);
    return cart;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Adds [quantity] (the server caps at stock / 10). Returns the server note, if any.
  Future<CartResponse> add(int productId, {int quantity = 1, String? source}) async {
    await _settled();
    final res = await _repo.add(productId, quantity: quantity, source: source);
    _accept(res.cart, ++_version);
    return res;
  }

  /// Optimistic quantity change (0 removes); rolls back and rethrows on failure.
  Future<CartResponse> setQuantity(int productId, int quantity) async {
    final current = state.value ?? _confirmed;
    state = AsyncData(current.withQuantity(productId, quantity));
    _pushCount(state.requireValue);
    final version = ++_version;
    try {
      final res = await _repo.setQuantity(productId, quantity);
      _accept(res.cart, version);
      return res;
    } on ApiException {
      _rollback(version);
      rethrow;
    }
  }

  /// Optimistic removal. Returns the removed line so the UI can offer "Undo".
  Future<CartItem?> remove(int productId) async {
    final current = state.value ?? _confirmed;
    CartItem? removed;
    for (final i in current.items) {
      if (i.productId == productId) removed = i;
    }
    state = AsyncData(current.withQuantity(productId, 0));
    _pushCount(state.requireValue);
    final version = ++_version;
    try {
      final res = await _repo.remove(productId);
      _accept(res.cart, version);
      return removed;
    } on ApiException {
      _rollback(version);
      rethrow;
    }
  }

  /// Puts a removed line back (undo).
  Future<void> restore(CartItem item) => add(item.productId, quantity: item.quantity);

  /// Throws [ApiException] with the reason when the code is invalid / min not met.
  Future<Cart> applyCoupon(String code) async {
    final res = await _repo.applyCoupon(code);
    _accept(res.cart, ++_version);
    return res.cart;
  }

  Future<void> removeCoupon() async {
    final res = await _repo.removeCoupon();
    _accept(res.cart, ++_version);
  }

  /// After checkout the server empties the cart.
  void markEmpty() {
    _version++;
    _confirmed = Cart.empty;
    state = const AsyncData(Cart.empty);
    _pushCount(Cart.empty);
  }

  // ---------- internals ----------

  /// Waits for the initial load so its response can't overwrite a mutation.
  Future<void> _settled() async {
    try {
      await future;
    } catch (_) {
      // a failed initial load shouldn't block adding to the cart
    }
  }

  void _accept(Cart cart, int version) {
    if (!ref.mounted) return;
    _confirmed = cart;
    if (version != _version) return; // a newer request will land shortly
    state = AsyncData(cart);
    _pushCount(cart);
  }

  void _rollback(int version) {
    if (!ref.mounted || version != _version) return;
    state = AsyncData(_confirmed);
    _pushCount(_confirmed);
  }

  void _pushCount(Cart cart) => ref.read(cartCountProvider.notifier).set(cart.summary.itemCount);
}
