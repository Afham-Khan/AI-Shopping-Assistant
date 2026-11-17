import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../auth/providers/auth_controller.dart';
import '../../cart/providers/cart_provider.dart';
import '../data/ai_repository.dart';
import '../data/models/ai_models.dart';

/// Personal "For you" rail. Refetches on login/logout (guests get popular picks).
final recommendationsProvider = FutureProvider.autoDispose<AiRecommendations>((ref) {
  ref.watch(isAuthenticatedProvider);
  return ref.watch(aiRepositoryProvider).recommendations();
});

final similarProductsProvider = FutureProvider.autoDispose.family<List<ProductSummary>, int>(
  (ref, productId) => ref.watch(aiRepositoryProvider).similar(productId),
);

final boughtTogetherProvider = FutureProvider.autoDispose.family<List<ProductSummary>, int>(
  (ref, productId) => ref.watch(aiRepositoryProvider).boughtTogether(productId),
);

final reviewSummaryProvider = FutureProvider.autoDispose.family<ReviewSummary, int>(
  (ref, productId) => ref.watch(aiRepositoryProvider).reviewSummary(productId),
);

/// Keyed by the canonical id list (`"2,5,9"`) so the same set never refetches.
final compareProvider = FutureProvider.autoDispose.family<CompareResult, String>((ref, key) {
  final ids = [for (final s in key.split(',')) ?int.tryParse(s)];
  return ref.watch(aiRepositoryProvider).compare(ids);
});

String compareKey(List<int> ids) => ids.join(',');

final smartSearchProvider = FutureProvider.autoDispose.family<SmartSearchResult, String>((ref, q) {
  ref.watch(isAuthenticatedProvider);
  return ref.watch(aiRepositoryProvider).smartSearch(q);
});

final finderFlowsProvider = FutureProvider.autoDispose<List<FinderFlow>>(
  (ref) => ref.watch(aiRepositoryProvider).finder(),
);

final aiInsightsProvider = FutureProvider.autoDispose<AiInsights>((ref) => ref.watch(aiRepositoryProvider).insights());

/// Product header for AI screens (ask, etc.).
final aiProductProvider = FutureProvider.autoDispose.family<ProductSummary, int>(
  (ref, id) => ref.watch(aiRepositoryProvider).product(id),
);

/// Cart insights: only for signed-in users; refetches when the cart count changes.
final cartInsightsProvider = FutureProvider.autoDispose<CartInsights?>((ref) async {
  if (!ref.watch(isAuthenticatedProvider)) return null;
  final count = ref.watch(cartCountProvider);
  if (count == 0) return null;
  return ref.watch(aiRepositoryProvider).cartInsights();
});

final shoppingProfileProvider = FutureProvider.autoDispose<ShoppingProfile>((ref) {
  ref.watch(isAuthenticatedProvider);
  return ref.watch(aiRepositoryProvider).profile();
});
