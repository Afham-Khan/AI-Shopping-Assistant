import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/local_storage.dart';
import '../../../core/storage/token_store.dart';
import '../data/auth_repository.dart';
import '../data/models/user.dart';

enum AuthStatus {
  /// Restoring the session on launch.
  unknown,
  authenticated,

  /// Not signed in (browsing as a guest).
  guest,
}

@immutable
class AuthState {
  const AuthState._(this.status, this.user, {this.guestChosen = false});

  const AuthState.unknown() : this._(AuthStatus.unknown, null);
  const AuthState.authenticated(User user) : this._(AuthStatus.authenticated, user);
  const AuthState.guest({bool guestChosen = false}) : this._(AuthStatus.guest, null, guestChosen: guestChosen);

  final AuthStatus status;
  final User? user;

  /// The guest explicitly tapped "Continue as guest" (skip login on next launch).
  final bool guestChosen;

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isGuest => status == AuthStatus.guest;
  bool get isUnknown => status == AuthStatus.unknown;
}

/// Session state for the whole app.
///
/// ```dart
/// final auth = ref.watch(authControllerProvider);   // AuthState
/// if (auth.isAuthenticated) Text('Hi ${auth.user!.firstName}');
/// await ref.read(authControllerProvider.notifier).login(email: e, password: p);
/// ```
/// Sign-in methods throw [ApiException]; on success the router redirects
/// automatically (to `from`, or to the interests screen for new users).
final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

/// Convenience: the signed-in user or null.
final currentUserProvider = Provider<User?>((ref) => ref.watch(authControllerProvider).user);

/// Convenience: true when signed in. Watch this in providers that must
/// refetch on login/logout (cart, wishlist, recommendations…).
final isAuthenticatedProvider = Provider<bool>(
  (ref) => ref.watch(authControllerProvider.select((s) => s.isAuthenticated)),
);

class AuthController extends Notifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  @override
  AuthState build() {
    final sub = ref.read(tokenStoreProvider).sessionExpired.listen((_) => _onSessionExpired());
    ref.onDispose(sub.cancel);
    Future.microtask(_restore);
    return const AuthState.unknown();
  }

  /// Restores the session instantly from cache, then validates it in the
  /// background so a slow/offline server never blocks app start.
  Future<void> _restore() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final guestChosen = prefs.getBool(StorageKeys.guestChosen) ?? false;

    if (!_tokens.hasSession) {
      state = AuthState.guest(guestChosen: guestChosen);
      return;
    }

    final cached = _readCachedUser();
    if (cached != null) {
      state = AuthState.authenticated(cached);
      unawaited(refreshUser());
      return;
    }

    try {
      _setUser(await _repo.me());
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _tokens.clear();
        state = AuthState.guest(guestChosen: guestChosen);
      } else {
        // offline with tokens but no cached profile: keep the session, show a placeholder user
        state = const AuthState.authenticated(User(id: 0, name: 'Shopper', email: ''));
      }
    }
  }

  Future<void> login({required String email, required String password}) async {
    _setUser(await _repo.login(email: email, password: password));
  }

  Future<void> register({required String name, required String email, required String password}) async {
    _setUser(await _repo.register(name: name, email: email, password: password));
  }

  Future<void> demoLogin() async => _setUser(await _repo.demo());

  Future<void> logout() async {
    await _repo.logout();
    await _clearLocal();
    state = const AuthState.guest();
  }

  /// "Continue as guest" — remembered so the next launch skips the login screen.
  Future<void> continueAsGuest() async {
    await ref.read(sharedPreferencesProvider).setBool(StorageKeys.guestChosen, true);
    state = const AuthState.guest(guestChosen: true);
  }

  /// Re-fetches `/auth/me` (e.g. after editing the profile elsewhere).
  Future<void> refreshUser() async {
    if (!state.isAuthenticated) return;
    try {
      _setUser(await _repo.me());
    } on ApiException {
      // keep the cached user; a 401 is handled by the API client (session expiry)
    }
  }

  /// Replace the user locally after an API call returned an updated `User`
  /// (PATCH /users/me, PUT /users/me/preferences).
  void updateUser(User user) {
    if (!state.isAuthenticated) return;
    _setUser(user);
  }

  /// Saves interests/budget/gender and updates the session user.
  Future<void> savePreferences({
    required List<String> interests,
    double? budgetMin,
    double? budgetMax,
    String? gender,
  }) async {
    final user = await _repo.savePreferences(
      interests: interests,
      budgetMin: budgetMin,
      budgetMax: budgetMax,
      gender: gender,
    );
    updateUser(user);
  }

  // forgot-password flow (no session change; screens hold the step state)
  Future<void> requestPasswordReset(String email) => _repo.forgotPassword(email);

  Future<String> verifyResetCode({required String email, required String otp}) =>
      _repo.verifyOtp(email: email, otp: otp);

  Future<void> resetPassword({required String resetToken, required String password}) =>
      _repo.resetPassword(resetToken: resetToken, password: password);

  // ---------- internals ----------

  void _setUser(User user) {
    state = AuthState.authenticated(user);
    final prefs = ref.read(sharedPreferencesProvider);
    unawaited(prefs.setString(StorageKeys.cachedUser, jsonEncode(user.toJson())));
    unawaited(prefs.remove(StorageKeys.guestChosen));
  }

  User? _readCachedUser() {
    final raw = ref.read(sharedPreferencesProvider).getString(StorageKeys.cachedUser);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _clearLocal() async {
    await ref.read(sharedPreferencesProvider).remove(StorageKeys.cachedUser);
  }

  Future<void> _onSessionExpired() async {
    if (!state.isAuthenticated) return;
    await _clearLocal();
    state = const AuthState.guest();
  }
}
