import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'models/price_history.dart';

/// `GET /products/:id/price-history` (public).
class PriceHistoryRepository {
  PriceHistoryRepository(this._api);

  final ApiClient _api;

  Future<PriceHistory> history(int productId, {int days = 90}) =>
      _api.get('/products/$productId/price-history', query: {'days': days}, decode: PriceHistory.fromJson);
}

final priceHistoryRepositoryProvider = Provider<PriceHistoryRepository>(
  (ref) => PriceHistoryRepository(ref.watch(apiClientProvider)),
);
