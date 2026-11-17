import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';

import 'app_colors.dart';

/// Zelora's three voices:
///
/// - **Serif** (Source Serif 4) — the editorial voice: hero headings, section
///   titles, product names on the detail page. Already applied to every
///   `display*` / `headline*` style in the text theme.
/// - **Sans** (Inter) — the interface: everything else. Prices use Inter with
///   tabular figures ([tabular]).
/// - **Mono** (JetBrains Mono) — the ledger: eyebrows, order numbers, SKUs,
///   spec values, timestamps, keyboard chips, status lines.
abstract final class AppType {
  /// Tests switch this off because Google Fonts would hit the network.
  static bool useGoogleFonts = true;

  static const tabular = [FontFeature.tabularFigures()];

  /// Editorial serif. `AppType.serif(context.textTheme.titleLarge!)`.
  static TextStyle serif(TextStyle base) =>
      useGoogleFonts ? GoogleFonts.sourceSerif4(textStyle: base) : base.copyWith(fontFamily: 'serif');

  /// Ledger mono, always with tabular figures.
  static TextStyle mono(TextStyle base) {
    final style = base.copyWith(fontFeatures: tabular);
    return useGoogleFonts ? GoogleFonts.jetBrainsMono(textStyle: style) : style.copyWith(fontFamily: 'monospace');
  }

  /// Small uppercase letter-spaced label (pass text already upper-cased, or
  /// use the `Eyebrow` widget which does it for you).
  static TextStyle eyebrow(BuildContext context, {Color? color}) {
    final palette = Theme.of(context).extension<AppPalette>() ?? AppPalette.dark;
    return mono(
      TextStyle(
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.3,
        color: color ?? palette.primary,
      ),
    );
  }

  /// Mono data value: order numbers, SKUs, specs, latency, timestamps.
  static TextStyle data(BuildContext context, {Color? color, double size = 12, FontWeight weight = FontWeight.w500}) {
    final palette = Theme.of(context).extension<AppPalette>() ?? AppPalette.dark;
    return mono(TextStyle(fontSize: size, height: 1.35, fontWeight: weight, letterSpacing: 0, color: color ?? palette.muted));
  }
}
