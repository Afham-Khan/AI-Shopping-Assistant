import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/ai_models.dart';

/// Inline notice for a bundle whose budget couldn't cover the essentials:
/// the server's honest message plus a one-tap "Use Rs X" retry with the
/// suggested budget. Renders nothing when the essentials were covered.
class BudgetAdviceNotice extends StatelessWidget {
  const BudgetAdviceNotice({
    super.key,
    required this.advice,
    required this.budget,
    this.onUseSuggested,
    this.busy = false,
    this.secondary,
  });

  final BudgetAdvice advice;

  /// The budget the bundle was built with.
  final double budget;

  /// Re-runs the bundle with the suggested budget. Null hides the button.
  final ValueChanged<double>? onUseSuggested;
  final bool busy;

  /// An extra, lower-emphasis action under the main one (e.g. "Keep what fits").
  final Widget? secondary;

  String get _message {
    if (advice.message.isNotEmpty) return advice.message;
    return "Your ${Formatters.price(budget)} budget doesn't cover ${advice.missingRequired.join(', ').toLowerCase()}.";
  }

  @override
  Widget build(BuildContext context) {
    if (!advice.missesEssentials) return const SizedBox.shrink();
    final colors = context.colors;
    final t = context.textTheme;
    final suggested = advice.suggestionAbove(budget);
    return Semantics(
      container: true,
      liveRegion: true,
      child: AppCard(
        key: const ValueKey('budget-advice-notice'),
        color: Color.alphaBlend(colors.warning.withValues(alpha: 0.10), colors.surface),
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, size: 20, color: colors.warning),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Budget is too low for the essentials', style: t.titleSmall),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(_message, style: t.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            if (suggested != null && onUseSuggested != null) ...[
              AppSpacing.gapSm,
              AppButton(
                label: 'Use ${Formatters.price(suggested)}',
                icon: Icons.trending_up_rounded,
                expand: true,
                loading: busy,
                onPressed: () => onUseSuggested!(suggested),
              ),
            ],
            if (secondary != null) ...[AppSpacing.gapXs, secondary!],
          ],
        ),
      ),
    );
  }
}
