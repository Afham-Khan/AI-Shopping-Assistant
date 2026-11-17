import 'package:material_ui/material_ui.dart';

import '../theme/app_typography.dart';
import '../utils/extensions.dart';

/// Brand mark: an accent tile with a geometric "Z" cut from straight edges,
/// optionally followed by the serif "Zelora" wordmark. Drawn in code, so it
/// is crisp at every size and follows the theme.
///
/// ```dart
/// AppLogo()                                  // mark + wordmark
/// AppLogo(size: 40, showWordmark: false)     // mark only
/// AppLogo(tileColor: colors.text, glyphColor: colors.background) // mono
/// ```
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.showWordmark = true, this.tileColor, this.glyphColor, this.wordmarkColor});

  final double size;
  final bool showWordmark;

  /// Override the tile / glyph / wordmark colors (e.g. on a fixed dark panel).
  final Color? tileColor;
  final Color? glyphColor;
  final Color? wordmarkColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(tile: tileColor ?? colors.primary, glyph: glyphColor ?? colors.onPrimary),
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
          SizedBox(width: size * 0.3),
          Text(
            'Zelora',
            style: AppType.serif(
              TextStyle(
                fontSize: size * 0.66,
                height: 1,
                fontWeight: FontWeight.w700,
                letterSpacing: -size * 0.012,
                color: wordmarkColor ?? colors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.tile, required this.glyph});

  final Color tile;
  final Color glyph;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & Size(s, s), Radius.circular(s * 0.27)),
      Paint()..color = tile,
    );

    // a Z built from two bars and a parallel-edged diagonal
    Offset p(double x, double y) => Offset(x * s, y * s);
    final z = Path()
      ..addPolygon([
        p(0.285, 0.285),
        p(0.715, 0.285),
        p(0.715, 0.395),
        p(0.455, 0.605),
        p(0.715, 0.605),
        p(0.715, 0.715),
        p(0.285, 0.715),
        p(0.285, 0.605),
        p(0.545, 0.395),
        p(0.285, 0.395),
      ], true);
    canvas.drawPath(
      z,
      Paint()
        ..color = glyph
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.tile != tile || old.glyph != glyph;
}
