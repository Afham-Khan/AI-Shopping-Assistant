import 'package:material_ui/material_ui.dart';

import '../network/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/extensions.dart';

/// Floating snackbars with consistent styling.
///
/// ```dart
/// AppSnack.success(context, 'Added to cart');
/// AppSnack.error(context, e);                 // any error → friendly message
/// AppSnack.info(context, 'Removed', actionLabel: 'Undo', onAction: undo);
/// ```
abstract final class AppSnack {
  static void success(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) =>
      _show(context, message, icon: Icons.check_circle_rounded, iconColor: _inverse(context).success,
          actionLabel: actionLabel, onAction: onAction);

  /// [error] may be a String, an [ApiException] or anything thrown.
  static void error(BuildContext context, Object error, {String? actionLabel, VoidCallback? onAction}) {
    final message = error is String ? error : ApiException.from(error).message;
    _show(context, message, icon: Icons.error_rounded, iconColor: _inverse(context).error,
        actionLabel: actionLabel, onAction: onAction);
  }

  static void info(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) =>
      _show(context, message, actionLabel: actionLabel, onAction: onAction);

  // dark theme: a raised surface chip; light theme: an ink chip. either way
  // the bar is dark, so status icons come from the dark palette
  static AppPalette _inverse(BuildContext context) => AppPalette.dark;

  static void _show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? iconColor,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final wide = context.isWide;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          // a full-width toast looks odd on desktop; cap it
          width: wide ? 420 : null,
          duration: Duration(milliseconds: actionLabel == null ? 3000 : 5000),
          content: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: iconColor),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(child: Text(message)),
            ],
          ),
          action: actionLabel == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
        ),
      );
  }
}
