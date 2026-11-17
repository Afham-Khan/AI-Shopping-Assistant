import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/local_storage.dart';

/// Resolved runtime configuration (server address + helpers).
///
/// Base URL priority:
///   1. `--dart-define=API_BASE_URL=http://192.168.1.5:5000`
///   2. the address saved in Settings → Server address
///   3. platform default (web: same host as the page, Android emulator:
///      10.0.2.2, everything else: localhost)
@immutable
class AppConfig {
  const AppConfig(this.baseUrl);

  static const appName = 'Zelora';
  static const appVersion = '0.1.0';
  static const apiPrefix = '/api/v1';

  /// Value passed with --dart-define, or empty.
  static const envBaseUrl = String.fromEnvironment('API_BASE_URL');
  static bool get isEnvOverridden => envBaseUrl.isNotEmpty;

  static String get platformDefault {
    // on web, follow the page's host so LAN testing (http://192.168.x.x) works too
    if (kIsWeb) {
      final host = Uri.base.host.isEmpty ? 'localhost' : Uri.base.host;
      return 'http://$host:5000';
    }
    // the android emulator reaches the host machine through 10.0.2.2
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:5000';
    return 'http://localhost:5000';
  }

  /// Server origin without trailing slash, e.g. `http://localhost:5000`.
  final String baseUrl;

  /// REST root, e.g. `http://localhost:5000/api/v1`.
  String get apiUrl => '$baseUrl$apiPrefix';

  /// Makes server-relative image paths (`/uploads/...`) absolute.
  /// Returns null for null/empty input so widgets can show a fallback.
  String? resolveImage(String? url) => resolveAgainst(baseUrl, url);

  static String? resolveAgainst(String baseUrl, String? url) {
    if (url == null) return null;
    final value = url.trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('data:') ||
        value.startsWith('blob:')) {
      return value;
    }
    if (value.startsWith('//')) return 'http:$value';
    return value.startsWith('/') ? '$baseUrl$value' : '$baseUrl/$value';
  }

  /// Trims, adds `http://` when missing and drops trailing slashes / `/api/v1`.
  static String normalize(String input) {
    var value = input.trim();
    if (value.isEmpty) return value;
    if (!value.contains('://')) value = 'http://$value';
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.endsWith(apiPrefix)) value = value.substring(0, value.length - apiPrefix.length);
    return value;
  }

  /// True when [input] parses as an http(s) URL with a host.
  static bool isValidBaseUrl(String input) {
    final uri = Uri.tryParse(normalize(input));
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }
}

/// The server origin currently in use. Change it with
/// `ref.read(serverUrlProvider.notifier).set(url)`; every API call follows.
final serverUrlProvider = NotifierProvider<ServerUrlController, String>(ServerUrlController.new);

class ServerUrlController extends Notifier<String> {
  @override
  String build() {
    if (AppConfig.isEnvOverridden) return AppConfig.normalize(AppConfig.envBaseUrl);
    final saved = ref.read(sharedPreferencesProvider).getString(StorageKeys.serverUrl);
    return (saved == null || saved.isEmpty) ? AppConfig.platformDefault : saved;
  }

  /// True when the user saved a custom address in Settings.
  bool get isCustom => ref.read(sharedPreferencesProvider).containsKey(StorageKeys.serverUrl);

  Future<void> set(String url) async {
    final value = AppConfig.normalize(url);
    await ref.read(sharedPreferencesProvider).setString(StorageKeys.serverUrl, value);
    state = value;
  }

  Future<void> reset() async {
    await ref.read(sharedPreferencesProvider).remove(StorageKeys.serverUrl);
    state = build();
  }
}

final appConfigProvider = Provider<AppConfig>((ref) => AppConfig(ref.watch(serverUrlProvider)));
