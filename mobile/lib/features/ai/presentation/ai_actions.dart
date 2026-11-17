import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/providers/require_auth.dart';
import '../../cart/providers/cart_provider.dart';
import '../data/ai_repository.dart';

/// Opens a product recommended by an AI surface and logs `ai_click`.
void openAiProduct(BuildContext context, WidgetRef ref, int productId, {String source = 'assistant'}) {
  ref.read(aiRepositoryProvider).track(productId, source: source);
  context.push(Routes.product(productId));
}

/// Asks for confirmation, then adds [productId] to the cart and syncs the badge.
/// Returns true when the item was added.
Future<bool> confirmAddToCart(
  BuildContext context,
  WidgetRef ref, {
  required int productId,
  String? title,
  double? price,
  int quantity = 1,
  String source = 'assistant',
}) async {
  if (!requireAuth(context, ref, message: 'Sign in to add items to your cart')) return false;
  final name = title ?? 'this item';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add to cart?'),
      content: Text(
        price == null ? 'Add $name to your cart?' : 'Add $name (${Formatters.price(price)}) to your cart?',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add to cart')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    final count = await ref.read(aiRepositoryProvider).addToCart(productId, quantity: quantity, source: source);
    ref.read(cartCountProvider.notifier).set(count);
    if (context.mounted) {
      AppSnack.success(context, 'Added to cart', actionLabel: 'View cart', onAction: () => context.go(Routes.cart));
    }
    return true;
  } on ApiException catch (e) {
    if (context.mounted) AppSnack.error(context, e);
    return false;
  }
}

/// Adds several products one after another (bundle "Add all"), then syncs the badge.
/// Returns how many were added.
Future<int> addAllToCart(BuildContext context, WidgetRef ref, List<ProductSummary> products, {String source = 'bundle'}) async {
  if (!requireAuth(context, ref, message: 'Sign in to add items to your cart')) return 0;
  final repo = ref.read(aiRepositoryProvider);
  var added = 0;
  ApiException? lastError;
  int? count;
  for (final p in products) {
    try {
      count = await repo.addToCart(p.id, source: source);
      added++;
    } on ApiException catch (e) {
      lastError = e;
    }
  }
  if (count != null) ref.read(cartCountProvider.notifier).set(count);
  if (!context.mounted) return added;
  if (added == products.length) {
    AppSnack.success(
      context,
      'Added ${Formatters.plural(added, 'item')} to cart',
      actionLabel: 'View cart',
      onAction: () => context.go(Routes.cart),
    );
  } else if (added > 0) {
    AppSnack.info(context, 'Added $added of ${products.length} items. ${lastError?.message ?? ''}'.trim());
  } else if (lastError != null) {
    AppSnack.error(context, lastError);
  }
  return added;
}
