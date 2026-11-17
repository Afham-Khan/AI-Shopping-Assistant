import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../widgets/app_background.dart';
import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the light/dark [ThemeData] from the design tokens.
///
/// v2 "airy royal": transparent scaffolds over the page wash (each page route
/// paints `AppBackground`), white rounded cards with soft shadows, pill
/// buttons and chips, one royal-blue accent, Plus Jakarta Sans throughout.
/// Every interactive component has explicit hover / pressed / focus /
/// disabled states so the app feels considered with a mouse as well as touch.
abstract final class AppTheme {
  /// Tests switch this off because Google Fonts would hit the network.
  static bool get useGoogleFonts => AppType.useGoogleFonts;
  static set useGoogleFonts(bool value) => AppType.useGoogleFonts = value;

  // built lazily once (static finals are lazy in Dart)
  static final ThemeData light = build(AppPalette.light, Brightness.light);
  static final ThemeData dark = build(AppPalette.dark, Brightness.dark);

  static ThemeData build(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final text = _textTheme(p);
    final scheme = _colorScheme(p, brightness);
    final disabledFill = p.text.withValues(alpha: 0.08);
    final disabledInk = p.text.withValues(alpha: 0.38);

    const buttonShape = StadiumBorder();
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.sm);
    const buttonMinSize = Size(64, 50);
    final buttonText = text.labelLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0);

    bool has(Set<WidgetState> s, WidgetState state) => s.contains(state);
    bool active(Set<WidgetState> s) => has(s, WidgetState.hovered) || has(s, WidgetState.pressed);

    // quiet neutral overlay for ghost hover; filled/outlined change their own fill
    final neutralOverlay = WidgetStateProperty.resolveWith<Color?>((s) {
      if (has(s, WidgetState.pressed)) return p.text.withValues(alpha: 0.08);
      if (has(s, WidgetState.hovered)) return p.text.withValues(alpha: 0.04);
      if (has(s, WidgetState.focused)) return p.primary.withValues(alpha: 0.10);
      return null;
    });
    final accentOverlay = WidgetStateProperty.resolveWith<Color?>((s) {
      if (has(s, WidgetState.pressed)) return p.primary.withValues(alpha: 0.12);
      if (has(s, WidgetState.hovered)) return p.primary.withValues(alpha: 0.06);
      if (has(s, WidgetState.focused)) return p.primary.withValues(alpha: 0.10);
      return null;
    });

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      textTheme: text,
      primaryTextTheme: text,
      // transparent: every page route paints the AppBackground wash
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: p.background,
      cardColor: p.surface,
      dividerColor: p.border,
      disabledColor: disabledInk,
      hintColor: p.faint,
      splashColor: p.primary.withValues(alpha: 0.06),
      highlightColor: p.primary.withValues(alpha: 0.03),
      hoverColor: p.text.withValues(alpha: 0.03),
      focusColor: p.primary.withValues(alpha: 0.12),
      splashFactory: InkRipple.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      iconTheme: IconThemeData(color: p.text, size: 22),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.windows: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.linux: FadeThroughPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeThroughPageTransitionsBuilder(),
        },
      ),
      // the automatic back / close buttons become white circles, like the
      // reference's app bar
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (context) => _CircleGlyph(icon: Icons.arrow_back_ios_new_rounded, palette: p, size: 17),
        closeButtonIconBuilder: (context) => _CircleGlyph(icon: Icons.close_rounded, palette: p),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.24),
        selectionHandleColor: p.primary,
      ),
      appBarTheme: AppBarThemeData(
        // see-through over the wash at rest; a solid page color once content
        // scrolls underneath, so titles never sit on top of text
        backgroundColor: WidgetStateColor.resolveWith(
          (s) => has(s, WidgetState.scrolledUnder) ? p.background : p.background.withValues(alpha: 0),
        ),
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleSpacing: AppSpacing.md,
        toolbarHeight: 60,
        titleTextStyle: text.titleMedium!.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
        iconTheme: IconThemeData(color: p.text, size: 22),
        actionsIconTheme: IconThemeData(color: p.text, size: 22),
        actionsPadding: const EdgeInsets.only(right: AppSpacing.xs),
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (has(s, WidgetState.disabled)) return disabledFill;
            return active(s) ? p.primaryHover : p.primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => has(s, WidgetState.disabled) ? disabledInk : p.onPrimary,
          ),
          overlayColor: WidgetStateProperty.resolveWith(
            (s) => has(s, WidgetState.pressed) ? p.onPrimary.withValues(alpha: 0.10) : Colors.transparent,
          ),
          side: WidgetStateProperty.resolveWith(
            (s) => has(s, WidgetState.focused) ? BorderSide(color: p.text, width: 2) : BorderSide.none,
          ),
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          padding: const WidgetStatePropertyAll(buttonPadding),
          shape: const WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(buttonText),
          elevation: const WidgetStatePropertyAll(0),
          animationDuration: AppDurations.color,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) => active(s) ? p.surfaceVariant : p.surface),
          foregroundColor: WidgetStateProperty.resolveWith((s) => has(s, WidgetState.disabled) ? disabledInk : p.text),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith((s) => BorderSide(color: active(s) ? p.borderStrong : p.border)),
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          padding: const WidgetStatePropertyAll(buttonPadding),
          shape: const WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(buttonText),
          elevation: const WidgetStatePropertyAll(0),
        ),
      ),
      // secondary = the reference's outlined "Add to Cart": blue outline + blue label
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (has(s, WidgetState.disabled)) return Colors.transparent;
            return active(s) ? p.primarySoft : p.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) => has(s, WidgetState.disabled) ? disabledInk : p.primary),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith((s) {
            if (has(s, WidgetState.disabled)) return BorderSide(color: p.border);
            if (has(s, WidgetState.focused)) return BorderSide(color: p.primaryHover, width: 2);
            return BorderSide(color: p.primary, width: 1.5);
          }),
          minimumSize: const WidgetStatePropertyAll(buttonMinSize),
          padding: const WidgetStatePropertyAll(buttonPadding),
          shape: const WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(buttonText),
          animationDuration: AppDurations.color,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) => has(s, WidgetState.disabled) ? disabledInk : p.primary),
          overlayColor: accentOverlay,
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.sm)),
          shape: const WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(buttonText.copyWith(fontSize: 14)),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) => has(s, WidgetState.disabled) ? disabledInk : p.text),
          overlayColor: neutralOverlay,
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: const WidgetStatePropertyAll(CircleBorder()),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        hoverColor: p.primaryHover,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: const StadiumBorder(),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.surface,
        hoverColor: Colors.transparent,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 15),
        hintStyle: text.bodyLarge!.copyWith(color: p.faint, fontSize: 15),
        labelStyle: text.bodyLarge!.copyWith(color: p.muted, fontSize: 15),
        floatingLabelStyle: text.bodyMedium!.copyWith(color: p.primary, fontWeight: FontWeight.w600),
        helperStyle: text.bodySmall!.copyWith(color: p.faint),
        errorStyle: text.bodySmall!.copyWith(color: p.error),
        errorMaxLines: 3,
        prefixIconColor: WidgetStateColor.resolveWith((s) {
          if (has(s, WidgetState.error)) return p.error;
          return has(s, WidgetState.focused) ? p.primary : p.faint;
        }),
        suffixIconColor: p.muted,
        border: _inputBorder(p.border),
        enabledBorder: _inputBorder(p.border),
        focusedBorder: _inputBorder(p.primary, 1.6),
        errorBorder: _inputBorder(p.error),
        focusedErrorBorder: _inputBorder(p.error, 1.6),
        disabledBorder: _inputBorder(p.border.withValues(alpha: 0.5)),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: isDark ? p.border : p.border.withValues(alpha: 0.7)),
        ),
      ),
      // the reference's color/storage chips: white pills, selected = blue
      // outline + light blue tint + blue label
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith((s) {
          if (has(s, WidgetState.selected)) return p.primarySoft;
          return active(s) ? p.surfaceVariant : p.surface;
        }),
        side: WidgetStateBorderSide.resolveWith((s) {
          if (has(s, WidgetState.selected)) return BorderSide(color: p.primary, width: 1.5);
          return BorderSide(color: active(s) ? p.borderStrong : p.border);
        }),
        labelStyle: text.labelLarge!.copyWith(
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith((s) => has(s, WidgetState.selected) ? p.primary : p.text),
        ),
        secondaryLabelStyle: text.labelLarge!.copyWith(color: p.primary),
        iconTheme: IconThemeData(color: p.muted, size: 18),
        deleteIconColor: p.muted,
        checkmarkColor: p.primary,
        showCheckmark: false,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        indicatorColor: p.primarySoft,
        indicatorShape: const StadiumBorder(),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected)
              ? text.labelSmall!.copyWith(color: p.primary, fontWeight: FontWeight.w700)
              : text.labelSmall!.copyWith(color: p.muted, fontWeight: FontWeight.w600),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 24, color: has(s, WidgetState.selected) ? p.primary : p.muted),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.sheetTop,
          side: isDark ? BorderSide(color: p.border) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        showDragHandle: false,
        dragHandleColor: p.borderStrong,
        constraints: const BoxConstraints(maxWidth: Breakpoints.maxSheet),
        modalBarrierColor: (isDark ? Colors.black : AppColors.navy).withValues(alpha: isDark ? 0.6 : 0.32),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: p.shadow,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.sheetAll),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.muted),
        barrierColor: (isDark ? Colors.black : AppColors.navy).withValues(alpha: isDark ? 0.6 : 0.32),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? p.surfaceRaised : p.text,
        contentTextStyle: text.bodyMedium!.copyWith(color: isDark ? p.text : Colors.white, fontWeight: FontWeight.w600),
        actionTextColor: isDark ? p.primary : AppColors.blueLight,
        closeIconColor: isDark ? p.muted : Colors.white70,
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.inputAll,
          side: isDark ? BorderSide(color: p.borderStrong) : BorderSide.none,
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p.muted,
        textColor: p.text,
        titleTextStyle: text.bodyLarge!.copyWith(fontWeight: FontWeight.w600, fontSize: 15),
        subtitleTextStyle: text.bodySmall,
        leadingAndTrailingTextStyle: text.bodyMedium!.copyWith(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minVerticalPadding: 12,
        minLeadingWidth: 24,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.inputAll),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          side: WidgetStateProperty.resolveWith(
            (s) => BorderSide(color: has(s, WidgetState.selected) ? p.primary : p.border),
          ),
          shape: const WidgetStatePropertyAll(StadiumBorder()),
          overlayColor: neutralOverlay,
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => has(s, WidgetState.selected) ? p.primarySoft : p.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith((s) {
            if (has(s, WidgetState.disabled)) return disabledInk;
            return has(s, WidgetState.selected) ? p.primary : p.muted;
          }),
          iconColor: WidgetStateProperty.resolveWith(
            (s) => has(s, WidgetState.selected) ? p.primary : p.faint,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.primary,
        inactiveTrackColor: p.surfaceRaised,
        disabledActiveTrackColor: p.borderStrong,
        disabledInactiveTrackColor: p.border,
        thumbColor: p.primary,
        overlayColor: p.primary.withValues(alpha: 0.12),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
        valueIndicatorColor: p.text,
        valueIndicatorTextStyle: AppType.mono(text.labelMedium!.copyWith(color: p.background)),
        trackHeight: 4,
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected) ? p.onPrimary : p.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected) ? p.primary : p.surfaceRaised,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected) ? p.primary : p.borderStrong,
        ),
        overlayColor: WidgetStatePropertyAll(p.primary.withValues(alpha: 0.10)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected) ? p.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(p.onPrimary),
        side: BorderSide(color: p.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(6))),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected) ? p.primary : p.borderStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceRaised,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
        borderRadius: AppRadii.pillAll,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primary,
        unselectedLabelColor: p.muted,
        indicatorColor: p.primary,
        dividerColor: p.border,
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: p.primary, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        overlayColor: accentOverlay,
        labelStyle: text.titleSmall!.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: text.titleSmall!.copyWith(fontWeight: FontWeight.w600),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.sale,
        textColor: p.onSale,
        smallSize: 8,
        largeSize: 18,
        textStyle: text.labelSmall!.copyWith(fontWeight: FontWeight.w700, fontFeatures: AppType.tabular),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: p.shadow,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.inputAll, side: BorderSide(color: p.border)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(10),
          shadowColor: WidgetStatePropertyAll(p.shadow),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadii.inputAll, side: BorderSide(color: p.border)),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? p.surfaceRaised : p.text,
          borderRadius: AppRadii.tagAll,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: text.labelMedium!.copyWith(color: isDark ? p.text : Colors.white, fontWeight: FontWeight.w600),
        waitDuration: const Duration(milliseconds: 500),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => active(s) ? p.borderStrong : p.borderStrong.withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(5),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: p.muted,
        collapsedIconColor: p.muted,
        textColor: p.text,
        collapsedTextColor: p.text,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: AppRadii.inputAll,
    borderSide: BorderSide(color: color, width: width),
  );

  static ColorScheme _colorScheme(AppPalette p, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ColorScheme(
      brightness: brightness,
      primary: p.primary,
      onPrimary: p.onPrimary,
      primaryContainer: p.primarySoft,
      onPrimaryContainer: p.primary,
      secondary: p.secondary,
      onSecondary: isDark ? const Color(0xFF04202F) : Colors.white,
      secondaryContainer: p.secondarySoft,
      onSecondaryContainer: p.secondary,
      tertiary: p.ai,
      onTertiary: p.onPrimary,
      tertiaryContainer: p.aiSoft,
      onTertiaryContainer: p.ai,
      error: p.error,
      onError: p.onSale,
      errorContainer: p.saleSoft,
      onErrorContainer: p.error,
      surface: p.surface,
      onSurface: p.text,
      surfaceDim: p.background,
      surfaceBright: p.surface,
      surfaceContainerLowest: p.surface,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceVariant,
      surfaceContainerHigh: p.surfaceVariant,
      surfaceContainerHighest: p.surfaceRaised,
      onSurfaceVariant: p.muted,
      outline: p.borderStrong,
      outlineVariant: p.border,
      shadow: p.shadow,
      scrim: AppColors.navy,
      inverseSurface: p.text,
      onInverseSurface: p.background,
      inversePrimary: isDark ? AppColors.blue : AppColors.blueLight,
      surfaceTint: Colors.transparent,
    );
  }

  /// Type scale — all Plus Jakarta Sans. Hierarchy by weight: 800 for
  /// display/headline, 700 titles, 600 labels, 400 body.
  static TextTheme _textTheme(AppPalette p) {
    TextStyle style(double size, FontWeight weight, double tracking, double height) =>
        TextStyle(fontSize: size, fontWeight: weight, letterSpacing: tracking, height: height);

    final base = TextTheme(
      displayLarge: style(40, FontWeight.w800, -1.0, 1.1),
      displayMedium: style(34, FontWeight.w800, -0.8, 1.12),
      displaySmall: style(29, FontWeight.w800, -0.6, 1.15),
      headlineLarge: style(26, FontWeight.w800, -0.5, 1.18),
      headlineMedium: style(23, FontWeight.w700, -0.4, 1.22),
      headlineSmall: style(20, FontWeight.w700, -0.3, 1.25),
      titleLarge: style(18, FontWeight.w700, -0.2, 1.3),
      titleMedium: style(16, FontWeight.w700, -0.1, 1.35),
      titleSmall: style(14, FontWeight.w600, 0, 1.35),
      bodyLarge: style(16, FontWeight.w400, 0, 1.5),
      bodyMedium: style(14, FontWeight.w400, 0, 1.5),
      bodySmall: style(12.5, FontWeight.w400, 0, 1.4),
      labelLarge: style(14, FontWeight.w600, 0, 1.2),
      labelMedium: style(12, FontWeight.w600, 0, 1.2),
      labelSmall: style(11, FontWeight.w600, 0.2, 1.2),
    ).apply(bodyColor: p.text, displayColor: p.text);

    final themed = base.copyWith(bodySmall: base.bodySmall!.copyWith(color: p.muted));
    return AppType.sansTheme(themed);
  }
}

/// White circular "chip" behind the automatic back / close icons.
class _CircleGlyph extends StatelessWidget {
  const _CircleGlyph({required this.icon, required this.palette, this.size = 20});

  final IconData icon;
  final AppPalette palette;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: palette.surface,
        shape: BoxShape.circle,
        boxShadow: palette.shadowSm,
        border: Border.all(color: palette.border.withValues(alpha: 0.8)),
      ),
      child: Icon(icon, size: size, color: palette.text),
    );
  }
}

/// Subtle fade + scale page transition (Material "fade through" feel), with
/// the [AppBackground] wash painted behind every page so scaffolds can stay
/// transparent. Falls back to an instant switch under reduced motion.
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  static final _fade = CurveTween(curve: const Interval(0.1, 1, curve: Curves.easeOut));
  static final _scale = Tween<double>(begin: 0.985, end: 1).chain(CurveTween(curve: AppCurves.standard));

  @override
  Duration get transitionDuration => AppDurations.page;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final page = AppBackground(child: child);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return page;
    return FadeTransition(
      opacity: animation.drive(_fade),
      child: ScaleTransition(scale: animation.drive(_scale), child: page),
    );
  }
}
