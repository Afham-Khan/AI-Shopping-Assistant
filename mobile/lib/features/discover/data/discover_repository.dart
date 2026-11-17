import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/models/product.dart';
import '../../../core/network/api_client.dart';
import '../../catalog/data/models/catalog_models.dart';
import 'discover_models.dart';

/// `/discover/*` endpoints. Each call degrades gracefully while the backend
/// is being built: a 404 falls back to existing catalog / AI endpoints, so
/// the deck and the reels work either way.
class DiscoverRepository {
  DiscoverRepository(this._api);

  final ApiClient _api;
  final _random = math.Random();

  /// `GET /discover/deck?limit=` (fallback: a shuffled page of popular products).
  Future<List<ProductSummary>> deck({int limit = 20}) async {
    try {
      final items = await _api.get('/discover/deck', query: {'limit': limit}, decode: _products);
      if (items.isNotEmpty) return items;
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    final page = await _api.getPage(
      '/products',
      query: {'sort': 'popular', 'limit': 48, 'page': 1 + _random.nextInt(3)},
      item: ProductSummary.fromJson,
    );
    return ([...page.items]..shuffle(_random)).take(limit).toList();
  }

  /// `POST /discover/swipe` (🔒). A `bag` also adds one to the cart on the
  /// server. Returns null when the endpoint is missing or the shopper is a
  /// guest (the deck then keeps learning locally); other errors (409 out of
  /// stock) are thrown.
  Future<SwipeResponse?> swipe(int productId, SwipeAction action) async {
    try {
      return await _api.post(
        '/discover/swipe',
        body: {'productId': productId, 'action': action.value},
        decode: SwipeResponse.fromJson,
      );
    } on ApiException catch (e) {
      if (e.isNotFound || e.isUnauthorized || e.code == ApiException.authRequired) return null;
      rethrow;
    }
  }

  /// `GET /discover/taste` (🔒): what the server already knows. Null for
  /// guests or when unavailable.
  Future<TasteProfile?> taste() async {
    try {
      final t = await _api.get('/discover/taste', decode: (d) => TasteProfile.fromJson(JsonX.asMap(d)['taste'] ?? d));
      return t.isEmpty ? null : t;
    } on ApiException {
      return null;
    }
  }

  /// Nearest neighbours for "because you liked…" when the swipe response has none.
  Future<List<ProductSummary>> similar(int productId, {int limit = 3}) async {
    try {
      return await _api.get('/ai/similar/$productId', query: {'limit': limit}, decode: _products);
    } on ApiException {
      return const [];
    }
  }

  /// `GET /discover/reels` (fallback: one story per department from `/products`).
  Future<List<DiscoverReel>> reels() async {
    try {
      final reels = await _api.get(
        '/discover/reels',
        query: {'perDepartment': 6},
        decode: (d) => JsonX.asList(d is Map ? d['reels'] : d, DiscoverReel.fromJson),
      );
      final usable = reels.where((r) => r.products.isNotEmpty).toList();
      if (usable.isNotEmpty) return usable;
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow;
    }
    final departments = await _api.get('/catalog/departments', decode: (d) => JsonX.asList(d, Department.fromJson));
    final stories = await Future.wait([
      for (final d in departments)
        _api
            .getPage(
              '/products',
              query: {'department': d.slug, 'sort': 'rating', 'limit': 8},
              item: ProductSummary.fromJson,
            )
            .then((p) => p.items)
            .catchError((Object _) => const <ProductSummary>[]),
    ]);
    return [
      for (var i = 0; i < departments.length; i++)
        if (stories[i].isNotEmpty)
          DiscoverReel(
            department: departments[i].name,
            slug: departments[i].slug,
            headline: 'Best rated in ${departments[i].name}',
            products: stories[i],
          ),
    ];
  }

  static List<ProductSummary> _products(dynamic d) => JsonX.asList(
    d is Map ? d['products'] ?? d['items'] ?? d['deck'] : d,
    ProductSummary.fromJson,
  ).where((p) => p.id != 0).toList();
}

final discoverRepositoryProvider = Provider<DiscoverRepository>(
  (ref) => DiscoverRepository(ref.watch(apiClientProvider)),
);
