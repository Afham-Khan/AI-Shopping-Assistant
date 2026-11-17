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

/// Corner radii (v2, soft and rounded): 8 tags / kbd chips · 14 inputs and
/// small tiles · 18 cards and dialogs · 24 sheets and the app frame · full
/// pills for buttons, chips, badges and the search bar.
abstract final class AppRadii {
  static const double tag = 8;
  static const double input = 14;
  static const double card = 18;
  static const double sheet = 24;
  static const double frame = 36;
  static const double pill = 999;

  static const tagAll = BorderRadius.all(Radius.circular(tag));
  static const inputAll = BorderRadius.all(Radius.circular(input));
  static const cardAll = BorderRadius.all(Radius.circular(card));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
  static const sheetAll = BorderRadius.all(Radius.circular(sheet));
  static const frameAll = BorderRadius.all(Radius.circular(frame));
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
///
/// Zelora is a mobile app everywhere: on screens wider than [frameFrom] the
/// whole app renders inside a centred phone-width column ([appColumn]) —
/// see `AppFrame`. Inside that column every screen sees a phone-sized
/// MediaQuery, so `context.isWide` is false and the bottom bar is always on.
abstract final class Breakpoints {
  /// Width of the app column on tablet / desktop / web.
  static const double appColumn = 460;

  /// Windows at least this wide get the framed app column.
  static const double frameFrom = 600;

  /// Legacy: tablet layouts. Only reachable on phones in landscape now.
  static const double compact = 700;

  /// Legacy: desktop layouts (no longer reachable inside the app column).
  static const double expanded = 1100;

  /// Max width of page content on large screens.
  static const double maxContent = 1200;

  /// Max width for forms / auth pages / sheets.
  static const double maxForm = 440;
  static const double maxSheet = 640;
}
