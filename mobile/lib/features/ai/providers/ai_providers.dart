import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../auth/providers/auth_controller.dart';
import '../../cart/providers/cart_provider.dart';
import '../data/ai_repository.dart';
import '../data/models/ai_models.dart';
import '../data/models/shopping_models.dart';

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

/// Keyed by the canonical id list plus the shopper's need (`"2,5,9"` or
/// `"2,5,9|gaming"`) so the same question never refetches.
final compareProvider = FutureProvider.autoDispose.family<CompareResult, String>((ref, key) {
  final split = key.indexOf('|');
  final ids = [for (final s in (split < 0 ? key : key.substring(0, split)).split(',')) ?int.tryParse(s)];
  final need = split < 0 ? null : key.substring(split + 1);
  return ref.watch(aiRepositoryProvider).compare(ids, need: need);
});

String compareKey(List<int> ids, {String? need}) {
  final n = need?.trim() ?? '';
  return n.isEmpty ? ids.join(',') : '${ids.join(',')}|$n';
}

/// Outfit picks for a fashion product (hidden when the server has none).
final completeLookProvider = FutureProvider.autoDispose.family<CompleteLook, int>(
  (ref, productId) => ref.watch(aiRepositoryProvider).completeLook(productId),
);

/// "Explain these specs" for a product page.
final specExplainerProvider = FutureProvider.autoDispose.family<SpecExplainer, int>(
  (ref, productId) => ref.watch(aiRepositoryProvider).explain(productId),
);

final smartSearchProvider = FutureProvider.autoDispose.family<SmartSearchResult, String>((ref, q) {
  ref.watch(isAuthenticatedProvider);
  return ref.watch(aiRepositoryProvider).smartSearch(q);
});

final finderFlowsProvider = FutureProvider.autoDispose<List<FinderFlow>>(
  (ref) => ref.watch(aiRepositoryProvider).finder(),
);

/// Bundle goals with their suggested budgets. Kept for the session once
/// loaded; a failed load is retried on the next watch, and callers fall back
/// to their own defaults meanwhile.
final bundleTemplatesProvider = FutureProvider.autoDispose<List<BundleTemplate>>((ref) async {
  final templates = await ref.watch(aiRepositoryProvider).bundleTemplates();
  ref.keepAlive();
  return templates;
});

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
