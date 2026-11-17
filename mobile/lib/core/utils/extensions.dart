import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

extension BuildContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  TextTheme get textTheme => Theme.of(this).textTheme;
  ColorScheme get colorScheme => Theme.of(this).colorScheme;

  /// Semantic design tokens (background, border, muted, sale, ai…).
  AppPalette get colors => Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// ≥ 700 px wide: tablet / desktop layouts.
  bool get isWide => screenWidth >= Breakpoints.compact;

  /// ≥ 1100 px wide: desktop layouts (extended rail, 2-pane pages).
  bool get isDesktop => screenWidth >= Breakpoints.expanded;

  /// Bottom bar only on narrow portrait screens; everything else gets a rail.
  bool get useBottomNav {
    final size = MediaQuery.sizeOf(this);
    return size.width < Breakpoints.compact && size.height >= size.width;
  }

  /// Horizontal page gutter for the current width.
  double get pagePadding => isWide ? AppSpacing.pageWide : AppSpacing.page;

  /// True when the OS asks for reduced motion — skip decorative animation.
  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// Duration that collapses to zero under reduced motion.
  Duration motion(Duration duration) => reduceMotion ? Duration.zero : duration;

  void unfocus() => FocusScope.of(this).unfocus();
}

extension StringX on String {
  String get capitalized => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  /// `smart-watches` → `Smart Watches`.
  String get titleCase => split(RegExp(r'[\s_-]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w.capitalized)
      .join(' ');

  /// Initials for avatars: `Ali Khan` → `AK`.
  String get initials {
    final parts = trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

extension NullableStringX on String? {
  bool get isNullOrEmpty => this == null || this!.trim().isEmpty;
}
