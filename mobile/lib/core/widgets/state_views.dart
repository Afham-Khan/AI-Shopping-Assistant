import 'package:material_ui/material_ui.dart';

import '../network/api_exception.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';
import 'app_button.dart';
import 'editorial.dart';

/// Empty screen/section: a soft tinted icon circle, a bold title, one
/// muted help line and (optionally) one way forward.
///
/// ```dart
/// EmptyState(
///   icon: Icons.favorite_border,
///   eyebrow: 'Wishlist',
///   title: 'Nothing saved yet',
///   message: 'Tap the heart on anything you like. It will wait here.',
///   actionLabel: 'Browse products',
///   onAction: () => context.go(Routes.explore),
/// )
/// ```
/// Voice: say what happened, then what to do. No exclamation marks, no "Oops".
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.iconWidget,
    this.actionLabel,
    this.onAction,
    this.compact = false,
    this.eyebrow,
    this.detail,
    this.accent,
  });

  final String title;
  final String? message;
  final IconData icon;

  /// Custom illustration instead of [icon] (e.g. `AiSparkleIcon(size: 28)`).
  final Widget? iconWidget;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Smaller paddings for use inside a section rather than a full page.
  final bool compact;

  /// Small uppercase label above the title.
  final String? eyebrow;

  /// Mono technical line under the message (error codes, timestamps).
  final String? detail;

  /// Tint for the icon tile's top edge and icon; defaults to neutral.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final tile = compact ? 48.0 : 60.0;
    final tint = accent;

    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // soft tinted circle: quiet, but clearly a state and not content
              Container(
                width: tile,
                height: tile,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tint == null ? colors.surfaceVariant : tint.withValues(alpha: context.isDark ? 0.14 : 0.10),
                  shape: BoxShape.circle,
                  border: Border.all(color: tint == null ? colors.border : tint.withValues(alpha: 0.28)),
                ),
                child: iconWidget ?? Icon(icon, size: compact ? 22 : 26, color: tint ?? colors.muted),
              ),
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              if (eyebrow != null) ...[
                Eyebrow(eyebrow!, color: accent),
                const SizedBox(height: AppSpacing.xs),
              ],
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: compact ? t.titleSmall!.copyWith(fontWeight: FontWeight.w700) : t.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  message!,
                  style: (compact ? t.bodySmall! : t.bodyMedium!.copyWith(fontSize: 13)).copyWith(color: colors.muted, height: 1.5),
                  textAlign: TextAlign.center,
                ),
              ],
              if (detail != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(detail!, style: AppType.data(context, color: colors.faint, size: 11), textAlign: TextAlign.center),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
                AppButton.secondary(
                  label: actionLabel!,
                  onPressed: onAction,
                  size: compact ? AppButtonSize.small : AppButtonSize.medium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error screen/section with a retry button. Pass the caught error —
/// network problems get a hint about the server address, and the technical
/// code is shown small in mono so it can be read back when asking for help.
///
/// ```dart
/// asyncValue.when(
///   data: ...,
///   loading: ...,
///   error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(productsProvider)),
/// )
/// ```
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, this.error, this.message, this.onRetry, this.compact = false});

  final Object? error;

  /// Overrides the message derived from [error].
  final String? message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final api = error == null ? null : ApiException.from(error!);
    final offline = api?.isNetwork ?? false;
    final status = api?.statusCode;
    final detail = offline
        ? 'NETWORK · NO RESPONSE'
        : [if (status != null) 'HTTP $status', if (api?.code != null) api!.code!.toUpperCase()].join(' · ');

    return EmptyState(
      compact: compact,
      icon: offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      accent: offline ? context.colors.warning : context.colors.error,
      title: offline ? "Can't reach the store" : 'That didn’t load',
      message: message ?? api?.message ?? 'Please try again.',
      detail: detail.isEmpty ? null : detail,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

/// Centered spinner for full-page loading when a skeleton doesn't fit.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}
