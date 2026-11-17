import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/network/api_exception.dart';
import 'core/storage/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // clean web URLs (/product/12 instead of /#/product/12); no-op on mobile
  usePathUrlStrategy();

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      retry: _retry,
      child: const ZeloraApp(),
    ),
  );
}

/// Providers retry only transient network failures (twice), never 4xx errors,
/// so error states show up promptly with a manual "Try again".
Duration? _retry(int retryCount, Object error) {
  if (retryCount >= 2) return null;
  if (error is ApiException && error.isNetwork) return Duration(seconds: 2 * (retryCount + 1));
  return null;
}
