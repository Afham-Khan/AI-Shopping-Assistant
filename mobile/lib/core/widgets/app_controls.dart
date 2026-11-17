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

    final base = color ?? (filled ? colors.surface : colors.surfaceVariant);
    // under a mouse: grows a hair, takes a light blue tint and a deeper shadow
    final tinted = Color.alphaBlend(colors.primary.withValues(alpha: 0.10), base);

    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip,
      excludeSemantics: true,
      child: Tooltip(
        message: tooltip,
        child: Pressable.builder(
          enabled: enabled,
          scale: 0.94,
          hover: PressableHover.grow,
          hoverScale: 1.06,
          builder: (context, hovered, pressed) => SizedBox.square(
            dimension: size < 44 ? 44 : size,
            child: Center(
              child: AnimatedContainer(
                duration: context.motion(AppDurations.hover),
                curve: AppCurves.standard,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hovered ? tinted : base,
                  boxShadow: filled ? (hovered ? colors.shadowMd : colors.shadowSm) : null,
                  border: filled
                      ? Border.all(color: (hovered ? colors.borderStrong : colors.border).withValues(alpha: 0.8))
                      : null,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
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
///
/// With [onTap] the card is a tappable surface: under a mouse it lifts 2 px
/// while the shadow deepens (`shadowSm` → `shadowMd`) and the blue hover tint
/// washes in; a press settles it to 0.98. Without [onTap] it is plain.
class AppCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderRadius = BorderRadius.circular(radius);
    final interactive = onTap != null;

    Widget card(bool hovered) => AnimatedContainer(
      duration: context.motion(AppDurations.hover),
      curve: AppCurves.standard,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: hovered ? colors.shadowMd : colors.shadowSm,
      ),
      child: Material(
        color: color ?? colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: selected
              ? BorderSide(color: colors.primary, width: 1.5)
              : BorderSide(color: context.isDark ? colors.border : colors.border.withValues(alpha: 0.6)),
        ),
        // InkWell paints the hover tint (theme hoverColor) and the splash
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      ),
    );

    return Semantics(
      container: true,
      button: interactive,
      selected: selected,
      label: semanticLabel,
      child: interactive
          ? Pressable.builder(scale: 0.98, builder: (context, hovered, _) => card(hovered))
          : card(false),
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

    Widget bar(bool hovered) => AnimatedContainer(
      duration: context.motion(AppDurations.hover),
      curve: AppCurves.standard,
      height: height,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: hovered ? colors.primary.withValues(alpha: 0.4) : colors.border),
        boxShadow: hovered ? colors.shadowMd : colors.shadowSm,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: isButton
            ? InkWell(onTap: onTap, customBorder: const StadiumBorder(), child: content)
            : content,
      ),
    );

    if (!isButton) return bar(false);
    // the button-mode bar answers a mouse with a blue hairline and a deeper
    // shadow (it stays put; it is a long bar, not a card)
    return Semantics(
      button: true,
      label: hint,
      excludeSemantics: trailing == null,
      child: Pressable.builder(
        scale: 0.99,
        hover: PressableHover.none,
        builder: (context, hovered, _) => bar(hovered),
      ),
    );
  }
}
