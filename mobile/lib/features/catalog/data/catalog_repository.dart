import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../../core/network/api_client.dart';
import '../../product/data/models/product_detail.dart';
import 'models/catalog_models.dart';
import 'models/product_query.dart';

/// Catalog, product and review endpoints.
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  Future<HomeFeed> home() => _api.get('/catalog/home', decode: (d) => HomeFeed.fromJson(d as Json));

  Future<List<Department>> departments() =>
      _api.get('/catalog/departments', decode: (d) => decodeList(d, Department.fromJson));

  Future<CategoryInfo> category(String slug) =>
      _api.get('/catalog/categories/${Uri.encodeComponent(slug)}', decode: (d) => CategoryInfo.fromJson(d as Json));

  Future<Paginated<ProductSummary>> products(ProductQuery query, {int page = 1, int limit = 24}) =>
      _api.getPage('/products', query: query.toQuery(page: page, limit: limit), item: ProductSummary.fromJson);

  Future<ProductDetail> product(String idOrSlug) => _api.get(
    '/products/${Uri.encodeComponent(idOrSlug)}',
    decode: (d) => ProductDetail.fromJson(d as Json),
  );

  Future<Paginated<Review>> reviews(int productId, {ReviewSort sort = ReviewSort.recent, int page = 1, int limit = 10}) =>
      _api.getPage(
        '/products/$productId/reviews',
        query: {'sort': sort.value, 'page': page, 'limit': limit},
        item: Review.fromJson,
      );

  Future<Review> addReview(int productId, {required int rating, String? title, required String comment}) => _api.post(
    '/products/$productId/reviews',
    body: {
      'rating': rating,
      if (title != null && title.trim().isNotEmpty) 'title': title.trim(),
      'comment': comment.trim(),
    },
    decode: (d) => Review.fromJson(d as Json),
  );
}

final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepository(ref.watch(apiClientProvider)),
);
