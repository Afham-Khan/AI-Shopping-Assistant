import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/network/api_client.dart';
import '../../auth/providers/auth_controller.dart';

/// Number of items in the cart, shown on the Cart tab badge.
///
/// Reads `GET /cart` → `summary.itemCount`; 0 for guests; reloads on login/logout.
/// The cart feature should keep it in sync after every mutation — every cart
/// endpoint returns the full Cart, so just push the new count:
/// ```dart
/// ref.read(cartCountProvider.notifier).set(cart.summary.itemCount);
/// // or, when you don't have the cart at hand:
/// ref.read(cartCountProvider.notifier).refresh();
/// ```
final cartCountProvider = NotifierProvider<CartCountController, int>(CartCountController.new);

class CartCountController extends Notifier<int> {
  @override
  int build() {
    final signedIn = ref.watch(isAuthenticatedProvider);
    if (signedIn) Future.microtask(refresh);
    return 0;
  }

  Future<void> refresh() async {
    if (!ref.read(isAuthenticatedProvider)) {
      state = 0;
      return;
    }
    try {
      final count = await ref.read(apiClientProvider).get(
        '/cart',
        decode: (d) => JsonX.asInt(JsonX.asMap(JsonX.asMap(d)['summary'])['itemCount']),
      );
      if (ref.mounted) state = count;
    } on ApiException {
      // badge is non-critical; keep the last known value
    }
  }

  void set(int count) => state = count < 0 ? 0 : count;
}
