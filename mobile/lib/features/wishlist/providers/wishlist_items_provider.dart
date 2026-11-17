import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../../core/models/product_preview_cache.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_controller.dart';
import '../../cart/data/cart_repository.dart';
import '../../cart/providers/cart_controller.dart';
import 'wishlist_provider.dart';

/// Saved products (`GET /wishlist`, newest first). The wishlist screen shows
/// only those still in [wishlistIdsProvider], so un-hearting anywhere (and
/// undo) is reflected instantly without refetching.
final wishlistItemsProvider = FutureProvider.autoDispose<List<ProductSummary>>((ref) async {
  if (!ref.watch(isAuthenticatedProvider)) return const [];
  final items = await ref
      .watch(apiClientProvider)
      .get('/wishlist', decode: (d) => decodeList(d, ProductSummary.fromJson));
  ProductPreviewCache.rememberAll(items);
  // keep the hearts in sync with what the server just told us
  if (ref.mounted) unawaited(ref.read(wishlistIdsProvider.notifier).refresh());
  return items;
});

/// Wishlist actions that touch more than one feature.
final wishlistActionsProvider = Provider<WishlistActions>(WishlistActions.new);

class WishlistActions {
  WishlistActions(this._ref);

  final Ref _ref;

  /// Adds the product to the cart, then un-saves it. Returns the cart's
  /// server note (e.g. limited stock), if any. Throws [ApiException].
  Future<CartResponse> moveToCart(int productId) async {
    final res = await _ref.read(cartProvider.notifier).add(productId, source: 'wishlist');
    if (_ref.read(wishlistIdsProvider).contains(productId)) {
      await _ref.read(wishlistIdsProvider.notifier).toggle(productId);
    }
    return res;
  }
}
