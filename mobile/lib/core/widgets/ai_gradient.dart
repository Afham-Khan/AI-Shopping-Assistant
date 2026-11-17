import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/extensions.dart';
import 'ai_mascot.dart';

/// The AI accent. Despite the legacy name there is **no gradient**: AI
/// surfaces use the single Zelora royal blue, flat. Use these only on AI
/// surfaces: the assistant, match badges, recommendation rails,
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

/// The assistant's mark at icon size — now the bag mascot ([AiMascot]),
/// static and simplified so it reads at 16–20 px. The name is kept so every
/// existing call site picks the mascot up. `AiSparkleIcon(size: 20)`.
///
/// [filled] false draws the outlined bag (quiet / unselected states).
/// For a larger, animated mascot with moods use [AiMascot] directly.
class AiSparkleIcon extends StatelessWidget {
  const AiSparkleIcon({super.key, this.size = 20, this.semanticLabel, this.filled = true, this.color});

  final double size;
  final String? semanticLabel;
  final bool filled;

  /// Defaults to the AI accent; pass `IconTheme.of(context).color` to follow a parent.
  final Color? color;

  @override
  Widget build(BuildContext context) => AiMascot(
    size: size,
    color: color,
    outline: !filled,
    animate: false,
    semanticLabel: semanticLabel,
  );
}

/// Text in the solid AI accent. `AiGradientText('Ask ${AppConfig.assistantName}')`.
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

/// Small pill marking AI content (mascot + label): `AiBadge()`, `AiBadge(label: '92% match')`.
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
      padding: const EdgeInsets.fromLTRB(7, 3, 8, 3),
      decoration: BoxDecoration(
        color: solid ? colors.ai : colors.aiSoft,
        borderRadius: AppRadii.pillAll,
        border: solid ? null : Border.all(color: colors.ai.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AiSparkleIcon(size: 12, color: ink),
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
        border: Border.all(color: colors.ai.withValues(alpha: 0.30), width: borderWidth),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
