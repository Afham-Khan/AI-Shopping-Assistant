import 'package:material_ui/material_ui.dart';

/// Spacing scale (4/8/12/16/20/24/32/48). Use these instead of raw numbers.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Default horizontal page gutter on phones.
  static const double page = 16;

  /// Page gutter on tablets/desktop.
  static const double pageWide = 24;

  static const gapXxs = SizedBox(width: xxs, height: xxs);
  static const gapXs = SizedBox(width: xs, height: xs);
  static const gapSm = SizedBox(width: sm, height: sm);
  static const gapMd = SizedBox(width: md, height: md);
  static const gapLg = SizedBox(width: lg, height: lg);
  static const gapXl = SizedBox(width: xl, height: xl);
  static const gapXxl = SizedBox(width: xxl, height: xxl);
  static const gapXxxl = SizedBox(width: xxxl, height: xxxl);
}

/// Corner radii: 6 tags/kbd chips, 8 inputs/buttons, 12 cards/dialogs, 16 sheets, full pills (chips, badges).
abstract final class AppRadii {
  static const double tag = 6;
  static const double input = 8;
  static const double card = 12;
  static const double sheet = 16;
  static const double pill = 999;

  static const tagAll = BorderRadius.all(Radius.circular(tag));
  static const inputAll = BorderRadius.all(Radius.circular(input));
  static const cardAll = BorderRadius.all(Radius.circular(card));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
  static const sheetAll = BorderRadius.all(Radius.circular(sheet));
  static const pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Motion tokens. Keep motion subtle; widgets should check
/// `context.reduceMotion` and skip non-essential animation.
abstract final class AppDurations {
  /// Hover / press / focus color changes.
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);

  /// Color / border transitions on buttons, cards and links.
  static const color = Duration(milliseconds: 300);

  /// Bottom sheets (ease-out).
  static const sheet = Duration(milliseconds: 450);
  static const slow = Duration(milliseconds: 400);
  static const page = Duration(milliseconds: 300);
}

abstract final class AppCurves {
  static const standard = Curves.easeOutCubic;
  static const emphasized = Curves.easeInOutCubicEmphasized;
}

/// Layout breakpoints (logical pixels, by width).
abstract final class Breakpoints {
  /// Below this (in portrait) the shell uses a bottom bar, otherwise a rail.
  static const double compact = 700;

  /// Rail becomes extended (labels beside icons) from here.
  static const double expanded = 1100;

  /// Max width of page content on large screens.
  static const double maxContent = 1200;

  /// Max width for forms / auth pages / sheets.
  static const double maxForm = 440;
  static const double maxSheet = 640;
}
