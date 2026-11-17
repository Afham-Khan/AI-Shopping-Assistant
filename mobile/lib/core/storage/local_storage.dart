import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app-wide [SharedPreferences] instance.
///
/// It is loaded once in `main()` and injected with
/// `sharedPreferencesProvider.overrideWithValue(prefs)`, so reads are sync.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider in main()'),
);

/// Every key the app persists, in one place to avoid collisions.
abstract final class StorageKeys {
  static const accessToken = 'auth.accessToken';
  static const refreshToken = 'auth.refreshToken';
  static const cachedUser = 'auth.user';
  static const guestChosen = 'auth.guestChosen';
  static const onboardingDone = 'app.onboardingDone';
  static const themeMode = 'app.themeMode';
  static const serverUrl = 'app.serverUrl';
  static const aiShowReasoning = 'ai.showReasoning';
}
