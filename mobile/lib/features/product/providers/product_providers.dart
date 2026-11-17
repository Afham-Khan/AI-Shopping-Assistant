import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_controller.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/models/price_history.dart';
import '../data/models/product_detail.dart';
import '../data/price_history_repository.dart';

/// `GET /products/:idOrSlug` (the backend logs the view for signed-in users).
final productDetailProvider = FutureProvider.autoDispose.family<ProductDetail, String>((ref, idOrSlug) {
  ref.watch(isAuthenticatedProvider);
  return ref.watch(catalogRepositoryProvider).product(idOrSlug);
});

/// Recorded price changes (last 90 days) for the mini chart on the product page.
final priceHistoryProvider = FutureProvider.autoDispose.family<PriceHistory, int>(
  (ref, productId) => ref.watch(priceHistoryRepositoryProvider).history(productId),
);

/// The 3 most helpful reviews + rating summary for the product page.
final topReviewsProvider = FutureProvider.autoDispose.family<Paginated<Review>, int>(
  (ref, productId) =>
      ref.watch(catalogRepositoryProvider).reviews(productId, sort: ReviewSort.helpful, limit: 3),
);

typedef ReviewsArgs = ({int productId, ReviewSort sort});

@immutable
class ReviewsState {
  const ReviewsState({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.stats,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Review> items;
  final int page;
  final int totalPages;
  final ReviewStats stats;
  final bool loadingMore;
  final ApiException? loadMoreError;

  bool get hasMore => page < totalPages;
}

/// Paginated reviews for the reviews screen.
final reviewsProvider = AsyncNotifierProvider.autoDispose.family<ReviewsController, ReviewsState, ReviewsArgs>(
  ReviewsController.new,
);

class ReviewsController extends AsyncNotifier<ReviewsState> {
  ReviewsController(this.args);

  final ReviewsArgs args;

  @override
  Future<ReviewsState> build() async {
    final page = await ref.watch(catalogRepositoryProvider).reviews(args.productId, sort: args.sort);
    return ReviewsState(
      items: page.items,
      page: page.page,
      totalPages: page.totalPages,
      stats: ReviewStats.fromMeta(page.meta),
    );
  }

  Future<void> loadMore() async {
    final s = state.value;
    if (s == null || !s.hasMore || s.loadingMore) return;
    state = AsyncData(ReviewsState(items: s.items, page: s.page, totalPages: s.totalPages, stats: s.stats, loadingMore: true));
    try {
      final next = await ref.read(catalogRepositoryProvider).reviews(args.productId, sort: args.sort, page: s.page + 1);
      if (!ref.mounted) return;
      final seen = {for (final r in s.items) r.id};
      state = AsyncData(
        ReviewsState(
          items: [...s.items, ...next.items.where((r) => seen.add(r.id))],
          page: next.page,
          totalPages: next.totalPages,
          stats: ReviewStats.fromMeta(next.meta),
        ),
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(
        ReviewsState(items: s.items, page: s.page, totalPages: s.totalPages, stats: s.stats, loadMoreError: e),
      );
    }
  }
}
