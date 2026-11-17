import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import 'memory_models.dart';

/// `/users/me/memory` (all require auth).
class MemoryRepository {
  MemoryRepository(this._api);

  final ApiClient _api;

  Future<ShoppingMemory> get() => _api.get('/users/me/memory', decode: ShoppingMemory.fromJson);

  /// Turns learning on or off. Returns the server's note ("Shopping memory is off").
  Future<String?> setEnabled(bool enabled) async {
    final envelope = await _api.send('PUT', '/users/me/memory', body: {'enabled': enabled});
    return envelope.message;
  }

  /// Deletes what Zel learned (browsing signals, searches, chat context).
  Future<String?> forgetAll() async {
    final envelope = await _api.send('DELETE', '/users/me/memory');
    return envelope.message;
  }
}

final memoryRepositoryProvider = Provider<MemoryRepository>((ref) => MemoryRepository(ref.watch(apiClientProvider)));
