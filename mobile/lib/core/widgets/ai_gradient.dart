import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/extensions.dart';

/// The AI accent. Despite the legacy name there is **no gradient**: AI
/// surfaces use the single Zelora accent, flat. Use these only on AI
/// surfaces: the assistant ("Zel"), match badges, recommendation rails,
/// smart search.
abstract final class AiGradient {
  /// Flat two-stop "gradient" kept for older call sites.
  static const linear = AppColors.aiGradient;

  /// Paints [child] (icon/text) in the solid AI accent.
  static Widget mask({required Widget child}) => Builder(
    builder: (context) => ColorFiltered(
      colorFilter: ColorFilter.mode(context.colors.ai, BlendMode.srcIn),
      child: child,
    ),
  );
}

/// Zel's mark: a single crisp four-point spark, drawn in code so it stays
/// sharp at any size. `AiSparkleIcon(size: 20)`.
///
/// [filled] false draws the outline (unselected nav state).
class AiSparkleIcon extends StatelessWidget {
  const AiSparkleIcon({super.key, this.size = 20, this.semanticLabel, this.filled = true, this.color});

  final double size;
  final String? semanticLabel;
  final bool filled;

  /// Defaults to the AI accent; pass `IconTheme.of(context).color` to follow a parent.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _SparkPainter(color ?? context.colors.ai, filled)),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _SparkPainter extends CustomPainter {
  const _SparkPainter(this.color, this.filled);

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = s / 2;
    final stroke = (s * 0.075).clamp(1.2, 2.0);
    // the outline is inset so both versions share the same optical size
    final r = filled ? s * 0.47 : s * 0.47 - stroke / 2;
    final k = s * 0.085; // how far the waist pinches in

    final path = Path()
      ..moveTo(c, c - r)
      ..quadraticBezierTo(c + k, c - k, c + r, c)
      ..quadraticBezierTo(c + k, c + k, c, c + r)
      ..quadraticBezierTo(c - k, c + k, c - r, c)
      ..quadraticBezierTo(c - k, c - k, c, c - r)
      ..close();

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    if (filled) {
      canvas.drawPath(path, paint);
    } else {
      canvas.drawPath(
        path,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.color != color || old.filled != filled;
}

/// Text in the solid AI accent. `AiGradientText('Ask Zel')`.
class AiGradientText extends StatelessWidget {
  const AiGradientText(this.text, {super.key, this.style, this.maxLines, this.textAlign});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: maxLines,
      textAlign: textAlign,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: (style ?? context.textTheme.titleMedium)?.copyWith(color: context.colors.ai),
    );
  }
}

/// Small pill marking AI content: `AiBadge()` → "✦ AI", `AiBadge(label: '92% match')`.
class AiBadge extends StatelessWidget {
  const AiBadge({super.key, this.label = 'AI', this.solid = true});

  final String label;

  /// Solid accent fill (for use over photos); otherwise a soft accent tint
  /// with a hairline (for use on surfaces).
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = solid ? colors.onPrimary : colors.ai;
    final style = context.textTheme.labelSmall!.copyWith(
      color: ink,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.1,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 3, 7, 3),
      decoration: BoxDecoration(
        color: solid ? colors.ai : colors.aiSoft,
        borderRadius: AppRadii.tagAll,
        border: solid ? null : Border.all(color: colors.ai.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AiSparkleIcon(size: 10, color: ink),
          const SizedBox(width: 4),
          Flexible(child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// A container with a hairline accent border — for AI cards (review summary,
/// recommendations header, assistant entry point). Solid, no gradient.
class AiGradientBorder extends StatelessWidget {
  const AiGradientBorder({
    super.key,
    required this.child,
    this.borderRadius = AppRadii.card,
    this.borderWidth = 1,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.tinted = true,
  });

  final Widget child;
  final double borderRadius;
  final double borderWidth;
  final EdgeInsetsGeometry padding;

  /// Fill with the soft AI tint instead of the plain surface.
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tinted ? Color.alphaBlend(colors.aiSoft.withValues(alpha: 0.55), colors.surface) : colors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: colors.ai.withValues(alpha: 0.45), width: borderWidth),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
