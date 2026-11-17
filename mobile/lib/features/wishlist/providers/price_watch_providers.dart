import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/price_watch_models.dart';
import '../data/price_watch_repository.dart';

/// Every price watch of the signed-in user (newest first). Empty for guests.
/// One shared request feeds the product page, the wishlist badges and the
/// "Price alerts" screen.
final priceWatchesProvider = AsyncNotifierProvider<PriceWatchController, List<PriceWatch>>(PriceWatchController.new);

/// The watch on one product (null when not watching). Rebuilds only when that
/// product's watch changes.
final priceWatchForProvider = Provider.autoDispose.family<PriceWatch?, int>(
  (ref, productId) => ref.watch(
    priceWatchesProvider.select((async) => async.value?.where((w) => w.productId == productId).firstOrNull),
  ),
);

class PriceWatchController extends AsyncNotifier<List<PriceWatch>> {
  PriceWatchRepository get _repo => ref.read(priceWatchRepositoryProvider);

  @override
  Future<List<PriceWatch>> build() {
    if (!ref.watch(isAuthenticatedProvider)) return Future.value(const []);
    return ref.watch(priceWatchRepositoryProvider).list();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Starts or updates a watch. Throws `ApiException` (field errors map to
  /// `targetPrice`). Returns the server's note for a toast.
  Future<String?> save(ProductSummary product, {double? targetPrice, required bool notifyRestock}) async {
    final saved = await _repo.save(productId: product.id, targetPrice: targetPrice, notifyRestock: notifyRestock);
    if (!ref.mounted) return saved.message;
    final others = [for (final w in state.value ?? const <PriceWatch>[]) if (w.productId != product.id) w];
    // the response may omit the product card on older servers: keep the one we know
    final watch = saved.watch.product.title.isEmpty
        ? PriceWatch(
            id: saved.watch.id,
            product: product,
            targetPrice: saved.watch.targetPrice,
            notifyRestock: saved.watch.notifyRestock,
            initialPrice: saved.watch.initialPrice,
            createdAt: saved.watch.createdAt,
            status: saved.watch.status,
          )
        : saved.watch;
    state = AsyncData([watch, ...others]);
    return saved.message;
  }

  /// Stops watching. Throws `ApiException`. Returns the server's note.
  Future<String?> remove(int productId) async {
    final message = await _repo.remove(productId);
    if (ref.mounted) {
      state = AsyncData([for (final w in state.value ?? const <PriceWatch>[]) if (w.productId != productId) w]);
    }
    return message;
  }
}
