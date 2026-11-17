import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/utils/extensions.dart';
import '../../ai/presentation/ai_actions.dart';
import '../data/chat_models.dart';

/// Product-list location for a `view_all` action. Every query value is kept
/// (minPrice/maxPrice/minRating/gender pass through for the list screen).
String viewAllLocation(ChatAction action) {
  final q = action.query;
  final params = <String, String>{
    for (final e in q.entries)
      if (e.value != null && '${e.value}'.trim().isNotEmpty)
        e.key: e.value is List ? (e.value as List).join(',') : '${e.value}',
  };
  params.putIfAbsent('title', () {
    final cat = params['category'] ?? params['department'];
    if (cat != null) return cat.titleCase;
    if (params['q'] != null) return params['q']!.capitalized;
    return 'Results';
  });
  return Uri(path: Routes.products, queryParameters: params).toString();
}

IconData chatActionIcon(String type) => switch (type) {
  'view_all' => Icons.grid_view_rounded,
  'compare' => Icons.compare_arrows_rounded,
  'add_to_cart' => Icons.add_shopping_cart_rounded,
  'open_product' => Icons.open_in_new_rounded,
  'view_order' => Icons.receipt_long_outlined,
  'open_cart' => Icons.shopping_cart_outlined,
  _ => Icons.arrow_forward_rounded,
};

bool isSupportedChatAction(ChatAction a) => switch (a.type) {
  'view_all' || 'open_cart' => true,
  'compare' => a.productIds.length >= 2,
  'add_to_cart' || 'open_product' => a.productId != null,
  'view_order' => a.orderId != null,
  _ => false,
};

Future<void> runChatAction(BuildContext context, WidgetRef ref, ChatAction action, {ChatMeta? meta}) async {
  switch (action.type) {
    case 'view_all':
      context.push(viewAllLocation(action));
    case 'compare':
      context.push(Routes.compareOf(action.productIds));
    case 'open_product':
      openAiProduct(context, ref, action.productId!, source: 'assistant');
    case 'add_to_cart':
      final product = meta?.products.where((p) => p.id == action.productId).firstOrNull;
      await confirmAddToCart(
        context,
        ref,
        productId: action.productId!,
        title: product?.title,
        price: product?.price,
        quantity: action.quantity,
        source: 'assistant',
      );
    case 'view_order':
      context.push(Routes.orderDetailOf(action.orderId!));
    case 'open_cart':
      context.go(Routes.cart);
  }
}
