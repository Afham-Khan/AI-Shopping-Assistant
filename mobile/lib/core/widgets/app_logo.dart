import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';

/// The Zelora logo: the **Z-bag** mark (a bold geometric "Z" that doubles as
/// a shopping bag — its top bar is the bag's rim and a rounded handle rises
/// from it) on a royal-blue rounded tile, optionally followed by the
/// "Zelora" wordmark in Plus Jakarta Sans ExtraBold. Drawn in code
/// ([ZeloraMarkPainter]), so it is crisp from a 16 px favicon to a 512 px
/// store icon.
///
/// ```dart
/// AppLogo()                                  // mark + wordmark
/// AppLogo(size: 40, showWordmark: false)     // mark only
/// AppLogo(tileColor: Colors.white, glyphColor: colors.primary) // inverted
/// ```
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.showWordmark = true, this.tileColor, this.glyphColor, this.wordmarkColor});

  final double size;
  final bool showWordmark;

  /// Override the tile / glyph / wordmark colors (e.g. on a blue panel).
  final Color? tileColor;
  final Color? glyphColor;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: ZeloraMarkPainter(
          // the brand blue in both themes: the mark is an identity, not a state
          tile: tileColor ?? AppColors.blue,
          glyph: glyphColor ?? Colors.white,
        ),
      ),
    );

    if (!showWordmark) return Semantics(label: 'Zelora', image: true, child: mark);

    return Semantics(
      label: 'Zelora',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          mark,
          SizedBox(width: size * 0.28),
          ZeloraWordmark(size: size * 0.66, color: wordmarkColor ?? colors.text),
        ],
      ),
    );
  }
}

/// The "Zelora" wordmark alone: Plus Jakarta Sans ExtraBold, tight tracking.
class ZeloraWordmark extends StatelessWidget {
  const ZeloraWordmark({super.key, this.size = 22, this.color});

  /// Font size.
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Zelora',
      maxLines: 1,
      softWrap: false,
      textScaler: TextScaler.noScaling,
      style: AppType.sans(
        TextStyle(
          fontSize: size,
          height: 1,
          fontWeight: FontWeight.w800,
          letterSpacing: -size * 0.035,
          color: color ?? context.colors.text,
        ),
      ),
    );
  }
}

/// Paints the Zelora mark into a square. Public so `tool/generate_app_icons`
/// can render the launcher / favicon PNGs from the exact same geometry.
///
/// - [tile]: the rounded tile color (null = no tile, glyph only).
/// - [fullBleed]: fill the whole square (maskable / adaptive icon
///   backgrounds); the glyph is then scaled by [glyphScale] to sit inside
///   the platform safe zone.
class ZeloraMarkPainter extends CustomPainter {
  const ZeloraMarkPainter({
    this.tile = AppColors.blue,
    this.glyph = Colors.white,
    this.spark = true,
    this.fullBleed = false,
    this.glyphScale = 1,
  });

  final Color? tile;
  final Color glyph;

  /// Legacy: the mark no longer carries a spark (kept so old calls compile).
  final bool spark;
  final bool fullBleed;
  final double glyphScale;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final square = Offset.zero & Size(s, s);

    final tileColor = tile;
    if (tileColor != null) {
      // a whisper of depth: a touch lighter at the top, never a loud gradient
      final paint = Paint()
        ..isAntiAlias = true
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(tileColor, Colors.white, 0.10)!, Color.lerp(tileColor, Colors.black, 0.04)!],
        ).createShader(square);
      if (fullBleed) {
        canvas.drawRect(square, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(square, Radius.circular(s * 0.30)), paint);
      }
    }

    canvas.save();
    // glyph geometry is authored in a 100 × 100 box
    final scale = s / 100 * glyphScale;
    final inset = (s - 100 * scale) / 2;
    canvas.translate(inset, inset);
    canvas.scale(scale);
    _paintGlyph(canvas);
    canvas.restore();
  }

  void _paintGlyph(Canvas canvas) {
    final fill = Paint()
      ..color = glyph
      ..isAntiAlias = true;
    // a stroke in the same color softens every corner of the Z
    final soften = Paint()
      ..color = glyph
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round;

    const dx = 0.0;
    const dy = 0.0;
    Offset p(double x, double y) => Offset(x + dx, y + dy);

    // Z: rim (top bar), diagonal, base (bottom bar)
    final z = Path()
      ..addPolygon([
        p(30, 38),
        p(70, 38),
        p(70, 47.5),
        p(46.5, 68.5),
        p(70, 68.5),
        p(70, 78),
        p(30, 78),
        p(30, 68.5),
        p(53.5, 47.5),
        p(30, 47.5),
      ], true);
    canvas.drawPath(z, fill);
    canvas.drawPath(z, soften);

    // bag handle rising from the rim
    final handle = Path()
      ..moveTo(38.5 + dx, 38 + dy)
      ..lineTo(38.5 + dx, 35 + dy)
      ..arcToPoint(Offset(61.5 + dx, 35 + dy), radius: const Radius.circular(11.5))
      ..lineTo(61.5 + dx, 38 + dy);
    canvas.drawPath(
      handle,
      Paint()
        ..color = glyph
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

  }

  @override
  bool shouldRepaint(ZeloraMarkPainter old) =>
      old.tile != tile || old.glyph != glyph || old.spark != spark || old.fullBleed != fullBleed || old.glyphScale != glyphScale;
}
