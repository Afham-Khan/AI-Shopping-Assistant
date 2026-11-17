import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';
import 'feedback.dart';

/// Small uppercase mono label that sits above a heading.
///
/// ```dart
/// Eyebrow('Picked for you')                       // PICKED FOR YOU
/// Eyebrow('Trending', index: 2)                   // 02 — TRENDING
/// Eyebrow('Store online · 38 ms', dot: true)      // ● STORE ONLINE · 38 MS
/// Eyebrow('Ends in 02:14:09', color: colors.sale)
/// ```
/// One per section, never two stacked. Keep it under ~32 characters.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.label, {super.key, this.index, this.dot = false, this.color, this.leading, this.textAlign});

  final String label;

  /// Section number, rendered as a two-digit prefix ("01 —").
  final int? index;

  /// A small filled dot before the label (status / "live" lines).
  final bool dot;
  final Color? color;

  /// Custom leading widget instead of the dot (e.g. `AiSparkleIcon(size: 11)`).
  final Widget? leading;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = color ?? colors.primary;
    final style = AppType.eyebrow(context, color: ink);

    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (index != null) ...[
            Text(index!.toString().padLeft(2, '0'), style: style.copyWith(color: colors.faint)),
            Container(
              width: 14,
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 8),
              color: colors.borderStrong,
            ),
          ] else if (leading != null) ...[
            leading!,
            const SizedBox(width: 6),
          ] else if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
            ),
          ),
        ],
      ),
    );
  }
}

/// A big confident number with a tiny caption — for "at a glance" rows.
///
/// ```dart
/// Row(children: [
///   StatBlock(value: '194', caption: 'Products'),
///   StatBlock(value: '4.6', caption: 'Avg rating', valueColor: colors.star),
/// ])
/// ```
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.value,
    required this.caption,
    this.valueColor,
    this.compact = false,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.count,
  });

  /// Counts up to [count] when it appears (1.2 s ease-out). Until the number
  /// is known pass null and an em dash is shown.
  const StatBlock.count({
    super.key,
    required this.count,
    required this.caption,
    this.valueColor,
    this.compact = false,
    this.crossAxisAlignment = CrossAxisAlignment.start,
  }) : value = '\u2014';

  /// Animated number; takes precedence over [value] when set.
  final num? count;

  final String value;
  final String caption;
  final Color? valueColor;

  /// Smaller number (24 px instead of 32 px).
  final bool compact;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final number = (compact ? t.headlineMedium! : t.displaySmall!).copyWith(
      color: valueColor ?? colors.text,
      fontFeatures: AppType.tabular,
      height: 1.05,
    );
    return Semantics(
      label: '$caption: ${count ?? value}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          if (count != null) CountUp(count!, style: number) else Text(value, style: number, maxLines: 1),
          const SizedBox(height: 6),
          Text(
            caption.toUpperCase(),
            style: AppType.eyebrow(context, color: colors.faint).copyWith(fontSize: 10, letterSpacing: 1.1),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Keyboard key chip, e.g. `KbdChip('Ctrl')`, `KbdChip('K')`, `KbdChip('/')`.
/// Show only where the shortcut really works (web/desktop).
class KbdChip extends StatelessWidget {
  const KbdChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.surfaceRaised,
        borderRadius: AppRadii.tagAll,
        border: Border.all(color: colors.borderStrong.withValues(alpha: 0.7)),
        // a hard (unblurred) lower edge reads as a physical key
        boxShadow: [BoxShadow(color: colors.borderStrong, offset: const Offset(0, 1.5))],
      ),
      child: Text(
        label,
        style: AppType.data(context, color: colors.muted, size: 10.5, weight: FontWeight.w600).copyWith(height: 1),
      ),
    );
  }
}

/// A row of key/value facts in the ledger voice (mono values).
///
/// ```dart
/// KeyValueRow(label: 'Order', value: '#ZL-10482')
/// KeyValueRow(label: 'Version', value: '0.1.0', onTap: copy)
/// ```
class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value, this.valueColor, this.trailing, this.copyable = false});

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  /// Tap to copy the value (confirms with a snack).
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final row = _row(context);
    if (!copyable) return row;
    return Tooltip(
      message: 'Copy',
      child: InkWell(onTap: () => copyToClipboard(context, value, label: label), child: row),
    );
  }

  Widget _row(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 13),
      child: Row(
        children: [
          Text(label, style: context.textTheme.bodyMedium!.copyWith(color: colors.muted)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.data(context, color: valueColor ?? colors.text, size: 12.5),
            ),
          ),
          if (copyable) ...[
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.copy_rounded, size: 13, color: colors.faint),
          ],
          if (trailing != null) ...[const SizedBox(width: AppSpacing.xs), trailing!],
        ],
      ),
    );
  }
}

/// Subtle dot grid behind hero areas (auth panels, empty states, banners).
/// Flat dots only — no fade, no glow.
///
/// ```dart
/// DotGridBackground(child: Padding(padding: ..., child: hero))
/// ```
class DotGridBackground extends StatelessWidget {
  const DotGridBackground({super.key, this.child, this.spacing = 22, this.dotRadius = 1, this.color, this.lines = false});

  final Widget? child;
  final double spacing;
  final double dotRadius;
  final Color? color;

  /// Draw hairline grid lines instead of dots.
  final bool lines;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GridPainter(color ?? context.colors.grid, spacing, dotRadius, lines),
      child: child,
    );
  }
}

class _GridPainter extends CustomPainter {
  const _GridPainter(this.color, this.spacing, this.radius, this.lines);

  final Color color;
  final double spacing;
  final double radius;
  final bool lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (lines) {
      for (var x = spacing; x < size.width; x += spacing) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
      for (var y = spacing; y < size.height; y += spacing) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      }
      return;
    }
    for (var y = spacing / 2; y < size.height; y += spacing) {
      for (var x = spacing / 2; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.color != color || old.spacing != spacing || old.radius != radius || old.lines != lines;
}

/// Solid card with a hairline border and a thin colored top edge — the
/// department / category card. Hover lifts the border, never the fill.
///
/// ```dart
/// CategoryTopBorderCard(
///   accent: context.colors.departmentAccent(dept.slug),
///   onTap: () => context.push(Routes.productList(department: dept.slug)),
///   child: Column(children: [Text(dept.name), Text('38 products')]),
/// )
/// ```
class CategoryTopBorderCard extends StatefulWidget {
  const CategoryTopBorderCard({
    super.key,
    required this.child,
    this.accent,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.topBorderWidth = 2,
    this.semanticLabel,
  });

  final Widget child;

  /// Top edge color; defaults to the app accent.
  final Color? accent;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double topBorderWidth;
  final String? semanticLabel;

  @override
  State<CategoryTopBorderCard> createState() => _CategoryTopBorderCardState();
}

class _CategoryTopBorderCardState extends State<CategoryTopBorderCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final interactive = widget.onTap != null;
    final lifted = _hovered && interactive;

    return Semantics(
      button: interactive,
      label: widget.semanticLabel,
      child: Pressable(
        enabled: interactive,
        scale: 0.98,
        child: AnimatedContainer(
        duration: context.motion(AppDurations.color),
        decoration: BoxDecoration(
          borderRadius: AppRadii.cardAll,
          boxShadow: lifted ? colors.shadowMd : const [],
        ),
        child: Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.cardAll,
            side: BorderSide(color: lifted ? colors.borderStrong : colors.border),
          ),
          child: InkWell(
            onTap: widget.onTap,
            onHover: (h) => setState(() => _hovered = h),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.only(top: widget.topBorderWidth),
                  child: Padding(padding: widget.padding, child: widget.child),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: widget.topBorderWidth,
                  child: ColoredBox(color: widget.accent ?? colors.primary),
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

/// A status line with a dot that pulses a few times when it appears
/// (then rests — motion with a meaning, not a loop).
///
/// ```dart
/// StatusLine('Store online · 38 ms', color: colors.success)
/// StatusLine('Out for delivery', color: colors.warning)
/// ```
class StatusLine extends StatelessWidget {
  const StatusLine(this.label, {super.key, this.color, this.pulse = true, this.textColor});

  final String label;
  final Color? color;
  final bool pulse;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = color ?? colors.success;
    return Semantics(
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(key: ValueKey(ink), color: ink, pulse: pulse && !context.reduceMotion),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.data(context, color: textColor ?? colors.muted, size: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({super.key, required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    // three rings, then rest
    if (widget.pulse) _controller.repeat(count: 3);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 12,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Curves.easeOut.transform(_controller.value);
          final ringing = _controller.isAnimating;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (ringing)
                Container(
                  width: 6 + 6 * t,
                  height: 6 + 6 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color.withValues(alpha: 0.6 * (1 - t))),
                  ),
                ),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ],
          );
        },
      ),
    );
  }
}
