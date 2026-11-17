import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_storage.dart';

/// Holds the access/refresh token pair.
///
/// Values are cached in memory (sync reads for every request) and mirrored to
/// SharedPreferences so the session survives restarts. Not secure storage —
/// fine for this project, swap for flutter_secure_storage in production.
class TokenStore {
  TokenStore(this._prefs)
    : _access = _prefs.getString(StorageKeys.accessToken),
      _refresh = _prefs.getString(StorageKeys.refreshToken);

  final SharedPreferences _prefs;
  String? _access;
  String? _refresh;

  final _expired = StreamController<void>.broadcast();

  String? get accessToken => _access;
  String? get refreshToken => _refresh;
  bool get hasSession => _refresh != null;

  /// Fires when the API client gives up on the session (refresh failed).
  /// The auth controller listens and switches to guest.
  Stream<void> get sessionExpired => _expired.stream;

  Future<void> save({required String accessToken, required String refreshToken}) async {
    _access = accessToken;
    _refresh = refreshToken;
    await Future.wait([
      _prefs.setString(StorageKeys.accessToken, accessToken),
      _prefs.setString(StorageKeys.refreshToken, refreshToken),
    ]);
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    await Future.wait([
      _prefs.remove(StorageKeys.accessToken),
      _prefs.remove(StorageKeys.refreshToken),
    ]);
  }

  /// Clears tokens and notifies listeners that the session is gone.
  Future<void> expire() async {
    await clear();
    _expired.add(null);
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) {
  return TokenStore(ref.watch(sharedPreferencesProvider));
});
