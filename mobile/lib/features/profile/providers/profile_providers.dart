import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_controller.dart';
import '../data/models/address.dart';
import '../data/profile_repository.dart';

/// Counts on the account screen. Null-safe for guests (never fetched).
final userStatsProvider = FutureProvider.autoDispose<UserStats>((ref) {
  if (!ref.watch(isAuthenticatedProvider)) return const UserStats();
  return ref.watch(profileRepositoryProvider).stats();
});

/// Saved addresses (default first). Shared by the addresses screen and checkout.
final addressesProvider = AsyncNotifierProvider.autoDispose<AddressesController, List<Address>>(
  AddressesController.new,
);

class AddressesController extends AsyncNotifier<List<Address>> {
  ProfileRepository get _repo => ref.read(profileRepositoryProvider);

  @override
  Future<List<Address>> build() {
    if (!ref.watch(isAuthenticatedProvider)) return Future.value(const []);
    return ref.watch(profileRepositoryProvider).addresses();
  }

  Future<Address> save(Address address, {int? id}) async {
    final saved = id == null ? await _repo.createAddress(address) : await _repo.updateAddress(id, address);
    await _reload();
    return saved;
  }

  Future<void> delete(int id) async {
    await _repo.deleteAddress(id);
    // the server may promote another address to default, so reload
    await _reload();
  }

  Future<void> setDefault(int id) async {
    final current = state.value ?? const [];
    // optimistic: move the badge right away
    state = AsyncData(_sorted([for (final a in current) _withDefault(a, a.id == id)]));
    try {
      await _repo.setDefault(id);
    } finally {
      await _reload();
    }
  }

  Future<void> _reload() async {
    final list = await _repo.addresses();
    if (ref.mounted) state = AsyncData(list);
  }

  static List<Address> _sorted(List<Address> list) =>
      [...list.where((a) => a.isDefault), ...list.where((a) => !a.isDefault)];

  static Address _withDefault(Address a, bool isDefault) => Address(
    id: a.id,
    label: a.label,
    fullName: a.fullName,
    phone: a.phone,
    line1: a.line1,
    line2: a.line2,
    city: a.city,
    province: a.province,
    postalCode: a.postalCode,
    country: a.country,
    isDefault: isDefault,
  );
}
