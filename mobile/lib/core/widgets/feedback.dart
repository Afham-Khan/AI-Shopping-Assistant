import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';
import 'app_button.dart';
import 'app_network_image.dart';
import 'app_snack.dart';

/// What a mouse pointer resting on a [Pressable] does to it (web / desktop;
/// touch has no hover).
enum PressableHover {
  /// Nothing — rows inside lists and surfaces that already tint themselves.
  none,

  /// Rises 2 px (cards, tiles, quick actions). Pair it with `shadowMd` via
  /// [Pressable.builder] so the shadow deepens as the card lifts.
  lift,

  /// Grows a hair (circular buttons, small chips, logos); see `hoverScale`.
  grow,
}

/// Builds a [Pressable]'s content from its pointer state.
typedef PressableBuilder = Widget Function(BuildContext context, bool hovered, bool pressed);

/// The one place hover and press feedback lives, so every tappable surface
/// behaves the same: under a mouse it **lifts** 2 px (or grows 2 %), under any
/// pointer it settles to 0.97 while pressed and springs back on release.
/// 150–200 ms, `easeOutCubic`, transforms only (no blur, no layers beyond one
/// `RepaintBoundary`). Reduced motion keeps colour changes but drops all
/// movement.
///
/// ```dart
/// Pressable(child: CategoryTile(...))                  // visual only; child owns onTap
/// Pressable(scale: 0.98, child: BigBanner(...))        // large surfaces move less
/// Pressable(hover: PressableHover.none, child: Row())  // list rows: press only
/// Pressable.builder(                                    // deepen the shadow with the lift
///   builder: (context, hovered, pressed) => DecoratedBox(
///     decoration: BoxDecoration(boxShadow: hovered ? colors.shadowMd : colors.shadowSm),
///     child: tile,
///   ),
/// )
/// ```
/// A press that turns into a scroll or drag (the pointer moves more than
/// ~14 px) releases at once, so a card doesn't stay shrunk under a swipe.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required Widget this.child,
    this.scale = 0.97,
    this.enabled = true,
    this.hover = PressableHover.lift,
    this.hoverScale = 1.02,
    this.cursor = MouseCursor.defer,
  }) : builder = null;

  /// Like the default constructor, but [builder] gets `hovered` / `pressed`
  /// so the content can swap shadows, tints or icons with the pointer.
  const Pressable.builder({
    super.key,
    required PressableBuilder this.builder,
    this.scale = 0.97,
    this.enabled = true,
    this.hover = PressableHover.lift,
    this.hoverScale = 1.02,
    this.cursor = MouseCursor.defer,
  }) : child = null;

  final Widget? child;
  final PressableBuilder? builder;

  /// Scale while pressed (0.97; large surfaces use 0.98, small circles ~0.94).
  final double scale;
  final bool enabled;
  final PressableHover hover;

  /// Scale under a mouse for [PressableHover.grow].
  final double hoverScale;

  /// Mouse cursor over the surface; the default leaves it to the child
  /// (an `InkWell` already shows the click cursor).
  final MouseCursor cursor;

  /// How far a hovered [PressableHover.lift] surface rises, in logical px.
  static const double liftDistance = 2;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  static const _hoverTime = AppDurations.hover;
  static const _pressTime = Duration(milliseconds: 90);
  static const _slop = 14.0;

  bool _down = false;
  bool _hovered = false;
  Offset _downAt = Offset.zero;

  void _setDown(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  void _setHovered(bool hovered) {
    if (_hovered != hovered && mounted) setState(() => _hovered = hovered);
  }

  @override
  void didUpdateWidget(Pressable old) {
    super.didUpdateWidget(old);
    // a disabled surface neither lifts nor stays pressed
    if (!widget.enabled && (_down || _hovered)) {
      _down = false;
      _hovered = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = context.reduceMotion;
    final pressed = widget.enabled && _down;
    final hovered = widget.enabled && _hovered;
    final content = widget.builder != null ? widget.builder!(context, hovered, pressed) : widget.child!;

    var scale = 1.0;
    var lift = 0.0;
    if (!reduce) {
      if (pressed) {
        scale = widget.scale;
      } else if (hovered) {
        switch (widget.hover) {
          case PressableHover.lift:
            lift = -Pressable.liftDistance;
          case PressableHover.grow:
            scale = widget.hoverScale;
          case PressableHover.none:
            break;
        }
      }
    }
    final duration = reduce ? Duration.zero : (pressed ? _pressTime : _hoverTime);

    // the mouse region sits OUTSIDE the transforms: a lifted card's resting
    // footprint stays hoverable, so the pointer can't flicker at its lower edge
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Listener(
        onPointerDown: (e) {
          _downAt = e.position;
          _setDown(true);
        },
        onPointerMove: (e) {
          if (_down && (e.position - _downAt).distance > _slop) _setDown(false);
        },
        onPointerUp: (_) => _setDown(false),
        onPointerCancel: (_) => _setDown(false),
        child: AnimatedScale(
          scale: scale,
          duration: duration,
          curve: AppCurves.standard,
          child: AnimatedContainer(
            duration: duration,
            curve: AppCurves.standard,
            transform: Matrix4.translationValues(0, lift, 0),
            // the animated subtree repaints on its own, not with the page
            child: RepaintBoundary(child: content),
          ),
        ),
      ),
    );
  }
}

/// Number that counts up once when it appears (1.2 s ease-out, tabular
/// figures so the width doesn't jitter). For stat rows.
///
/// ```dart
/// CountUp(194, style: t.displaySmall)
/// CountUp(4.6, decimals: 1)
/// ```
class CountUp extends StatelessWidget {
  const CountUp(this.value, {super.key, this.style, this.decimals = 0, this.prefix = '', this.suffix = ''});

  final num value;
  final TextStyle? style;
  final int decimals;
  final String prefix;
  final String suffix;

  String _format(double v) {
    final fixed = v.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final grouped = parts.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return '$prefix${parts.length > 1 ? '$grouped.${parts[1]}' : grouped}$suffix';
  }

  @override
  Widget build(BuildContext context) {
    final base = (style ?? DefaultTextStyle.of(context).style).copyWith(fontFeatures: AppType.tabular);
    final end = value.toDouble();
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: end),
      duration: context.motion(const Duration(milliseconds: 1200)),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text(_format(v), style: base, maxLines: 1, semanticsLabel: _format(end)),
    );
  }
}

/// Success mark that draws itself: a ring, then the check stroke.
/// Use on order-placed / saved / verified moments.
class SuccessCheck extends StatelessWidget {
  const SuccessCheck({super.key, this.size = 64, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? context.colors.success;
    return Semantics(
      label: 'Done',
      image: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: context.motion(const Duration(milliseconds: 700)),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(painter: _CheckPainter(t, ink)),
        ),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = (s * 0.07).clamp(2.0, 5.0);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(Offset(s / 2, s / 2), s / 2 - stroke, Paint()..color = color.withValues(alpha: 0.12));

    // ring over the first 55 %, check over the rest
    final ring = (t / 0.55).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: Offset(s / 2, s / 2), radius: s / 2 - stroke),
      -1.5708,
      6.2832 * ring,
      false,
      paint,
    );

    final check = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
    if (check <= 0) return;
    final path = Path()
      ..moveTo(s * 0.30, s * 0.52)
      ..lineTo(s * 0.44, s * 0.66)
      ..lineTo(s * 0.71, s * 0.37);
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * check), paint);
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t || old.color != color;
}

/// Round avatar: photo when there is one, otherwise initials on a soft
/// accent tint. `AppAvatar(name: user.name, imageUrl: user.avatarUrl)`.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, this.name, this.imageUrl, this.size = 36, this.selected = false});

  final String? name;
  final String? imageUrl;
  final double size;

  /// Accent ring (e.g. the current tab).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasName = name != null && name!.trim().isNotEmpty;
    final Widget inner;
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      inner = AppNetworkImage(imageUrl, width: size, height: size, fit: BoxFit.cover, fallbackIcon: Icons.person_outline_rounded);
    } else if (hasName) {
      inner = Text(
        name!.initials,
        style: context.textTheme.labelMedium!.copyWith(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
          letterSpacing: 0.2,
        ),
      );
    } else {
      inner = Icon(Icons.person_outline_rounded, size: size * 0.52, color: colors.muted);
    }
    return Semantics(
      label: hasName ? name : 'Guest',
      image: true,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: context.motion(AppDurations.normal),
        width: size,
        height: size,
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: hasName ? colors.primarySoft : colors.surfaceVariant,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? colors.primary : colors.border, width: selected ? 1.5 : 1),
        ),
        child: inner,
      ),
    );
  }
}

enum StatusTone {
  neutral,
  success,
  warning,
  danger,
  info,
  accent,

  /// Warm amber "deal" pill (flash deals, limited offers).
  deal,
}

/// Status badge: soft background, strong text, subtle border.
///
/// ```dart
/// StatusBadge('Delivered', tone: StatusTone.success)
/// StatusBadge('Low stock', tone: StatusTone.warning, icon: Icons.bolt_rounded)
/// ```
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.tone = StatusTone.neutral, this.icon});

  final String label;
  final StatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final ink = switch (tone) {
      StatusTone.neutral => colors.muted,
      StatusTone.success => colors.success,
      StatusTone.warning => colors.warning,
      StatusTone.danger => colors.error,
      StatusTone.info => colors.secondary,
      StatusTone.accent => colors.primary,
      StatusTone.deal => colors.dealInk,
    };
    final deal = tone == StatusTone.deal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: deal
            ? colors.dealSoft
            : tone == StatusTone.neutral
            ? colors.surfaceVariant
            : ink.withValues(alpha: context.isDark ? 0.14 : 0.09),
        borderRadius: AppRadii.pillAll,
        border: Border.all(
          color: deal
              ? colors.deal.withValues(alpha: 0.6)
              : tone == StatusTone.neutral
              ? colors.border
              : ink.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: ink), const SizedBox(width: 4)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall!.copyWith(color: ink, fontWeight: FontWeight.w600, letterSpacing: 0.1),
            ),
          ),
        ],
      ),
    );
  }
}

/// A solid amber "deal" pill with navy ink (9.8:1) — flash deals, limited
/// offers, "Deal of the day". Use sparingly: one per surface, next to (not
/// instead of) the red discount tag.
///
/// ```dart
/// DealTag('Flash deal')
/// DealTag('Ends today', icon: Icons.timer_outlined)
/// ```
class DealTag extends StatelessWidget {
  const DealTag(this.label, {super.key, this.icon = Icons.bolt_rounded});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: colors.deal, borderRadius: AppRadii.pillAll),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: colors.onDeal), const SizedBox(width: 3)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelSmall!.copyWith(
                color: colors.onDeal,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.1,
                fontFeatures: AppType.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog with the app's motion: fades in over 150 ms while sliding up 20 px.
Future<T?> showAppDialog<T>(BuildContext context, {required WidgetBuilder builder, bool barrierDismissible = true}) {
  final reduce = context.reduceMotion;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.black.withValues(alpha: context.isDark ? 0.6 : 0.4),
    transitionDuration: reduce ? Duration.zero : const Duration(milliseconds: 150),
    pageBuilder: (context, _, _) => SafeArea(child: Builder(builder: builder)),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(offset: Offset(0, 20 * (1 - curved.value)), child: child),
          child: child,
        ),
      );
    },
  );
}

/// Confirmation dialog. Destructive ones get an error-tinted icon circle and
/// a danger button; the confirm button shows a spinner while [onConfirm]
/// runs and the dialog closes itself when it completes.
///
/// ```dart
/// final removed = await ConfirmDialog.show(
///   context,
///   title: 'Remove this address?',
///   message: 'This action cannot be undone.',
///   confirmLabel: 'Remove',
///   onConfirm: () => repo.delete(id),
/// );
/// ```
class ConfirmDialog extends StatefulWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    this.message = 'This action cannot be undone.',
    this.confirmLabel = 'Delete',
    this.cancelLabel = 'Cancel',
    this.icon,
    this.destructive = true,
    this.onConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final IconData? icon;
  final bool destructive;

  /// Async work to run before closing; errors are shown in a snack and keep
  /// the dialog open.
  final Future<void> Function()? onConfirm;

  /// Returns true when confirmed.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    String message = 'This action cannot be undone.',
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    IconData? icon,
    bool destructive = true,
    Future<void> Function()? onConfirm,
  }) async {
    final result = await showAppDialog<bool>(
      context,
      builder: (_) => ConfirmDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
        destructive: destructive,
        onConfirm: onConfirm,
      ),
    );
    return result ?? false;
  }

  @override
  State<ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<ConfirmDialog> {
  bool _busy = false;

  Future<void> _confirm() async {
    final task = widget.onConfirm;
    if (task == null) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final ink = widget.destructive ? colors.error : colors.primary;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Material(
            color: colors.surface,
            elevation: 12,
            shadowColor: colors.shadow,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(AppRadii.card)),
              side: BorderSide(color: colors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: widget.destructive ? colors.saleSoft : colors.primarySoft,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.icon ?? (widget.destructive ? Icons.delete_outline_rounded : Icons.help_outline_rounded),
                      size: 20,
                      color: ink,
                    ),
                  ),
                  AppSpacing.gapMd,
                  Semantics(header: true, child: Text(widget.title, style: t.titleMedium)),
                  AppSpacing.gapXs,
                  Text(widget.message, style: t.bodyMedium!.copyWith(color: colors.muted)),
                  AppSpacing.gapLg,
                  Row(
                    children: [
                      Expanded(
                        child: AppButton.secondary(
                          label: widget.cancelLabel,
                          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
                          expand: true,
                        ),
                      ),
                      AppSpacing.gapSm,
                      Expanded(
                        child: widget.destructive
                            ? AppButton.destructive(label: widget.confirmLabel, onPressed: _confirm, loading: _busy, expand: true)
                            : AppButton(label: widget.confirmLabel, onPressed: _confirm, loading: _busy, expand: true),
                      ),
                    ],
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

/// Copies [text] and confirms with a snack: `copyToClipboard(context, order.number, label: 'Order number')`.
Future<void> copyToClipboard(BuildContext context, String text, {String label = 'Text'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  HapticFeedback.selectionClick();
  if (context.mounted) AppSnack.success(context, '$label copied');
}

/// Validates a form the app's way: returns true when valid; otherwise
/// scrolls to and focuses the first invalid field. Pair with a
/// `FormErrorBanner(message: kFixFieldsMessage)`.
///
/// ```dart
/// if (!validateForm(_formKey)) { setState(() => _banner = kFixFieldsMessage); return; }
/// ```
bool validateForm(GlobalKey<FormState> key) {
  final invalid = key.currentState?.validateGranularly() ?? const <FormFieldState<Object?>>{};
  if (invalid.isEmpty) return true;
  final first = invalid.first;
  Scrollable.ensureVisible(first.context, alignment: 0.2, duration: AppDurations.normal, curve: AppCurves.standard);
  var focused = false;
  void visit(Element element) {
    if (focused) return;
    final widget = element.widget;
    if (widget is EditableText) {
      widget.focusNode.requestFocus();
      focused = true;
      return;
    }
    element.visitChildren(visit);
  }

  (first.context as Element).visitChildren(visit);
  return false;
}

const kFixFieldsMessage = 'Please fix the highlighted fields.';
