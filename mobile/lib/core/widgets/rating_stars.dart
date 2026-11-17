import 'package:material_ui/material_ui.dart';

import '../theme/app_typography.dart';
import '../utils/extensions.dart';
import '../utils/formatters.dart';

/// Star rating.
///
/// - `RatingStars(4.6, count: 128)` → ★ 4.6 (128) — compact, for cards
/// - `RatingStars.full(4.6, size: 18)` → ★★★★½ with partial fill
class RatingStars extends StatelessWidget {
  const RatingStars(this.rating, {super.key, this.count, this.size = 14, this.showValue = true})
    : full = false;

  const RatingStars.full(this.rating, {super.key, this.count, this.size = 16, this.showValue = false})
    : full = true;

  final double rating;
  final int? count;
  final double size;
  final bool showValue;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final clamped = rating.clamp(0, 5).toDouble();
    final textStyle = context.textTheme.bodySmall!.copyWith(
      fontSize: size * 0.9,
      color: colors.faint,
      fontFeatures: AppType.tabular,
    );
    // nothing rated yet: say so instead of showing a sad 0.0
    final unrated = !full && clamped == 0 && (count ?? 0) == 0;

    final label = StringBuffer(unrated ? 'No reviews yet' : 'Rated ${Formatters.rating(clamped)} out of 5');
    if (count != null) label.write(', ${Formatters.plural(count!, 'review')}');

    return Semantics(
      label: label.toString(),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unrated) ...[
            Icon(Icons.star_outline_rounded, size: size + 2, color: colors.faint),
            const SizedBox(width: 3),
            Text('New', style: textStyle.copyWith(fontWeight: FontWeight.w500)),
          ] else ...[
          if (full)
            for (var i = 0; i < 5; i++) _Star(fill: (clamped - i).clamp(0, 1).toDouble(), size: size)
          else
            Icon(Icons.star_rounded, size: size + 2, color: colors.star),
          if (showValue || !full) ...[
            const SizedBox(width: 3),
            Text(
              Formatters.rating(clamped),
              style: textStyle.copyWith(color: colors.text, fontWeight: FontWeight.w600),
            ),
          ],
          if (count != null) ...[
            const SizedBox(width: 3),
            Flexible(
              child: Text(
                '(${Formatters.compact(count)})',
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          ],
        ],
      ),
    );
  }
}

class _Star extends StatelessWidget {
  const _Star({required this.fill, required this.size});

  /// 0..1
  final double fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox.square(
      dimension: size + 2,
      child: Stack(
        children: [
          Icon(Icons.star_rounded, size: size + 2, color: colors.surfaceRaised),
          ClipRect(
            clipper: _FractionClipper(fill),
            child: Icon(Icons.star_rounded, size: size + 2, color: colors.star),
          ),
        ],
      ),
    );
  }
}

class _FractionClipper extends CustomClipper<Rect> {
  const _FractionClipper(this.fraction);

  final double fraction;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, size.width * fraction, size.height);

  @override
  bool shouldReclip(_FractionClipper oldClipper) => oldClipper.fraction != fraction;
}
