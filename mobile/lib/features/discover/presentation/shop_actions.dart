import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product.dart';
import '../../../core/models/product_preview_cache.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/providers/require_auth.dart';
import '../../cart/providers/cart_controller.dart';
import '../../wishlist/providers/wishlist_provider.dart';

/// One-tap commerce used by the Room tray, the Discover deck and the reels.

/// Adds [product] to the cart (guests get the sign-in prompt). Returns true when added.
Future<bool> quickAddToCart(
  BuildContext context,
  WidgetRef ref,
  ProductSummary product, {
  String source = 'discover',
  bool announce = true,
}) async {
  if (!requireAuth(context, ref, message: 'Sign in to add items to your cart')) return false;
  HapticFeedback.lightImpact();
  try {
    final res = await ref.read(cartProvider.notifier).add(product.id, source: source);
    if (announce && context.mounted) {
      AppSnack.success(
        context,
        res.message ?? 'Added to cart',
        actionLabel: 'View cart',
        onAction: () => context.go(Routes.cart),
      );
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppSnack.error(context, e);
    return false;
  }
}

/// Flips the wishlist heart for [product]; guests get the sign-in prompt.
Future<void> quickToggleSave(BuildContext context, WidgetRef ref, ProductSummary product) async {
  if (!requireAuth(context, ref, message: 'Sign in to save items')) return;
  HapticFeedback.selectionClick();
  try {
    final saved = await toggleWishlist(ref, product.id);
    if (context.mounted) AppSnack.info(context, saved ? 'Saved to wishlist' : 'Removed from wishlist');
  } on ApiException catch (e) {
    if (context.mounted) AppSnack.error(context, e);
  }
}

/// Opens the product page (instantly, from the preview cache).
void openProduct(BuildContext context, ProductSummary product) {
  ProductPreviewCache.remember(product);
  context.push(Routes.product(product.id));
}
