import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// Zelora speaks in ONE family: **Plus Jakarta Sans** — a geometric sans with
/// soft, rounded-feeling bowls, a tall x-height that stays legible at 11–13 px,
/// and a full 200–800 weight range. Hierarchy comes from weight and size, not
/// from switching fonts:
///
/// - 800 — big screen titles, the wordmark
/// - 700 — headings, section titles, prices, buttons
/// - 600 — labels, chips, nav labels, card titles
/// - 400/500 — body copy and captions
///
/// Every number that changes or lines up (prices, counts, order numbers)
/// uses tabular figures: `fontFeatures: AppType.tabular`.
///
/// The old `serif` / `mono` helpers are kept for call sites but now return
/// the same family (serif → heavier display cut, mono → tabular figures).
abstract final class AppType {
  /// Tests switch this off because Google Fonts would hit the network.
  static bool useGoogleFonts = true;

  /// The family name, for code that builds a raw [TextStyle].
  static const family = 'Plus Jakarta Sans';

  static const tabular = [FontFeature.tabularFigures()];

  /// Applies the brand family to [base].
  static TextStyle sans(TextStyle base) => useGoogleFonts ? GoogleFonts.plusJakartaSans(textStyle: base) : base;

  /// Applies the brand family to a whole text theme.
  static TextTheme sansTheme(TextTheme base) => useGoogleFonts ? GoogleFonts.plusJakartaSansTextTheme(base) : base;

  /// Legacy "editorial" voice — now the display cut of the same family
  /// (weight 800 if the style was lighter). Prefer `context.textTheme` styles.
  static TextStyle serif(TextStyle base) {
    final weight = base.fontWeight;
    final heavier = weight == null || weight.value < FontWeight.w700.value ? FontWeight.w800 : weight;
    return sans(base.copyWith(fontWeight: heavier));
  }

  /// Legacy "ledger" voice — now the same family with tabular figures, for
  /// order numbers, SKUs, counters and timestamps.
  static TextStyle mono(TextStyle base) => sans(base.copyWith(fontFeatures: tabular));

  /// Small label above a heading ("PICKED FOR YOU"): 11.5 px, bold, lightly
  /// tracked, brand blue. Pass text already upper-cased or use `Eyebrow`.
  static TextStyle eyebrow(BuildContext context, {Color? color}) {
    final palette = Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
    return sans(
      TextStyle(
        fontSize: 11.5,
        height: 1.3,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: color ?? palette.primary,
      ),
    );
  }

  /// Data value: order numbers, SKUs, specs, latency, timestamps (tabular).
  static TextStyle data(BuildContext context, {Color? color, double size = 12, FontWeight weight = FontWeight.w500}) {
    final palette = Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
    return mono(TextStyle(fontSize: size, height: 1.35, fontWeight: weight, letterSpacing: 0, color: color ?? palette.muted));
  }
}
