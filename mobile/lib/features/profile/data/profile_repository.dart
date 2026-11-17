import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/network/api_client.dart';
import '../../auth/data/models/user.dart';
import 'models/address.dart';

/// `GET /users/me/stats`.
@immutable
class UserStats {
  const UserStats({this.orders = 0, this.wishlist = 0, this.reviews = 0, this.conversations = 0});

  factory UserStats.fromJson(Map<String, dynamic> json) => UserStats(
    orders: JsonX.asInt(json['orders']),
    wishlist: JsonX.asInt(json['wishlist']),
    reviews: JsonX.asInt(json['reviews']),
    conversations: JsonX.asInt(json['conversations']),
  );

  final int orders;
  final int wishlist;
  final int reviews;
  final int conversations;
}

/// Profile + address endpoints (all require auth).
class ProfileRepository {
  ProfileRepository(this._api);

  final ApiClient _api;

  Future<User> updateProfile({required String name, String? phone}) => _api.patch(
    '/users/me',
    body: {'name': name.trim(), 'phone': (phone == null || phone.trim().isEmpty) ? null : phone.trim()},
    decode: (d) => User.fromJson(d as Json),
  );

  Future<void> changePassword({required String currentPassword, required String newPassword}) => _api.post<void>(
    '/users/me/change-password',
    body: {'currentPassword': currentPassword, 'newPassword': newPassword},
  );

  Future<UserStats> stats() => _api.get('/users/me/stats', decode: (d) => UserStats.fromJson(d as Json));

  Future<List<Address>> addresses() => _api.get('/addresses', decode: (d) => decodeList(d, Address.fromJson));

  Future<Address> createAddress(Address a) =>
      _api.post('/addresses', body: a.toJson(), decode: (d) => Address.fromJson(d as Json));

  Future<Address> updateAddress(int id, Address a) =>
      _api.patch('/addresses/$id', body: a.toJson(), decode: (d) => Address.fromJson(d as Json));

  Future<void> deleteAddress(int id) => _api.delete<void>('/addresses/$id');

  Future<Address> setDefault(int id) =>
      _api.post('/addresses/$id/default', decode: (d) => Address.fromJson(d as Json));
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(apiClientProvider)));
