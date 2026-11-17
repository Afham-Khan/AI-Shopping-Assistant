import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../storage/local_storage.dart';

/// Current [ThemeMode] (system / light / dark), persisted across launches.
/// Defaults to light: the airy lavender-and-royal-blue theme is Zelora's
/// identity. Dark (derived from the same hues) is available in Settings.
///
/// `ref.watch(themeModeProvider)` / `ref.read(themeModeProvider.notifier).set(ThemeMode.dark)`.
final themeModeProvider = NotifierProvider<ThemeController, ThemeMode>(ThemeController.new);

class ThemeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final saved = ref.read(sharedPreferencesProvider).getString(StorageKeys.themeMode);
    return ThemeMode.values.firstWhere((m) => m.name == saved, orElse: () => ThemeMode.light);
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(StorageKeys.themeMode, mode.name);
  }
}
