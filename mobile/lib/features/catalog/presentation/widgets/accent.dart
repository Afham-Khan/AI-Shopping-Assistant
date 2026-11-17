import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/extensions.dart';

/// A soft background + strong foreground pair derived from one accent color,
/// readable in both themes. Used for department tiles, chips and banners.
@immutable
class AccentTint {
  const AccentTint({required this.accent, required this.background, required this.foreground});

  factory AccentTint.of(BuildContext context, Color accent) {
    final dark = context.isDark;
    return AccentTint(
      accent: accent,
      background: accent.withValues(alpha: dark ? 0.18 : 0.10),
      // lift the hue on deep navy so text keeps contrast
      foreground: dark ? Color.lerp(accent, Colors.white, 0.35)! : accent,
    );
  }

  /// Tint for a department slug (`AppColors.departmentAccent`).
  factory AccentTint.department(BuildContext context, String? slug) =>
      AccentTint.of(context, AppColors.departmentAccent(slug));

  final Color accent;
  final Color background;
  final Color foreground;
}

/// Maps a banner's `theme` name onto palette tokens (no hard-coded hex).
Color bannerAccent(BuildContext context, String? theme) {
  final c = context.colors;
  return switch (theme) {
    'emerald' || 'green' => c.primary,
    'indigo' || 'blue' => c.secondary,
    'violet' || 'purple' => AppColors.departmentAccent('beauty-personal-care'),
    'rose' || 'pink' => AppColors.departmentAccent('fashion'),
    'amber' || 'orange' => AppColors.departmentAccent('sports-outdoors'),
    'teal' => AppColors.departmentAccent('automotive'),
    _ => c.primary,
  };
}
