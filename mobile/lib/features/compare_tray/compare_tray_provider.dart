import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/product.dart';

/// Products picked for comparison (max [CompareTrayController.maxItems]),
/// kept for the session. Drives [CompareTrayBar] and the "Compare" toggles.
///
/// ```dart
/// final added = ref.read(compareTrayProvider.notifier).toggle(product); // false when full
/// final inTray = ref.watch(compareTrayProvider.select((l) => l.any((p) => p.id == id)));
/// context.push(Routes.compareOf(ref.read(compareTrayProvider.notifier).ids));
/// ```
final compareTrayProvider = NotifierProvider<CompareTrayController, List<ProductSummary>>(
  CompareTrayController.new,
);

enum CompareToggleResult { added, removed, full }

class CompareTrayController extends Notifier<List<ProductSummary>> {
  static const maxItems = 4;

  @override
  List<ProductSummary> build() => const [];

  List<int> get ids => [for (final p in state) p.id];

  bool contains(int productId) => state.any((p) => p.id == productId);

  CompareToggleResult toggle(ProductSummary product) {
    if (contains(product.id)) {
      remove(product.id);
      return CompareToggleResult.removed;
    }
    if (state.length >= maxItems) return CompareToggleResult.full;
    state = [...state, product];
    return CompareToggleResult.added;
  }

  void remove(int productId) => state = [for (final p in state) if (p.id != productId) p];

  void clear() => state = const [];
}
