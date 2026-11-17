import 'package:material_ui/material_ui.dart';

/// Raw Zelora color tokens. Widgets should read the theme-aware [AppPalette]
/// (`context.colors`) rather than these constants.
///
/// Identity v2 — "airy royal": a soft lavender-blue page with a gentle wash
/// of light from the top, pure white rounded cards with very soft shadows,
/// ONE confident royal blue, dark navy ink, slate secondary text. Calm red
/// for discounts, amber for rating stars. Light is the primary theme; dark is
/// derived from the same hues (deep navy, lighter periwinkle accent).
abstract final class AppColors {
  // brand — Zelora royal blue (5.17:1 with white, 4.58:1 on the page wash)
  static const blue = Color(0xFF2563EB);
  static const blueHover = Color(0xFF1D4ED8);
  static const blueSoft = Color(0xFFEDF2FE);

  /// Dark-theme accent: a lighter periwinkle that reads on navy (6.9:1 on
  /// the dark surface) with navy ink on top.
  static const blueLight = Color(0xFF7AA2FF);
  static const blueLightHover = Color(0xFF94B4FF);
  static const navy = Color(0xFF0F172A);

  // light — lavender-blue page, white cards, navy ink
  static const lightBackground = Color(0xFFEEF1FB);
  static const lightBackgroundTop = Color(0xFFF3F5FD);
  static const lightBackgroundBottom = Color(0xFFE6EAF8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFF4F6FC);
  static const lightSurfaceRaised = Color(0xFFE9EDF8);
  static const lightBorder = Color(0xFFE3E8F4);
  static const lightBorderStrong = Color(0xFFC9D2E6);
  static const lightText = navy;
  static const lightMuted = Color(0xFF5B6478);
  static const lightFaint = Color(0xFF6B7489);

  // dark — deep navy derived from the same hue family
  static const darkBackground = Color(0xFF0B1020);
  static const darkBackgroundTop = Color(0xFF10172C);
  static const darkBackgroundBottom = Color(0xFF0A0E1C);
  static const darkSurface = Color(0xFF141B2E);
  static const darkSurfaceVariant = Color(0xFF1A2238);
  static const darkSurfaceRaised = Color(0xFF222B44);
  static const darkBorder = Color(0xFF252E47);
  static const darkBorderStrong = Color(0xFF36415F);
  static const darkText = Color(0xFFE8ECF6);
  static const darkMuted = Color(0xFFA3ADC4);
  static const darkFaint = Color(0xFF8790AB);

  // semantic
  static const red = Color(0xFFDC2626);
  static const redLight = Color(0xFFFF7A7A);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFBBF24);
  static const green = Color(0xFF15803D);
  static const sky = Color(0xFF0369A1);
  static const violet = Color(0xFF7C3AED);

  // legacy names kept so older call sites compile — all point at v2 values
  // (there is no mint/teal anywhere any more)
  static const mint = blue;
  static const mintHover = blueHover;
  static const mintDeep = blue;
  static const mintDeepHover = blueHover;
  static const coral = red;
  static const emerald = green;
  static const emeraldBright = Color(0xFF4ADE80);
  static const ocean = sky;
  static const oceanBright = Color(0xFF38BDF8);
  static const cyan = Color(0xFF0891B2);
  static const aiStart = blue;
  static const aiMid = blue;
  static const aiEnd = blue;
  static const ai = blue;
  static const sale = red;
  static const success = green;
  static const warning = Color(0xFFB45309);
  static const star = amber;
  static const error = red;
  static const errorDark = redLight;

  /// Flat on purpose: the design system has no loud gradients. Kept as a
  /// [LinearGradient] only because older code asks for one.
  static const aiGradient = LinearGradient(colors: [blue, blue]);
  static const brandGradient = LinearGradient(colors: [blue, blue]);

  // Department hues: calm mid-tones that read on both themes. Use them as a
  // small icon tint, a 6 px dot or a soft 10 % tile behind an icon — never
  // as a loud fill or for body text.
  static const _departmentAccents = <String, Color>{
    'electronics': Color(0xFF3B82F6),
    'fashion': Color(0xFFEC4899),
    'beauty-personal-care': Color(0xFF8B5CF6),
    'home-living': Color(0xFFF59E0B),
    'groceries': Color(0xFF22A06B),
    'sports-outdoors': Color(0xFFF97316),
    'automotive': Color(0xFF0EA5E9),
  };
  static const _fallbackAccents = [
    Color(0xFF3B82F6),
    Color(0xFF22A06B),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF97316),
    Color(0xFF0EA5E9),
    Color(0xFFF59E0B),
  ];

  /// Accent for a department slug; unknown slugs get a stable color from the palette.
  static Color departmentAccent(String? slug) {
    if (slug == null) return _fallbackAccents[1];
    return _departmentAccents[slug] ?? _fallbackAccents[slug.hashCode.abs() % _fallbackAccents.length];
  }
}

/// Theme-aware semantic colors, available via `context.colors`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceRaised,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.muted,
    required this.faint,
    required this.primary,
    required this.primaryHover,
    required this.onPrimary,
    required this.primarySoft,
    required this.secondary,
    required this.secondarySoft,
    required this.error,
    required this.sale,
    required this.onSale,
    required this.saleSoft,
    required this.success,
    required this.warning,
    required this.star,
    required this.purple,
    required this.ai,
    required this.aiSoft,
    required this.imageWell,
    required this.onImageWell,
    required this.grid,
    required this.shadow,
  });

  static const light = AppPalette(
    background: AppColors.lightBackground,
    backgroundTop: AppColors.lightBackgroundTop,
    backgroundBottom: AppColors.lightBackgroundBottom,
    surface: AppColors.lightSurface,
    surfaceVariant: AppColors.lightSurfaceVariant,
    surfaceRaised: AppColors.lightSurfaceRaised,
    border: AppColors.lightBorder,
    borderStrong: AppColors.lightBorderStrong,
    text: AppColors.lightText,
    muted: AppColors.lightMuted,
    faint: AppColors.lightFaint,
    primary: AppColors.blue,
    primaryHover: AppColors.blueHover,
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: AppColors.blueSoft,
    secondary: AppColors.sky,
    secondarySoft: Color(0xFFE0F2FE),
    error: AppColors.red,
    sale: AppColors.red,
    onSale: Color(0xFFFFFFFF),
    saleSoft: Color(0xFFFDECEC),
    success: AppColors.green,
    warning: Color(0xFFB45309),
    star: AppColors.amber,
    purple: AppColors.violet,
    ai: AppColors.blue,
    aiSoft: AppColors.blueSoft,
    imageWell: Color(0xFFF3F5FA),
    onImageWell: AppColors.navy,
    grid: Color(0xFFDDE3F1),
    shadow: Color(0x661E2A5A),
  );

  static const dark = AppPalette(
    background: AppColors.darkBackground,
    backgroundTop: AppColors.darkBackgroundTop,
    backgroundBottom: AppColors.darkBackgroundBottom,
    surface: AppColors.darkSurface,
    surfaceVariant: AppColors.darkSurfaceVariant,
    surfaceRaised: AppColors.darkSurfaceRaised,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorderStrong,
    text: AppColors.darkText,
    muted: AppColors.darkMuted,
    faint: AppColors.darkFaint,
    primary: AppColors.blueLight,
    primaryHover: AppColors.blueLightHover,
    onPrimary: Color(0xFF0A1A3F),
    primarySoft: Color(0xFF1C2850),
    secondary: Color(0xFF38BDF8),
    secondarySoft: Color(0xFF0E2A3D),
    error: AppColors.redLight,
    sale: AppColors.redLight,
    onSale: Color(0xFF2A0707),
    saleSoft: Color(0xFF3A1C24),
    success: Color(0xFF4ADE80),
    warning: AppColors.amberLight,
    star: AppColors.amberLight,
    purple: Color(0xFFB79CFF),
    ai: AppColors.blueLight,
    aiSoft: Color(0xFF1C2850),
    // product photos are cut-outs and many products are black: the well
    // stays light in dark mode too
    imageWell: Color(0xFFEEF1F8),
    onImageWell: AppColors.navy,
    grid: Color(0xFF1F2740),
    shadow: Color(0xB3000000),
  );

  /// Flat page color (also the scrolled-under app bar fill). The page itself
  /// paints a soft wash from [backgroundTop] to [backgroundBottom] — see
  /// `AppBackground`.
  final Color background;
  final Color backgroundTop;
  final Color backgroundBottom;

  /// Cards, sheets, inputs, the bottom bar, circular icon buttons (white).
  final Color surface;

  /// Quiet fills: pressed rows, skeletons, inset panels, unselected chips on cards.
  final Color surfaceVariant;

  /// Kbd chips, tooltips, slider/progress tracks.
  final Color surfaceRaised;

  /// Light grey-blue hairline. [borderStrong] on hover / emphasis.
  final Color border;
  final Color borderStrong;

  /// Navy primary text, slate secondary text ([muted]) and captions/placeholders ([faint]).
  final Color text;
  final Color muted;
  final Color faint;

  /// Royal blue: primary buttons, active nav, selected chips, links, prices you act on.
  final Color primary;
  final Color primaryHover;
  final Color onPrimary;

  /// Very light blue tint for selected chips, the nav indicator, AI panels.
  final Color primarySoft;

  /// Informational sky blue: info states only.
  final Color secondary;
  final Color secondarySoft;

  final Color error;

  /// Calm red for discounts and "was" savings. Text on it uses [onSale].
  final Color sale;
  final Color onSale;
  final Color saleSoft;
  final Color success;
  final Color warning;

  /// Amber rating stars.
  final Color star;
  final Color purple;

  /// AI surfaces use the brand blue (separate names for intent).
  final Color ai;
  final Color aiSoft;

  /// The very light tile behind product photos — light in BOTH themes,
  /// because the catalog's cut-out photos include dark products.
  final Color imageWell;

  /// Ink for anything drawn on top of [imageWell].
  final Color onImageWell;

  /// Dot / line color for `DotGridBackground`.
  final Color grid;

  /// Translucent shadow hue for `Material.shadowColor` (navy in light, black
  /// in dark). For box shadows use [shadowSm] / [shadowMd] / [shadowLg].
  final Color shadow;

  bool get _isDark => background.computeLuminance() < 0.2;

  LinearGradient get aiGradient => LinearGradient(colors: [ai, ai]);
  LinearGradient get brandGradient => LinearGradient(colors: [primary, primary]);

  /// The page wash: light from the top, very soft.
  LinearGradient get backgroundWash => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [backgroundTop, background, backgroundBottom],
    stops: const [0, 0.42, 1],
  );

  /// Department hue (small icon tints, dots, soft tiles).
  Color departmentAccent(String? slug) => AppColors.departmentAccent(slug);

  /// Resting cards (product cards, AppCard, list groups): barely-there lift.
  List<BoxShadow> get shadowSm => [
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.30 : 0.06), blurRadius: 18, offset: const Offset(0, 6)),
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.20 : 0.03), blurRadius: 3, offset: const Offset(0, 1)),
  ];

  /// Hovered cards, menus, floating bars and circular icon buttons over photos.
  List<BoxShadow> get shadowMd => [
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.45 : 0.10), blurRadius: 30, spreadRadius: -6, offset: const Offset(0, 12)),
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.25 : 0.04), blurRadius: 4, offset: const Offset(0, 1)),
  ];

  /// Dialogs, popovers and the desktop app frame.
  List<BoxShadow> get shadowLg => [
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.55 : 0.14), blurRadius: 70, spreadRadius: -18, offset: const Offset(0, 30)),
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.30 : 0.05), blurRadius: 10, offset: const Offset(0, 2)),
  ];

  @override
  AppPalette copyWith({
    Color? background,
    Color? backgroundTop,
    Color? backgroundBottom,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceRaised,
    Color? border,
    Color? borderStrong,
    Color? text,
    Color? muted,
    Color? faint,
    Color? primary,
    Color? primaryHover,
    Color? onPrimary,
    Color? primarySoft,
    Color? secondary,
    Color? secondarySoft,
    Color? error,
    Color? sale,
    Color? onSale,
    Color? saleSoft,
    Color? success,
    Color? warning,
    Color? star,
    Color? purple,
    Color? ai,
    Color? aiSoft,
    Color? imageWell,
    Color? onImageWell,
    Color? grid,
    Color? shadow,
  }) {
    return AppPalette(
      background: background ?? this.background,
      backgroundTop: backgroundTop ?? this.backgroundTop,
      backgroundBottom: backgroundBottom ?? this.backgroundBottom,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      onPrimary: onPrimary ?? this.onPrimary,
      primarySoft: primarySoft ?? this.primarySoft,
      secondary: secondary ?? this.secondary,
      secondarySoft: secondarySoft ?? this.secondarySoft,
      error: error ?? this.error,
      sale: sale ?? this.sale,
      onSale: onSale ?? this.onSale,
      saleSoft: saleSoft ?? this.saleSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      star: star ?? this.star,
      purple: purple ?? this.purple,
      ai: ai ?? this.ai,
      aiSoft: aiSoft ?? this.aiSoft,
      imageWell: imageWell ?? this.imageWell,
      onImageWell: onImageWell ?? this.onImageWell,
      grid: grid ?? this.grid,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: mix(background, other.background),
      backgroundTop: mix(backgroundTop, other.backgroundTop),
      backgroundBottom: mix(backgroundBottom, other.backgroundBottom),
      surface: mix(surface, other.surface),
      surfaceVariant: mix(surfaceVariant, other.surfaceVariant),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      border: mix(border, other.border),
      borderStrong: mix(borderStrong, other.borderStrong),
      text: mix(text, other.text),
      muted: mix(muted, other.muted),
      faint: mix(faint, other.faint),
      primary: mix(primary, other.primary),
      primaryHover: mix(primaryHover, other.primaryHover),
      onPrimary: mix(onPrimary, other.onPrimary),
      primarySoft: mix(primarySoft, other.primarySoft),
      secondary: mix(secondary, other.secondary),
      secondarySoft: mix(secondarySoft, other.secondarySoft),
      error: mix(error, other.error),
      sale: mix(sale, other.sale),
      onSale: mix(onSale, other.onSale),
      saleSoft: mix(saleSoft, other.saleSoft),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      star: mix(star, other.star),
      purple: mix(purple, other.purple),
      ai: mix(ai, other.ai),
      aiSoft: mix(aiSoft, other.aiSoft),
      imageWell: mix(imageWell, other.imageWell),
      onImageWell: mix(onImageWell, other.onImageWell),
      grid: mix(grid, other.grid),
      shadow: mix(shadow, other.shadow),
    );
  }
}
