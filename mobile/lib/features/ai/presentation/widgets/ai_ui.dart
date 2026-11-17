import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// The AI mark — delegates to the shared identity widget in core/widgets
/// so the design system's mark flows into every AI surface.
class AiMark extends StatelessWidget {
  const AiMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) => AiSparkleIcon(size: size);
}

/// Text in the AI accent (titles on AI surfaces).
class AiText extends StatelessWidget {
  const AiText(this.text, {super.key, this.style, this.maxLines, this.textAlign});

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: maxLines,
    textAlign: textAlign,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: (style ?? context.textTheme.titleMedium)?.copyWith(color: context.colors.ai),
  );
}

/// Card for AI content: soft AI tint, hairline accent border, no effects.
class AiCard extends StatelessWidget {
  const AiCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpacing.md)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Color.alphaBlend(colors.aiSoft.withValues(alpha: 0.6), colors.surface),
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: colors.ai.withValues(alpha: 0.25)),
      ),
      child: child,
    );
  }
}

/// The assistant's avatar slot in chat. Renders only the shared identity
/// mark (no custom mascot) so a new Zelora AI identity applies everywhere.
class AiAvatar extends StatelessWidget {
  const AiAvatar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: Center(child: AiSparkleIcon(size: size * 0.8)),
  );
}

/// Horizontal confidence/score bar (solid token fill), animated from 0.
class AiConfidenceBar extends StatelessWidget {
  const AiConfidenceBar({super.key, required this.value, this.height = 6, this.color, this.semanticLabel});

  /// 0..1
  final double value;
  final double height;

  /// Fill color (defaults to `colors.primary`).
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: ClipRRect(
        borderRadius: AppRadii.pillAll,
        child: SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: colors.surfaceVariant)),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: v),
                duration: context.motion(const Duration(milliseconds: 600)),
                curve: AppCurves.standard,
                builder: (context, t, _) => FractionallySizedBox(
                  widthFactor: t,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: color ?? colors.primary, borderRadius: AppRadii.pillAll),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Labeled score row: `intent_name ███████░░ 87%`.
class ScoreRow extends StatelessWidget {
  const ScoreRow({super.key, required this.label, required this.value, this.highlight = false, this.labelWidth = 128});

  final String label;
  final double value;
  final bool highlight;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final style = t.labelMedium!.copyWith(
      color: highlight ? colors.text : colors.muted,
      fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final lw = math.min(labelWidth, c.maxWidth * 0.42);
        return Row(
          children: [
            SizedBox(width: lw, child: Text(label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: AiConfidenceBar(value: value, color: highlight ? colors.primary : colors.secondary.withValues(alpha: 0.45)),
            ),
            const SizedBox(width: AppSpacing.xs),
            SizedBox(
              width: 44,
              child: Text(
                '${(value * 100).round()}%',
                textAlign: TextAlign.end,
                style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fades + slides its child in once, after [delay]. No-op under reduced motion.
class SlideFadeIn extends StatefulWidget {
  const SlideFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, 0.08),
    this.duration = AppDurations.slow,
    this.enabled = true,
  });

  final Widget child;
  final Duration delay;
  final Offset offset;
  final Duration duration;

  /// When false the child is shown immediately (e.g. history messages).
  final bool enabled;

  @override
  State<SlideFadeIn> createState() => _SlideFadeInState();
}

class _SlideFadeInState extends State<SlideFadeIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.duration);
  late final _curve = CurvedAnimation(parent: _c, curve: AppCurves.standard);
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.enabled || context.reduceMotion) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween(begin: widget.offset, end: Offset.zero).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// "Thinking" placeholder: pulsing orb, cycling status text and shimmer lines.
class AiThinking extends StatefulWidget {
  const AiThinking({
    super.key,
    this.messages = const ['Understanding your request…', 'Searching the catalog…', 'Ranking the best matches…'],
    this.lines = 3,
    this.compact = false,
  });

  final List<String> messages;
  final int lines;
  final bool compact;

  @override
  State<AiThinking> createState() => _AiThinkingState();
}

class _AiThinkingState extends State<AiThinking> {
  Timer? _timer;
  int _i = 0;

  @override
  void initState() {
    super.initState();
    if (widget.messages.length > 1) {
      _timer = Timer.periodic(const Duration(milliseconds: 1600), (_) {
        if (mounted) setState(() => _i = (_i + 1) % widget.messages.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.messages.isEmpty ? 'Thinking…' : widget.messages[_i % widget.messages.length];
    return Semantics(
      liveRegion: true,
      label: message,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const AiMark(size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AnimatedSwitcher(
                  duration: context.motion(AppDurations.normal),
                  child: AiText(
                    message,
                    key: ValueKey(message),
                    maxLines: 2,
                    style: context.textTheme.labelLarge,
                  ),
                ),
              ),
            ],
          ),
          if (widget.lines > 0) ...[
            SizedBox(height: widget.compact ? AppSpacing.xs : AppSpacing.sm),
            SkeletonText(lines: widget.lines, lineHeight: widget.compact ? 10 : 12),
          ],
        ],
      ),
    );
  }
}

/// Rounded suggestion chip used for quick replies, examples and follow-ups.
class AiSuggestionChip extends StatelessWidget {
  const AiSuggestionChip({super.key, required this.label, required this.onTap, this.icon, this.filled = false});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled ? colors.aiSoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.pillAll,
          side: BorderSide(color: filled ? colors.ai.withValues(alpha: 0.3) : colors.border),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon ?? Icons.auto_awesome, size: 14, color: colors.ai),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelLarge!.copyWith(color: colors.text, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small inline error with a retry link, for sections inside a page.
class AiInlineError extends StatelessWidget {
  const AiInlineError({super.key, required this.error, this.onRetry, this.title = "Couldn't load AI suggestions"});

  final Object error;
  final VoidCallback? onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: AppRadii.cardAll,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: colors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.textTheme.labelLarge),
                Text(
                  ApiException.from(error).message,
                  style: context.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Header used on AI pages/cards: sparkle + accent title + optional caption.
class AiHeader extends StatelessWidget {
  const AiHeader({super.key, required this.title, this.caption, this.trailing});

  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const AiMark(size: 18),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: AiText(title, style: context.textTheme.titleMedium, maxLines: 2),
              ),
              if (caption != null) Text(caption!, style: context.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}
