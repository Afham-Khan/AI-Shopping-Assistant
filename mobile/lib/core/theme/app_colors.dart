import 'package:material_ui/material_ui.dart';

/// Raw Zelora color tokens. Widgets should read the theme-aware [AppPalette]
/// (`context.colors`) rather than these constants.
///
/// Identity: "editorial front, ledger precision". Deep tide-ink neutrals
/// (dark, the default) or mint-tinted paper (light), ONE confident accent
/// (Zelora mint), a warm coral for sale states and amber for ratings.
/// No gradients anywhere — the gradient getters below are flat on purpose.
abstract final class AppColors {
  // accent — Zelora mint
  static const mint = Color(0xFF3DDBA6);
  static const mintHover = Color(0xFF62E5BA);
  static const mintDeep = Color(0xFF0A7F60);
  static const mintDeepHover = Color(0xFF086B51);

  // dark — tide ink (teal-black, lower chroma than navy so photos stay true)
  static const darkBackground = Color(0xFF081719);
  static const darkSurface = Color(0xFF0D2023);
  static const darkSurfaceVariant = Color(0xFF13292D);
  static const darkSurfaceRaised = Color(0xFF1A3439);
  static const darkBorder = Color(0xFF1E383D);
  static const darkBorderStrong = Color(0xFF30535A);
  static const darkText = Color(0xFFEAF2F0);
  static const darkMuted = Color(0xFFA4BBB8);
  static const darkFaint = Color(0xFF6F8A88);

  // light — paper with a breath of mint; cards are true white
  static const lightBackground = Color(0xFFF4F7F4);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFECF1ED);
  static const lightSurfaceRaised = Color(0xFFE0E8E3);
  static const lightBorder = Color(0xFFD9E3DD);
  static const lightBorderStrong = Color(0xFFB5C8BE);
  static const lightText = Color(0xFF10221D);
  static const lightMuted = Color(0xFF465E56);
  static const lightFaint = Color(0xFF72887F);

  // semantic (dark / light pairs live in AppPalette)
  static const coral = Color(0xFFF4736C);
  static const amber = Color(0xFFF0B352);
  static const sky = Color(0xFF5AB6EE);
  static const violet = Color(0xFFC4A0FA);

  // legacy names kept so older call sites compile
  static const emerald = mintDeep;
  static const emeraldBright = mint;
  static const ocean = Color(0xFF0F6FC0);
  static const oceanBright = sky;
  static const cyan = Color(0xFF3FBFC0);
  static const aiStart = mint;
  static const aiMid = mint;
  static const aiEnd = mint;
  static const ai = mint;
  static const sale = coral;
  static const success = Color(0xFF3BD48F);
  static const warning = amber;
  static const star = amber;
  static const error = Color(0xFFCF3B33);
  static const errorDark = coral;

  /// Flat on purpose: the design system has no visible gradients. Kept as a
  /// [LinearGradient] only because older code asks for one.
  static const aiGradient = LinearGradient(colors: [Color(0xFF1FB888), Color(0xFF1FB888)]);
  static const brandGradient = LinearGradient(colors: [Color(0xFF1FB888), Color(0xFF1FB888)]);

  // Department hues: mid-tones that read on both themes. Use them as a thin
  // top border, a 6 px dot or a small icon tint — never as a loud fill.
  static const _departmentAccents = <String, Color>{
    'electronics': Color(0xFF4AA8E8),
    'fashion': Color(0xFFE8719A),
    'beauty-personal-care': Color(0xFFA98BF0),
    'home-living': Color(0xFFE0A23C),
    'groceries': Color(0xFF4CC38A),
    'sports-outdoors': Color(0xFFEE8A4E),
    'automotive': Color(0xFF3FBFC0),
  };
  static const _fallbackAccents = [
    Color(0xFF4AA8E8),
    Color(0xFF4CC38A),
    Color(0xFFA98BF0),
    Color(0xFFE8719A),
    Color(0xFFEE8A4E),
    Color(0xFF3FBFC0),
    Color(0xFFE0A23C),
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

  static const dark = AppPalette(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceVariant: AppColors.darkSurfaceVariant,
    surfaceRaised: AppColors.darkSurfaceRaised,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorderStrong,
    text: AppColors.darkText,
    muted: AppColors.darkMuted,
    faint: AppColors.darkFaint,
    primary: AppColors.mint,
    primaryHover: AppColors.mintHover,
    onPrimary: Color(0xFF04271B),
    primarySoft: Color(0xFF123531),
    secondary: AppColors.sky,
    secondarySoft: Color(0xFF12303F),
    error: AppColors.coral,
    sale: AppColors.coral,
    onSale: Color(0xFF2B0907),
    saleSoft: Color(0xFF3A2224),
    success: Color(0xFF3BD48F),
    warning: AppColors.amber,
    star: AppColors.amber,
    purple: AppColors.violet,
    ai: AppColors.mint,
    aiSoft: Color(0xFF123531),
    imageWell: Color(0xFFE7EDEA),
    onImageWell: Color(0xFF10221D),
    grid: Color(0xFF1B3439),
    shadow: Color(0xB3000000),
  );

  static const light = AppPalette(
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceVariant: AppColors.lightSurfaceVariant,
    surfaceRaised: AppColors.lightSurfaceRaised,
    border: AppColors.lightBorder,
    borderStrong: AppColors.lightBorderStrong,
    text: AppColors.lightText,
    muted: AppColors.lightMuted,
    faint: AppColors.lightFaint,
    primary: AppColors.mintDeep,
    primaryHover: AppColors.mintDeepHover,
    onPrimary: Color(0xFFFFFFFF),
    primarySoft: Color(0xFFE1F2EC),
    secondary: Color(0xFF0F6FC0),
    secondarySoft: Color(0xFFE3EFF9),
    error: Color(0xFFCF3B33),
    sale: Color(0xFFC8372F),
    onSale: Color(0xFFFFFFFF),
    saleSoft: Color(0xFFFBE9E7),
    success: Color(0xFF0E8F5B),
    warning: Color(0xFFA86A09),
    star: Color(0xFFE09A14),
    purple: Color(0xFF6F48D6),
    ai: AppColors.mintDeep,
    aiSoft: Color(0xFFE1F2EC),
    imageWell: Color(0xFFEEF2EF),
    onImageWell: Color(0xFF10221D),
    grid: Color(0xFFD3DED7),
    shadow: Color(0x2410231C),
  );

  /// Page background.
  final Color background;

  /// Cards, sheets, inputs.
  final Color surface;

  /// Quiet fills: hover rows, skeletons, inset panels (surface-2).
  final Color surfaceVariant;

  /// Chips on a surface, kbd chips, tooltips (surface-3).
  final Color surfaceRaised;

  /// Hairline border. [borderStrong] on hover / emphasis.
  final Color border;
  final Color borderStrong;

  /// Primary text, secondary text ([muted]) and captions/placeholders ([faint]).
  final Color text;
  final Color muted;
  final Color faint;

  /// The one accent (Zelora mint): primary buttons, active states, eyebrows.
  final Color primary;
  final Color primaryHover;
  final Color onPrimary;

  /// Opaque accent tint for selected chips, nav indicators, AI panels.
  final Color primarySoft;

  /// Informational blue: links and info states only.
  final Color secondary;
  final Color secondarySoft;

  final Color error;

  /// Warm coral for discounts and "was" savings. Text on it uses [onSale].
  final Color sale;
  final Color onSale;
  final Color saleSoft;
  final Color success;
  final Color warning;
  final Color star;
  final Color purple;

  /// AI surfaces use the same single accent (kept as separate names for intent).
  final Color ai;
  final Color aiSoft;

  /// The light "studio" tile behind product photos — light in BOTH themes,
  /// because the catalog's cut-out photos include dark products.
  final Color imageWell;

  /// Ink for anything drawn on top of [imageWell].
  final Color onImageWell;

  /// Dot / line color for `DotGridBackground`.
  final Color grid;

  /// Shadow color, for floating elements only.
  final Color shadow;

  LinearGradient get aiGradient => LinearGradient(colors: [ai, ai]);
  LinearGradient get brandGradient => LinearGradient(colors: [primary, primary]);

  /// Department hue (thin top borders, dots, small icon tints).
  Color departmentAccent(String? slug) => AppColors.departmentAccent(slug);

  /// Soft drop shadow for hovered cards and menus.
  List<BoxShadow> get shadowMd => [BoxShadow(color: shadow, blurRadius: 28, spreadRadius: -10, offset: const Offset(0, 10))];

  /// Deep shadow for dialogs and popovers.
  List<BoxShadow> get shadowLg => [BoxShadow(color: shadow, blurRadius: 64, spreadRadius: -24, offset: const Offset(0, 28))];

  @override
  AppPalette copyWith({
    Color? background,
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
