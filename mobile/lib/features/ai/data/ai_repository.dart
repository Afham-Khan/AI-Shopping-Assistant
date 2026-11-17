import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/models/product.dart';
import '../../../core/network/api_client.dart';
import 'models/ai_models.dart';
import 'models/shopping_models.dart';

/// Every `/ai/*` endpoint except chat (see `AssistantRepository`), plus the
/// two small cart/interaction calls AI surfaces need (swap, add bundle).
class AiRepository {
  AiRepository(this._api);

  final ApiClient _api;

  Future<AiRecommendations> recommendations({int limit = 10}) =>
      _api.get('/ai/recommendations', query: {'limit': limit}, decode: AiRecommendations.fromJson);

  Future<List<ProductSummary>> similar(int productId, {int limit = 8}) =>
      _api.get('/ai/similar/$productId', query: {'limit': limit}, decode: _productList);

  Future<List<ProductSummary>> boughtTogether(int productId, {int limit = 6}) =>
      _api.get('/ai/bought-together/$productId', query: {'limit': limit}, decode: _productList);

  Future<ReviewSummary> reviewSummary(int productId) =>
      _api.get('/ai/review-summary/$productId', decode: ReviewSummary.fromJson);

  /// [need] ("gaming", "a gift for mum") asks the server for a "Best for you" pick.
  Future<CompareResult> compare(List<int> productIds, {String? need}) => _api.post(
    '/ai/compare',
    body: {
      'productIds': productIds,
      if (need != null && need.trim().isNotEmpty) 'need': need.trim(),
    },
    decode: CompareResult.fromJson,
  );

  /// Outfit picks for a fashion item (`GET /ai/complete-look/:id`).
  Future<CompleteLook> completeLook(int productId) =>
      _api.get('/ai/complete-look/$productId', decode: CompleteLook.fromJson);

  /// Plain-language spec explainer (`GET /ai/explain/:id`).
  Future<SpecExplainer> explain(int productId) => _api.get('/ai/explain/$productId', decode: SpecExplainer.fromJson);

  /// Gift Finder. [budget] is the most the shopper will spend.
  Future<GiftResult> gift({
    required String recipient,
    required String occasion,
    required num budget,
    List<String> interests = const [],
  }) => _api.post(
    '/ai/gift',
    body: {'recipient': recipient, 'occasion': occasion, 'budget': budget.round(), 'interests': interests},
    decode: GiftResult.fromJson,
  );

  Future<SmartSearchResult> smartSearch(String q, {int limit = 20}) =>
      _api.get('/ai/search', query: {'q': q, 'limit': limit}, decode: SmartSearchResult.fromJson);

  Future<NluResult> nlu(String text) => _api.post('/ai/nlu', body: {'text': text}, decode: NluResult.fromJson);

  Future<List<FinderFlow>> finder() => _api.get(
    '/ai/finder',
    decode: (d) => JsonX.asList(d is Map ? d['departments'] : d, FinderFlow.fromJson),
  );

  Future<AiProductsResult> finderResults(String department, Map<String, Object?> answers) => _api.post(
    '/ai/finder',
    body: {'department': department, 'answers': answers},
    decode: AiProductsResult.fromJson,
  );

  Future<AiInsights> insights() => _api.get('/ai/insights', decode: AiInsights.fromJson);

  /// Multipart upload, field `image` (≤ 5 MB jpg/png/webp). 503 → model offline.
  Future<VisualSearchResult> visualSearch(Uint8List bytes, {required String filename, String? mimeType}) {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: mimeType == null ? null : DioMediaType.parse(mimeType),
      ),
    });
    return _api.post('/ai/visual-search', body: form, decode: VisualSearchResult.fromJson);
  }

  /// "Describe what you're looking for" (`GET /ai/visual-search/text?q=`, CLIP
  /// text to image). Falls back to natural-language search if the route is missing.
  Future<VisualSearchResult> describeSearch(String text) async {
    try {
      return await _api.get('/ai/visual-search/text', query: {'q': text}, decode: VisualSearchResult.fromJson);
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow;
      final r = await smartSearch(text);
      return VisualSearchResult(products: r.products);
    }
  }

  Future<BundleResult> bundle({required String goal, required double budget}) =>
      _api.post('/ai/bundle', body: {'goal': goal, 'budget': budget.round()}, decode: BundleResult.fromJson);

  Future<ProductAnswer> askProduct(int productId, String question) =>
      _api.post('/ai/products/$productId/ask', body: {'question': question}, decode: ProductAnswer.fromJson);

  Future<CartInsights> cartInsights() => _api.get('/ai/cart-insights', decode: CartInsights.fromJson);

  Future<ShoppingProfile> profile() => _api.get('/ai/profile', decode: ShoppingProfile.fromJson);

  /// Product header for AI screens that only get an id.
  Future<ProductSummary> product(int id) =>
      _api.get('/products/$id', decode: (d) => ProductSummary.fromJson(JsonX.asMap(d)));

  // ---- cart + analytics used by AI surfaces ----

  /// Adds to the cart and returns the new `summary.itemCount`.
  Future<int> addToCart(int productId, {int quantity = 1, String source = 'ai'}) => _api.post(
    '/cart/items',
    body: {'productId': productId, 'quantity': quantity, 'source': source},
    decode: _itemCount,
  );

  Future<int> removeFromCart(int productId) => _api.delete('/cart/items/$productId', decode: _itemCount);

  /// Quantity of [productId] currently in the cart (0 when absent).
  Future<int> cartQuantity(int productId) => _api.get(
    '/cart',
    decode: (d) {
      for (final item in JsonX.asList(JsonX.asMap(d)['items'], (j) => j)) {
        if (JsonX.asInt(item['productId']) == productId) return JsonX.asInt(item['quantity'], 1);
      }
      return 0;
    },
  );

  /// Fire-and-forget analytics; never throws.
  Future<void> track(int productId, {String type = 'ai_click', String source = 'assistant'}) async {
    try {
      await _api.post<void>('/interactions', body: {'productId': productId, 'type': type, 'source': source});
    } catch (_) {
      // analytics must never break the UI
    }
  }

  static List<ProductSummary> _productList(dynamic d) =>
      JsonX.asList(d is Map ? d['products'] ?? d['items'] : d, ProductSummary.fromJson);

  static int _itemCount(dynamic d) => JsonX.asInt(JsonX.asMap(JsonX.asMap(d)['summary'])['itemCount']);
}

final aiRepositoryProvider = Provider<AiRepository>((ref) => AiRepository(ref.watch(apiClientProvider)));
