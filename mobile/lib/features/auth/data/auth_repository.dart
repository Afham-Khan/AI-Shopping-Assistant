import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/token_store.dart';
import 'models/user.dart';

/// Auth & account endpoints. Stores tokens on successful sign-in.
///
/// Throws [ApiException] on failure (use `e.fieldError('email')` for forms).
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStore _tokens;

  Future<User> login({required String email, required String password}) =>
      _signIn('/auth/login', {'email': email.trim(), 'password': password});

  Future<User> register({required String name, required String email, required String password}) =>
      _signIn('/auth/register', {'name': name.trim(), 'email': email.trim(), 'password': password});

  /// Signs in the seeded demo account (for presentations).
  Future<User> demo() => _signIn('/auth/demo', null);

  Future<User> me() => _api.get('/auth/me', decode: (d) => User.fromJson(d as Json));

  /// Revokes the refresh token server-side; local tokens are cleared regardless.
  Future<void> logout() async {
    final refresh = _tokens.refreshToken;
    try {
      if (refresh != null) await _api.post<void>('/auth/logout', body: {'refreshToken': refresh});
    } on ApiException {
      // signing out must always succeed locally
    } finally {
      await _tokens.clear();
    }
  }

  /// Step 1: emails a 6-digit code (always succeeds — no account enumeration).
  Future<void> forgotPassword(String email) =>
      _api.post<void>('/auth/forgot-password', body: {'email': email.trim()});

  /// Step 2: exchanges the code for a short-lived reset token.
  Future<String> verifyOtp({required String email, required String otp}) => _api.post(
    '/auth/verify-otp',
    body: {'email': email.trim(), 'otp': otp.trim()},
    decode: (d) => (d as Json)['resetToken'] as String,
  );

  /// Step 3: sets the new password (signs out all devices server-side).
  Future<void> resetPassword({required String resetToken, required String password}) =>
      _api.post<void>('/auth/reset-password', body: {'resetToken': resetToken, 'password': password});

  /// PUT /users/me/preferences — also marks the user as onboarded.
  Future<User> savePreferences({
    required List<String> interests,
    double? budgetMin,
    double? budgetMax,
    String? gender,
  }) => _api.put(
    '/users/me/preferences',
    body: {
      'interests': interests,
      if (budgetMax != null) 'budget': {'min': budgetMin ?? 0, 'max': budgetMax},
      'gender': ?gender,
    },
    decode: (d) => User.fromJson(d as Json),
  );

  Future<User> _signIn(String path, Object? body) async {
    final data = await _api.post<Json>(path, body: body, decode: (d) => d as Json);
    await _tokens.save(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
    );
    return User.fromJson(data['user'] as Json);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider));
});
