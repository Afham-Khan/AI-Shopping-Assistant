import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Builds the light/dark [ThemeData] from the design tokens.
///
/// Solid surfaces with hairline borders, one accent, no gradients, no blur.
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

    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadii.inputAll);
    const buttonPadding = EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm);
    const buttonMinSize = Size(64, 48);
    final buttonText = text.labelLarge!.copyWith(fontSize: 15, letterSpacing: 0.1);

    bool has(Set<WidgetState> s, WidgetState state) => s.contains(state);
    bool active(Set<WidgetState> s) => has(s, WidgetState.hovered) || has(s, WidgetState.pressed);

    // quiet neutral overlay for ghost/outlined hover; the filled button
    // changes its own fill instead
    final neutralOverlay = WidgetStateProperty.resolveWith<Color?>((s) {
      if (has(s, WidgetState.pressed)) return p.text.withValues(alpha: 0.10);
      if (has(s, WidgetState.hovered)) return p.text.withValues(alpha: 0.05);
      if (has(s, WidgetState.focused)) return p.text.withValues(alpha: 0.08);
      return null;
    });

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [p],
      textTheme: text,
      primaryTextTheme: text,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      cardColor: p.surface,
      dividerColor: p.border,
      disabledColor: disabledInk,
      hintColor: p.faint,
      splashColor: p.text.withValues(alpha: 0.06),
      highlightColor: p.text.withValues(alpha: 0.03),
      hoverColor: p.text.withValues(alpha: 0.04),
      focusColor: p.primary.withValues(alpha: 0.14),
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
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primary.withValues(alpha: 0.28),
        selectionHandleColor: p.primary,
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: p.background,
        foregroundColor: p.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleSpacing: AppSpacing.md,
        titleTextStyle: text.titleLarge,
        iconTheme: IconThemeData(color: p.text, size: 22),
        actionsIconTheme: IconThemeData(color: p.text, size: 22),
        // a hairline instead of a shadow once content scrolls under
        shape: Border(bottom: BorderSide(color: p.border)),
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
            (s) => has(s, WidgetState.focused) ? BorderSide(color: p.text, width: 1.5) : BorderSide.none,
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
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((s) {
            if (has(s, WidgetState.disabled)) return Colors.transparent;
            return active(s) ? p.surfaceVariant : p.surface;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((s) => has(s, WidgetState.disabled) ? disabledInk : p.text),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          side: WidgetStateProperty.resolveWith((s) {
            if (has(s, WidgetState.focused)) return BorderSide(color: p.primary, width: 1.5);
            if (has(s, WidgetState.disabled)) return BorderSide(color: p.border.withValues(alpha: 0.6));
            return BorderSide(color: active(s) ? p.borderStrong : p.border);
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
          foregroundColor: WidgetStateProperty.resolveWith((s) => has(s, WidgetState.disabled) ? disabledInk : p.text),
          overlayColor: neutralOverlay,
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.sm)),
          shape: const WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(buttonText),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((s) => has(s, WidgetState.disabled) ? disabledInk : p.text),
          overlayColor: neutralOverlay,
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
          shape: const WidgetStatePropertyAll(buttonShape),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: p.onPrimary,
        hoverColor: p.primaryHover,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.cardAll),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: p.surface,
        hoverColor: Colors.transparent,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: text.bodyLarge!.copyWith(color: p.faint),
        labelStyle: text.bodyLarge!.copyWith(color: p.muted),
        floatingLabelStyle: text.bodyMedium!.copyWith(color: p.text),
        helperStyle: text.bodySmall!.copyWith(color: p.faint),
        errorStyle: text.bodySmall!.copyWith(color: p.error),
        errorMaxLines: 3,
        prefixIconColor: WidgetStateColor.resolveWith((s) {
          if (has(s, WidgetState.error)) return p.error;
          return has(s, WidgetState.focused) ? p.primary : p.faint;
        }),
        suffixIconColor: p.muted,
        border: _inputBorder(p.border),
        enabledBorder: WidgetStateInputBorder.resolveWith(
          (s) => _inputBorder(has(s, WidgetState.hovered) ? p.borderStrong : p.border),
        ),
        focusedBorder: _inputBorder(p.primary, 1.5),
        errorBorder: _inputBorder(p.error),
        focusedErrorBorder: _inputBorder(p.error, 1.5),
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
          side: BorderSide(color: p.border),
        ),
      ),
      chipTheme: ChipThemeData(
        // selected = soft accent tint + accent hairline, never a loud fill
        color: WidgetStateProperty.resolveWith((s) {
          if (has(s, WidgetState.selected)) return p.primarySoft;
          return active(s) ? p.surfaceVariant : p.surface;
        }),
        side: WidgetStateBorderSide.resolveWith((s) {
          if (has(s, WidgetState.selected)) return BorderSide(color: p.primary.withValues(alpha: 0.55));
          return BorderSide(color: active(s) ? p.borderStrong : p.border);
        }),
        labelStyle: text.labelLarge!.copyWith(
          fontWeight: FontWeight.w500,
          color: WidgetStateColor.resolveWith((s) => has(s, WidgetState.selected) ? p.primary : p.text),
        ),
        secondaryLabelStyle: text.labelLarge!.copyWith(color: p.primary),
        iconTheme: IconThemeData(color: p.muted, size: 18),
        deleteIconColor: p.muted,
        checkmarkColor: p.primary,
        showCheckmark: false,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppSpacing.xs),
        labelPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: p.primarySoft,
        indicatorShape: const RoundedRectangleBorder(borderRadius: AppRadii.inputAll),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected)
              ? text.labelSmall!.copyWith(color: p.primary, fontWeight: FontWeight.w600)
              : text.labelSmall!.copyWith(color: p.muted, fontWeight: FontWeight.w500),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(size: 22, color: has(s, WidgetState.selected) ? p.primary : p.muted),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.background,
        elevation: 0,
        indicatorColor: p.primarySoft,
        indicatorShape: const RoundedRectangleBorder(borderRadius: AppRadii.inputAll),
        selectedIconTheme: IconThemeData(color: p.primary, size: 22),
        unselectedIconTheme: IconThemeData(color: p.muted, size: 22),
        selectedLabelTextStyle: text.labelMedium!.copyWith(color: p.primary, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: text.labelMedium!.copyWith(color: p.muted, fontWeight: FontWeight.w500),
        minWidth: 84,
        minExtendedWidth: 232,
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
        constraints: const BoxConstraints(maxWidth: Breakpoints.maxSheet),
        modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.62 : 0.38),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: p.shadow,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: p.border),
        ),
        titleTextStyle: text.titleMedium,
        contentTextStyle: text.bodyMedium!.copyWith(color: p.muted),
        barrierColor: Colors.black.withValues(alpha: isDark ? 0.62 : 0.38),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? p.surfaceRaised : p.text,
        contentTextStyle: text.bodyMedium!.copyWith(color: isDark ? p.text : p.background, fontWeight: FontWeight.w500),
        actionTextColor: isDark ? p.primary : AppColors.mint,
        closeIconColor: isDark ? p.muted : p.background,
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.inputAll,
          side: BorderSide(color: isDark ? p.borderStrong : AppColors.darkBorderStrong),
        ),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: p.muted,
        textColor: p.text,
        titleTextStyle: text.bodyLarge!.copyWith(fontWeight: FontWeight.w500, fontSize: 15),
        subtitleTextStyle: text.bodySmall,
        leadingAndTrailingTextStyle: text.bodyMedium!.copyWith(color: p.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        minVerticalPadding: 10,
        minLeadingWidth: 24,
        shape: const RoundedRectangleBorder(borderRadius: AppRadii.inputAll),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
          shape: const WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: AppRadii.inputAll)),
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
        valueIndicatorColor: p.surfaceRaised,
        valueIndicatorTextStyle: AppType.mono(text.labelMedium!.copyWith(color: p.text)),
        valueIndicatorStrokeColor: p.borderStrong,
        trackHeight: 4,
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected) ? p.onPrimary : p.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => has(s, WidgetState.selected) ? p.primary : p.surfaceVariant,
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
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
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
        labelColor: p.text,
        unselectedLabelColor: p.muted,
        indicatorColor: p.primary,
        dividerColor: p.border,
        indicatorSize: TabBarIndicatorSize.label,
        overlayColor: neutralOverlay,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall!.copyWith(fontWeight: FontWeight.w500),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.primary,
        textColor: p.onPrimary,
        smallSize: 8,
        largeSize: 18,
        textStyle: text.labelSmall!.copyWith(fontWeight: FontWeight.w700, fontFeatures: AppType.tabular),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: p.shadow,
        textStyle: text.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.inputAll, side: BorderSide(color: p.border)),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shadowColor: WidgetStatePropertyAll(p.shadow),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: AppRadii.inputAll, side: BorderSide(color: p.border)),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: p.surfaceRaised,
          borderRadius: AppRadii.tagAll,
          border: Border.all(color: p.borderStrong),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        textStyle: text.labelMedium!.copyWith(color: p.text, fontWeight: FontWeight.w500),
        waitDuration: const Duration(milliseconds: 500),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => active(s) ? p.borderStrong : p.borderStrong.withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
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
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surface,
      surfaceContainer: p.surfaceVariant,
      surfaceContainerHigh: p.surfaceVariant,
      surfaceContainerHighest: p.surfaceRaised,
      onSurfaceVariant: p.muted,
      outline: p.borderStrong,
      outlineVariant: p.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: p.text,
      onInverseSurface: p.background,
      inversePrimary: isDark ? AppColors.mintDeep : AppColors.mint,
      surfaceTint: Colors.transparent,
    );
  }

  /// Type scale. `display*` / `headline*` are the editorial serif
  /// (Source Serif 4); `title*` / `body*` / `label*` are Inter.
  static TextTheme _textTheme(AppPalette p) {
    TextStyle style(double size, FontWeight weight, double tracking, double height) =>
        TextStyle(fontSize: size, fontWeight: weight, letterSpacing: tracking, height: height);

    final base = TextTheme(
      displayLarge: style(46, FontWeight.w700, -0.9, 1.06),
      displayMedium: style(38, FontWeight.w700, -0.7, 1.08),
      displaySmall: style(32, FontWeight.w700, -0.5, 1.12),
      headlineLarge: style(28, FontWeight.w700, -0.4, 1.16),
      headlineMedium: style(24, FontWeight.w700, -0.3, 1.2),
      headlineSmall: style(20, FontWeight.w600, -0.2, 1.25),
      titleLarge: style(18, FontWeight.w600, -0.3, 1.3),
      titleMedium: style(16, FontWeight.w600, -0.2, 1.35),
      titleSmall: style(14, FontWeight.w600, -0.1, 1.35),
      bodyLarge: style(16, FontWeight.w400, -0.1, 1.5),
      bodyMedium: style(14, FontWeight.w400, 0, 1.45),
      bodySmall: style(12, FontWeight.w400, 0, 1.4),
      labelLarge: style(14, FontWeight.w600, -0.1, 1.2),
      labelMedium: style(12, FontWeight.w600, 0, 1.2),
      labelSmall: style(11, FontWeight.w600, 0.2, 1.2),
    ).apply(bodyColor: p.text, displayColor: p.text);

    final themed = base.copyWith(bodySmall: base.bodySmall!.copyWith(color: p.muted));
    final sans = useGoogleFonts ? GoogleFonts.interTextTheme(themed) : themed;
    return sans.copyWith(
      displayLarge: AppType.serif(sans.displayLarge!),
      displayMedium: AppType.serif(sans.displayMedium!),
      displaySmall: AppType.serif(sans.displaySmall!),
      headlineLarge: AppType.serif(sans.headlineLarge!),
      headlineMedium: AppType.serif(sans.headlineMedium!),
      headlineSmall: AppType.serif(sans.headlineSmall!),
    );
  }
}

/// Subtle fade + scale page transition (Material "fade through" feel).
/// Falls back to an instant switch when the OS asks for reduced motion.
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
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    return FadeTransition(
      opacity: animation.drive(_fade),
      child: ScaleTransition(scale: animation.drive(_scale), child: child),
    );
  }
}
