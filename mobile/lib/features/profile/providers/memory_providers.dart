import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../ai/providers/ai_providers.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/memory_models.dart';
import '../data/memory_repository.dart';

/// What Zelora remembers, plus the consent switch and "forget everything".
final shoppingMemoryProvider = AsyncNotifierProvider.autoDispose<ShoppingMemoryController, ShoppingMemory>(
  ShoppingMemoryController.new,
);

class ShoppingMemoryController extends AsyncNotifier<ShoppingMemory> {
  MemoryRepository get _repo => ref.read(memoryRepositoryProvider);

  @override
  Future<ShoppingMemory> build() {
    if (!ref.watch(isAuthenticatedProvider)) return Future.value(const ShoppingMemory());
    return ref.watch(memoryRepositoryProvider).get();
  }

  /// Optimistic; rolls back and rethrows [ApiException] on failure.
  Future<String?> setEnabled(bool enabled) async {
    final before = state.value ?? const ShoppingMemory();
    state = AsyncData(before.copyWith(enabled: enabled));
    try {
      return await _repo.setEnabled(enabled);
    } on ApiException {
      if (ref.mounted) state = AsyncData(before);
      rethrow;
    }
  }

  /// Deletes everything Zel learned, then reloads the (now empty) snapshot.
  /// Throws [ApiException]; the confirm dialog shows it.
  Future<String?> forgetAll() async {
    final before = state.value ?? const ShoppingMemory();
    final message = await _repo.forgetAll();
    if (!ref.mounted) return message;
    state = AsyncData(before.cleared());
    // Shopping DNA and picks were built from the same signals
    ref.invalidate(shoppingProfileProvider);
    ref.invalidate(recommendationsProvider);
    try {
      final fresh = await _repo.get();
      if (ref.mounted) state = AsyncData(fresh);
    } on ApiException {
      // the cleared state above is already right
    }
    return message;
  }
}
