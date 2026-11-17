import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_controller.dart';

/// Wishlist endpoints (all require auth).
class WishlistRepository {
  WishlistRepository(this._api);

  final ApiClient _api;

  Future<Set<int>> ids() => _api.get(
    '/wishlist/ids',
    decode: (d) => {for (final id in (d as List? ?? const [])) (id as num).toInt()},
  );

  Future<void> add(int productId) => _api.post<void>('/wishlist', body: {'productId': productId});

  Future<void> remove(int productId) => _api.delete<void>('/wishlist/$productId');
}

final wishlistRepositoryProvider = Provider<WishlistRepository>(
  (ref) => WishlistRepository(ref.watch(apiClientProvider)),
);

/// Ids of wishlisted products — drives every heart icon in the app.
///
/// Empty for guests; reloads on login/logout.
/// ```dart
/// final saved = ref.watch(wishlistIdsProvider).contains(product.id);
/// await ref.read(wishlistIdsProvider.notifier).toggle(product.id);
/// ```
/// The commerce dev's wishlist screen should call
/// `ref.read(wishlistIdsProvider.notifier).refresh()` after loading the list,
/// and may `ref.listen` this provider to drop removed items.
final wishlistIdsProvider = NotifierProvider<WishlistController, Set<int>>(WishlistController.new);

class WishlistController extends Notifier<Set<int>> {
  final _pending = <int>{};

  @override
  Set<int> build() {
    final signedIn = ref.watch(isAuthenticatedProvider);
    if (signedIn) Future.microtask(refresh);
    return const {};
  }

  WishlistRepository get _repo => ref.read(wishlistRepositoryProvider);

  bool contains(int productId) => state.contains(productId);

  /// Reloads ids from the server (errors are ignored: hearts just stay as they are).
  Future<void> refresh() async {
    if (!ref.read(isAuthenticatedProvider)) return;
    try {
      final ids = await _repo.ids();
      if (ref.mounted) state = ids;
    } on ApiException {
      // non-critical
    }
  }

  /// Optimistically flips [productId]; rolls back and rethrows [ApiException] on failure.
  /// Returns the new saved state. Throws `ApiException(code: AUTH_REQUIRED)` for guests.
  Future<bool> toggle(int productId) async {
    if (!ref.read(isAuthenticatedProvider)) {
      throw const ApiException('Sign in to save items', statusCode: 401, code: ApiException.authRequired);
    }
    // ignore rapid double taps while a request for this product is in flight
    if (_pending.contains(productId)) return state.contains(productId);

    final wasSaved = state.contains(productId);
    _set(productId, !wasSaved);
    _pending.add(productId);
    try {
      wasSaved ? await _repo.remove(productId) : await _repo.add(productId);
      return !wasSaved;
    } on ApiException {
      if (ref.mounted) _set(productId, wasSaved);
      rethrow;
    } finally {
      _pending.remove(productId);
    }
  }

  void _set(int productId, bool saved) {
    state = saved ? {...state, productId} : ({...state}..remove(productId));
  }
}

/// Top-level helper matching the spec name: `await toggleWishlist(ref, id)`.
Future<bool> toggleWishlist(WidgetRef ref, int productId) =>
    ref.read(wishlistIdsProvider.notifier).toggle(productId);
