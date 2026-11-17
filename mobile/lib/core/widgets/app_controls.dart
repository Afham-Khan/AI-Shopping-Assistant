import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';
import 'app_badge.dart';
import 'feedback.dart';

/// White circular icon button with a soft shadow — the reference's app-bar
/// buttons (back, share, heart, bag) and the controls floating over photos.
///
/// ```dart
/// CircleIconButton(icon: Icons.favorite_border_rounded, tooltip: 'Save', onPressed: f)
/// CircleIconButton(icon: Icons.shopping_bag_outlined, tooltip: 'Cart', badgeCount: 3, onPressed: f)
/// CircleIconButton(icon: Icons.tune_rounded, tooltip: 'Filters', filled: false, onPressed: f) // on white
/// ```
class CircleIconButton extends StatelessWidget {
  const CircleIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 20,
    this.color,
    this.iconColor,
    this.filled = true,
    this.badgeCount = 0,
    this.dot = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Diameter of the visible circle; the tap target is always ≥ 44 px.
  final double size;
  final double iconSize;

  /// Circle fill (defaults to `surface`, i.e. white in light mode).
  final Color? color;
  final Color? iconColor;

  /// Shadowed white circle (true) or a quiet tinted circle for use on white cards.
  final bool filled;

  /// Count badge (e.g. cart) and unread dot.
  final int badgeCount;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null;
    Widget glyph = Icon(icon, size: iconSize, color: iconColor ?? (enabled ? colors.text : colors.faint));
    if (dot) {
      glyph = AppBadge.dot(show: true, child: glyph);
    } else if (badgeCount > 0) {
      glyph = AppBadge(count: badgeCount, child: glyph);
    }

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Pressable(
          enabled: enabled,
          scale: 0.92,
          child: SizedBox.square(
            dimension: size < 44 ? 44 : size,
            child: Center(
              child: Material(
                color: color ?? (filled ? colors.surface : colors.surfaceVariant),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: Ink(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: filled ? colors.shadowSm : null,
                    border: filled ? Border.all(color: colors.border.withValues(alpha: 0.8)) : null,
                  ),
                  child: InkWell(
                    onTap: onPressed,
                    customBorder: const CircleBorder(),
                    child: Center(child: glyph),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White rounded card with the soft resting shadow — the default container
/// for grouped content (settings groups, order summaries, info panels).
///
/// ```dart
/// AppCard(child: Column(children: [...]))
/// AppCard(onTap: open, padding: EdgeInsets.all(12), child: Row(...))
/// AppCard(padding: EdgeInsets.zero, child: Column(children: [ListTile(...), ...])) // list group
/// ```
class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.radius = AppRadii.card,
    this.color,
    this.selected = false,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final Color? color;

  /// Blue outline (selectable cards: address, payment method, plan).
  final bool selected;
  final String? semanticLabel;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final radius = BorderRadius.circular(widget.radius);
    final interactive = widget.onTap != null;
    final card = AnimatedContainer(
      duration: context.motion(AppDurations.color),
      curve: AppCurves.standard,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: _hovered && interactive ? colors.shadowMd : colors.shadowSm,
      ),
      child: Material(
        color: widget.color ?? colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: widget.selected
              ? BorderSide(color: colors.primary, width: 1.5)
              : BorderSide(color: context.isDark ? colors.border : colors.border.withValues(alpha: 0.6)),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onHover: interactive ? (h) => setState(() => _hovered = h) : null,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    return Semantics(
      container: true,
      button: interactive,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: interactive ? Pressable(scale: 0.98, child: card) : card,
    );
  }
}

/// The white pill search bar with a search icon (and an optional trailing
/// action such as a filter or camera button).
///
/// Two modes:
/// - **Button** (pass [onTap], no controller): looks like a field, opens the
///   search screen. Use on Home / Explore headers.
/// - **Field** (pass [controller]): a real text input.
///
/// ```dart
/// AppSearchBar(hint: 'Search products', onTap: () => context.push(Routes.search))
/// AppSearchBar(controller: c, autofocus: true, onChanged: search, onSubmitted: go)
/// AppSearchBar(onTap: open, trailing: CircleIconButton(icon: Icons.tune_rounded, ...))
/// ```
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    this.hint = 'Search products, brands and more',
    this.onTap,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.trailing,
    this.height = 50,
  });

  final String hint;
  final VoidCallback? onTap;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  /// Widget at the right end inside the pill (e.g. a small icon button).
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final isButton = controller == null;

    final content = Row(
      children: [
        const SizedBox(width: AppSpacing.md),
        Icon(Icons.search_rounded, size: 22, color: colors.faint),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: isButton
              ? Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyLarge!.copyWith(color: colors.faint, fontSize: 15))
              : TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: autofocus,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  textInputAction: TextInputAction.search,
                  style: t.bodyLarge!.copyWith(fontSize: 15),
                  decoration: InputDecoration(
                    hintText: hint,
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
        ),
        if (trailing != null) ...[const SizedBox(width: AppSpacing.xs), trailing!, const SizedBox(width: 3)]
        else const SizedBox(width: AppSpacing.md),
      ],
    );

    final bar = Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: colors.border),
        boxShadow: colors.shadowSm,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: isButton
            ? InkWell(onTap: onTap, customBorder: const StadiumBorder(), child: content)
            : content,
      ),
    );

    if (!isButton) return bar;
    return Semantics(button: true, label: hint, excludeSemantics: trailing == null, child: bar);
  }
}
