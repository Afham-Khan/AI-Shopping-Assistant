import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../../core/models/product_preview_cache.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/catalog_repository.dart';
import '../data/models/catalog_models.dart';
import '../data/models/product_query.dart';

/// `GET /catalog/home` — personalized when signed in, so it refetches on login/logout.
final homeFeedProvider = FutureProvider.autoDispose<HomeFeed>((ref) async {
  ref.watch(isAuthenticatedProvider);
  final feed = await ref.watch(catalogRepositoryProvider).home();
  return feed;
});

/// Departments with their categories. Static catalog data: kept for the session.
final departmentsProvider = FutureProvider<List<Department>>(
  (ref) => ref.watch(catalogRepositoryProvider).departments(),
);

/// `GET /catalog/categories/:slug` (header image + description on product lists).
final categoryInfoProvider = FutureProvider.autoDispose.family<CategoryInfo, String>(
  (ref, slug) => ref.watch(catalogRepositoryProvider).category(slug),
);

/// One loaded window of a product list (infinite scroll).
@immutable
class ProductListState {
  const ProductListState({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.total,
    required this.facets,
    this.relaxedSearch = false,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<ProductSummary> items;
  final int page;
  final int totalPages;
  final int total;
  final ProductFacets facets;

  /// The backend fell back to any-word matching for a multi-word query.
  final bool relaxedSearch;
  final bool loadingMore;
  final ApiException? loadMoreError;

  bool get hasMore => page < totalPages;

  ProductListState copyWith({
    List<ProductSummary>? items,
    int? page,
    int? totalPages,
    int? total,
    bool? loadingMore,
    ApiException? Function()? loadMoreError,
  }) {
    return ProductListState(
      items: items ?? this.items,
      page: page ?? this.page,
      totalPages: totalPages ?? this.totalPages,
      total: total ?? this.total,
      facets: facets,
      relaxedSearch: relaxedSearch,
      loadingMore: loadingMore ?? this.loadingMore,
      loadMoreError: loadMoreError == null ? this.loadMoreError : loadMoreError(),
    );
  }
}

/// Paginated `GET /products` for a [ProductQuery].
///
/// ```dart
/// ref.watch(productListProvider(query))            // AsyncValue<ProductListState>
/// ref.read(productListProvider(query).notifier).loadMore()
/// ```
final productListProvider =
    AsyncNotifierProvider.autoDispose.family<ProductListController, ProductListState, ProductQuery>(
      ProductListController.new,
    );

class ProductListController extends AsyncNotifier<ProductListState> {
  ProductListController(this.query);

  final ProductQuery query;
  static const pageSize = 24;

  @override
  Future<ProductListState> build() async {
    ref.watch(isAuthenticatedProvider);
    final page = await ref.watch(catalogRepositoryProvider).products(query, limit: pageSize);
    ProductPreviewCache.rememberAll(page.items);
    return ProductListState(
      items: page.items,
      page: page.page,
      totalPages: page.totalPages,
      total: page.total,
      facets: ProductFacets.fromMeta(page.meta),
      relaxedSearch: page.meta['relaxedSearch'] == true,
    );
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || state.isLoading) return;
    state = AsyncData(current.copyWith(loadingMore: true, loadMoreError: () => null));
    try {
      final next = await ref.read(catalogRepositoryProvider).products(query, page: current.page + 1, limit: pageSize);
      if (!ref.mounted) return;
      ProductPreviewCache.rememberAll(next.items);
      // pages can shift while browsing; never show (or hero-tag) a product twice
      final seen = {for (final p in current.items) p.id};
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...next.items.where((p) => seen.add(p.id))],
          page: next.page,
          totalPages: next.totalPages,
          total: next.total,
          loadingMore: false,
        ),
      );
    } on ApiException catch (e) {
      if (!ref.mounted) return;
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: () => e));
    }
  }
}
