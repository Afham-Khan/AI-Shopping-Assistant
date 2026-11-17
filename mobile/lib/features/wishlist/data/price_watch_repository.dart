import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'price_watch_models.dart';

/// A saved watch plus the server's note ("Watching iPhone 13 Pro").
typedef PriceWatchSaved = ({PriceWatch watch, String? message});

/// `/alerts/price-watch` (all require auth).
class PriceWatchRepository {
  PriceWatchRepository(this._api);

  final ApiClient _api;

  Future<List<PriceWatch>> list() => _api.get('/alerts/price-watch', decode: (d) => decodeList(d, PriceWatch.fromJson));

  /// Creates or updates (idempotent per product). `targetPrice: null` = any drop.
  Future<PriceWatchSaved> save({required int productId, double? targetPrice, bool notifyRestock = true}) async {
    final envelope = await _api.send(
      'POST',
      '/alerts/price-watch',
      body: {'productId': productId, 'targetPrice': targetPrice, 'notifyRestock': notifyRestock},
    );
    final data = envelope.data;
    if (data is! Map) throw const ApiException('Unexpected data from the server.', code: 'PARSE_ERROR');
    return (watch: PriceWatch.fromJson(Map<String, dynamic>.from(data)), message: envelope.message);
  }

  Future<String?> remove(int productId) async {
    final envelope = await _api.send('DELETE', '/alerts/price-watch/$productId');
    return envelope.message;
  }
}

final priceWatchRepositoryProvider = Provider<PriceWatchRepository>(
  (ref) => PriceWatchRepository(ref.watch(apiClientProvider)),
);
