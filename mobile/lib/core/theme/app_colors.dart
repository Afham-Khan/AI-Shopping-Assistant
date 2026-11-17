import 'package:material_ui/material_ui.dart';

/// Raw Zelora color tokens. Widgets should read the theme-aware [AppPalette]
/// (`context.colors`) rather than these constants.
///
/// Identity v2 — "airy royal": a light, clean blue-white page with a gentle
/// wash of light from the top, crisp white rounded cards with very soft
/// shadows, ONE confident royal blue, dark navy ink, slate secondary text.
/// Vivid coral-red for discounts, amber for rating stars and "deal" accents.
/// Light is the primary theme; dark is derived from the same hues (deep navy,
/// lighter periwinkle accent).
abstract final class AppColors {
  // brand — Zelora royal blue (5.52:1 with white, 5.0:1 on the page wash,
  // 4.78:1 on its own soft tint)
  static const blue = Color(0xFF1D5BF0);
  static const blueHover = Color(0xFF1648D8);
  static const blueSoft = Color(0xFFE7EFFF);

  /// Dark-theme accent: a lighter periwinkle that reads on navy (6.9:1 on
  /// the dark surface) with navy ink on top.
  static const blueLight = Color(0xFF7AA2FF);
  static const blueLightHover = Color(0xFF94B4FF);
  static const navy = Color(0xFF0F172A);

  /// Price ink: a confident deep navy-blue (13.5:1 on white), a step bluer
  /// than the body text so amounts read first.
  static const priceNavy = Color(0xFF0B2A6B);

  // light — clean blue-white page, crisp white cards, navy ink
  static const lightBackground = Color(0xFFF1F4FD);
  static const lightBackgroundTop = Color(0xFFF8FAFF);
  static const lightBackgroundBottom = Color(0xFFEAEFFC);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceVariant = Color(0xFFF5F8FE);
  static const lightSurfaceRaised = Color(0xFFE8EEFB);
  static const lightBorder = Color(0xFFE1E7F5);
  static const lightBorderStrong = Color(0xFFC5CFE6);
  static const lightText = navy;
  static const lightMuted = Color(0xFF556076);
  static const lightFaint = Color(0xFF636C82);

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

  // semantic — the sale red is a vivid coral-red that still clears 4.5:1 with
  // white text (5.3:1), on its own soft tint (4.8:1) and on the whole page wash
  static const red = Color(0xFFD5190B);
  static const redLight = Color(0xFFFF7F6B);
  static const amber = Color(0xFFF59E0B);
  static const amberLight = Color(0xFFFBBF24);

  /// Deal amber: a warm, bright fill for "deal" pills and strips. Always pair
  /// it with navy ink ([navy] on it is 9.8:1) — never amber text on white.
  static const deal = Color(0xFFFFB020);
  static const dealSoft = Color(0xFFFFF4D9);

  /// Brown-amber text for use on [dealSoft] (6.2:1).
  static const dealInk = Color(0xFF8A4B00);
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

  // category → department, mirroring the catalog seed (products only carry a
  // category, but tints and accents are per department)
  static const _categoryDepartment = <String, String>{
    'smartphones': 'electronics',
    'laptops': 'electronics',
    'tablets': 'electronics',
    'mobile-accessories': 'electronics',
    'mens-shirts': 'fashion',
    'mens-shoes': 'fashion',
    'mens-watches': 'fashion',
    'tops': 'fashion',
    'womens-dresses': 'fashion',
    'womens-shoes': 'fashion',
    'womens-bags': 'fashion',
    'womens-jewellery': 'fashion',
    'womens-watches': 'fashion',
    'sunglasses': 'fashion',
    'beauty': 'beauty-personal-care',
    'skin-care': 'beauty-personal-care',
    'fragrances': 'beauty-personal-care',
    'furniture': 'home-living',
    'home-decoration': 'home-living',
    'kitchen-accessories': 'home-living',
    'groceries': 'groceries',
    'sports-accessories': 'sports-outdoors',
    'motorcycle': 'automotive',
    'vehicle': 'automotive',
  };

  /// The department slug for a department OR category slug; null when unknown
  /// (so unknown things stay neutral instead of getting a random hue).
  static String? departmentKey(String? slug) {
    if (slug == null) return null;
    if (_departmentAccents.containsKey(slug)) return slug;
    return _categoryDepartment[slug];
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
    this.price = AppColors.priceNavy,
    this.deal = AppColors.deal,
    this.onDeal = AppColors.navy,
    this.dealSoft = AppColors.dealSoft,
    this.dealInk = AppColors.dealInk,
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
    saleSoft: Color(0xFFFFF1EE),
    success: AppColors.green,
    warning: Color(0xFFB45309),
    star: AppColors.amber,
    purple: AppColors.violet,
    ai: AppColors.blue,
    aiSoft: AppColors.blueSoft,
    imageWell: Color(0xFFF5F7FC),
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
    price: Color(0xFFDDE7FF),
    deal: AppColors.amberLight,
    onDeal: Color(0xFF2B1A00),
    dealSoft: Color(0xFF3A2E12),
    dealInk: Color(0xFFFBD38D),
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

  /// Ink for prices: a confident navy-blue (light) / pale periwinkle (dark).
  final Color price;

  /// Warm amber for "deal" pills and strips ([onDeal] ink on top), with a soft
  /// tint ([dealSoft]) and readable brown-amber text on it ([dealInk]).
  final Color deal;
  final Color onDeal;
  final Color dealSoft;
  final Color dealInk;

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

  /// Very soft department tint for product image wells (a 10 % wash of the
  /// department hue over [imageWell], so it stays light in both themes).
  /// Takes a department or a category slug; unknown slugs get plain [imageWell].
  Color departmentWell(String? slug) {
    final key = AppColors.departmentKey(slug);
    if (key == null) return imageWell;
    return Color.alphaBlend(AppColors.departmentAccent(key).withValues(alpha: 0.10), imageWell);
  }

  /// Soft department tint for tiles on a card surface (category tiles, icon
  /// wells). Unknown slugs get [surfaceVariant].
  Color departmentSoft(String? slug) {
    final key = AppColors.departmentKey(slug);
    if (key == null) return surfaceVariant;
    return Color.alphaBlend(AppColors.departmentAccent(key).withValues(alpha: _isDark ? 0.18 : 0.10), surface);
  }

  /// Resting cards (product cards, AppCard, list groups): barely-there lift.
  List<BoxShadow> get shadowSm => [
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.30 : 0.07), blurRadius: 18, offset: const Offset(0, 6)),
    BoxShadow(color: shadow.withValues(alpha: _isDark ? 0.20 : 0.05), blurRadius: 3, offset: const Offset(0, 1)),
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
    Color? price,
    Color? deal,
    Color? onDeal,
    Color? dealSoft,
    Color? dealInk,
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
      price: price ?? this.price,
      deal: deal ?? this.deal,
      onDeal: onDeal ?? this.onDeal,
      dealSoft: dealSoft ?? this.dealSoft,
      dealInk: dealInk ?? this.dealInk,
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
      price: mix(price, other.price),
      deal: mix(deal, other.deal),
      onDeal: mix(onDeal, other.onDeal),
      dealSoft: mix(dealSoft, other.dealSoft),
      dealInk: mix(dealInk, other.dealInk),
    );
  }
}
