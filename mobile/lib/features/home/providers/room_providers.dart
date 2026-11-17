import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../../core/storage/local_storage.dart';
import '../../ai/data/models/ai_models.dart';
import '../data/room_repository.dart';
import '../presentation/room/room_layout.dart';

/// The room's zones (geometry + API data). Never empty: zones whose data
/// failed to load still render, just without products.
final roomZonesProvider = FutureProvider.autoDispose<List<RoomZone>>((ref) async {
  final data = await ref.watch(roomRepositoryProvider).room();
  return RoomLayout.merge(data);
});

/// Zones the shopper has opened at least once ("3/7 explored"), persisted.
final roomExploredProvider = NotifierProvider<RoomExploredController, Set<String>>(RoomExploredController.new);

class RoomExploredController extends Notifier<Set<String>> {
  static const storageKey = 'home.room.explored';

  @override
  Set<String> build() {
    try {
      return ref.read(sharedPreferencesProvider).getStringList(storageKey)?.toSet() ?? <String>{};
    } catch (_) {
      return <String>{};
    }
  }

  void mark(String zoneId) {
    if (state.contains(zoneId)) return;
    state = {...state, zoneId};
    try {
      ref.read(sharedPreferencesProvider).setStringList(storageKey, state.toList());
    } catch (_) {
      // persistence is a nicety
    }
  }
}

/// A product placed in the room by "Build my setup".
@immutable
class PlacedItem {
  const PlacedItem({required this.product, required this.zoneId, required this.role});

  final ProductSummary product;

  /// Zone id, or null for the rug (no matching zone).
  final String? zoneId;
  final String role;
}

/// The furnished setup: what the bundle chose and where each piece landed.
@immutable
class RoomSetup {
  const RoomSetup({required this.title, required this.budget, required this.items});

  final String title;
  final double budget;
  final List<PlacedItem> items;

  double get total => items.fold(0, (sum, i) => sum + i.product.price);
  bool get overBudget => budget > 0 && total > budget;

  List<PlacedItem> inZone(String? zoneId) => [for (final i in items) if (i.zoneId == zoneId) i];
}

/// The current setup (null until the shopper builds one). Survives tab
/// switches for the session.
final roomSetupProvider = NotifierProvider<RoomSetupController, RoomSetup?>(RoomSetupController.new);

class RoomSetupController extends Notifier<RoomSetup?> {
  @override
  RoomSetup? build() => null;

  RoomSetup place(BundleResult bundle, List<RoomZone> zones) {
    final setup = RoomSetup(
      title: bundle.title,
      budget: bundle.budget,
      items: [
        for (final item in bundle.items)
          PlacedItem(
            product: item.product,
            zoneId: RoomLayout.zoneForProduct(item.product, zones),
            role: item.role,
          ),
      ],
    );
    state = setup;
    return setup;
  }

  void clear() => state = null;
}
