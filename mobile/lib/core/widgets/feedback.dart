import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';
import 'app_button.dart';
import 'app_network_image.dart';
import 'app_snack.dart';

/// Press feedback for anything tappable: the child settles to ~0.96 while a
/// pointer is down and springs back on release. Wrap cards and custom
/// buttons with it (AppButton and ProductCard already do).
///
/// ```dart
/// Pressable(child: CategoryTile(...))            // visual only; child owns onTap
/// Pressable(scale: 0.98, child: BigBanner(...))  // large surfaces move less
/// ```
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.scale = 0.96, this.enabled = true});

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && _down && !context.reduceMotion;
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: active ? widget.scale : 1,
        duration: active ? const Duration(milliseconds: 90) : AppDurations.normal,
        curve: AppCurves.standard,
        child: widget.child,
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

enum StatusTone { neutral, success, warning, danger, info, accent }

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
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tone == StatusTone.neutral ? colors.surfaceVariant : ink.withValues(alpha: context.isDark ? 0.14 : 0.09),
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: tone == StatusTone.neutral ? colors.border : ink.withValues(alpha: 0.32)),
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
