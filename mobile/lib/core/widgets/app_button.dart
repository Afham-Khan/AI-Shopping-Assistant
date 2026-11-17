import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';

enum AppButtonVariant { primary, secondary, ghost, destructive }

enum AppButtonSize {
  small(40, 13),
  medium(48, 15),
  large(54, 16);

  const AppButtonSize(this.height, this.fontSize);

  final double height;
  final double fontSize;
}

/// The app's button. Disabled when [onPressed] is null or [loading] is true.
///
/// ```dart
/// AppButton(label: 'Sign in', onPressed: submit, loading: busy, expand: true)
/// AppButton.secondary(label: 'Filters', icon: Icons.tune, onPressed: ...)
/// AppButton.ghost(label: 'Skip', onPressed: ...)
/// AppButton.destructive(label: 'Delete', onPressed: ...)
/// ```
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.destructive({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = AppButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.expand = false,
    this.semanticLabel,
  }) : variant = AppButtonVariant.destructive;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;

  /// Stretch to the parent's full width.
  final bool expand;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onPressed != null && !loading;
    // while loading keep the enabled look (no grey flash); taps are absorbed below
    final action = onPressed;
    final VoidCallback? callback = loading
        ? _noop
        : (action == null
              ? null
              : () {
                  // a light tick on commit actions (no-op on web/desktop)
                  if (variant == AppButtonVariant.primary || variant == AppButtonVariant.destructive) {
                    HapticFeedback.selectionClick();
                  }
                  action();
                });

    final base = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(expand ? double.infinity : 64, size.height)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: size == AppButtonSize.small ? AppSpacing.md : AppSpacing.lg),
      ),
      textStyle: WidgetStatePropertyAll(
        context.textTheme.labelLarge!.copyWith(fontSize: size.fontSize),
      ),
    );

    final spinnerColor = switch (variant) {
      AppButtonVariant.primary => colors.onPrimary,
      AppButtonVariant.destructive => colors.onSale,
      _ => colors.text,
    };

    final child = _ButtonContent(
      label: label,
      icon: icon,
      trailingIcon: trailingIcon,
      loading: loading,
      spinnerColor: spinnerColor,
      iconSize: size == AppButtonSize.small ? 16 : 18,
    );

    final button = switch (variant) {
      AppButtonVariant.primary => FilledButton(onPressed: callback, style: base, child: child),
      AppButtonVariant.secondary => OutlinedButton(onPressed: callback, style: base, child: child),
      AppButtonVariant.ghost => TextButton(onPressed: callback, style: base, child: child),
      AppButtonVariant.destructive => FilledButton(
        onPressed: callback,
        style: base.merge(
          FilledButton.styleFrom(backgroundColor: colors.error, foregroundColor: colors.onSale),
        ),
        child: child,
      ),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      // keep the button visible as busy to screen readers
      value: loading ? 'Loading' : null,
      child: AbsorbPointer(absorbing: loading, child: button),
    );
  }

  static void _noop() {}
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.trailingIcon,
    required this.loading,
    required this.spinnerColor,
    required this.iconSize,
  });

  final String label;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final Color spinnerColor;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, size: iconSize), const SizedBox(width: AppSpacing.xs)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
        if (trailingIcon != null) ...[const SizedBox(width: AppSpacing.xs), Icon(trailingIcon, size: iconSize)],
      ],
    );

    // the label stays laid out (invisible) so the button keeps its width while loading
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: loading ? 0 : 1, child: content),
        if (loading)
          SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: spinnerColor),
          ),
      ],
    );
  }
}
