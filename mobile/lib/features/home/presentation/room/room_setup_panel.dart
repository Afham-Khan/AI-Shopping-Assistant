import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/presentation/widgets/budget_advice_notice.dart';
import '../../providers/room_providers.dart';
import 'room_layout.dart';
import 'room_setup_layer.dart';

/// "Your Gaming setup": replaces the room's header while a setup is placed.
/// Total against budget with a bar that fills as the pieces land.
///
/// Only the amount and the bar listen to [flight] (a small subtree in its own
/// [RepaintBoundary]); the rest builds once.
class SetupHeaderBar extends StatelessWidget {
  const SetupHeaderBar({super.key, required this.setup, required this.staging, required this.flight});

  final RoomSetup setup;
  final SetupStaging staging;
  final Animation<double> flight;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final budget = setup.budget <= 0 ? setup.total : setup.budget;
    final pieces = Formatters.plural(setup.items.length, 'piece');
    return Container(
      key: const ValueKey('room-setup-header'),
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.cardAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AiSparkleIcon(size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(setup.heading, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$pieces Zel picked to fit your budget, placed where they belong.',
            style: t.bodySmall!.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: flight,
              builder: (context, _) => _BudgetMeter(
                spent: staging.spentAt(flight.value, setup),
                budget: budget,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetMeter extends StatelessWidget {
  const _BudgetMeter({required this.spent, required this.budget});

  final double spent;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final ratio = budget <= 0 ? 0.0 : spent / budget;
    final over = spent > budget + 0.5;
    final barColor = over ? colors.sale : colors.primary;
    const tabular = [FontFeature.tabularFigures()];
    return Semantics(
      label: '${Formatters.price(spent)} of ${Formatters.price(budget)} budget',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: AppSpacing.xs,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: Formatters.price(spent),
                      style: t.titleSmall!.copyWith(color: barColor, fontFeatures: tabular),
                    ),
                    TextSpan(
                      text: ' of ${Formatters.price(budget)}',
                      style: t.bodySmall!.copyWith(color: colors.muted, fontFeatures: tabular),
                    ),
                  ],
                ),
              ),
              Text(
                over ? 'Over by ${Formatters.price(spent - budget)}' : '${Formatters.price(budget - spent)} left',
                style: t.labelMedium!.copyWith(color: over ? colors.sale : colors.muted, fontFeatures: tabular),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: AppRadii.pillAll,
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(child: ColoredBox(color: colors.surface)),
                  FractionallySizedBox(
                    widthFactor: ratio.clamp(0.0, 1.0),
                    child: ColoredBox(color: barColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the room while a setup is placed: the budget notice when essentials
/// are missing, "How Zel chose these", and Add all / Rebuild / Clear room.
class SetupResultPanel extends StatelessWidget {
  const SetupResultPanel({
    super.key,
    required this.setup,
    required this.staging,
    required this.zones,
    required this.onAddAll,
    required this.onRebuild,
    required this.onClear,
    this.onUseSuggested,
    this.busy = false,
  });

  final RoomSetup setup;
  final SetupStaging staging;
  final List<RoomZone> zones;
  final VoidCallback onAddAll;
  final VoidCallback onRebuild;
  final VoidCallback onClear;
  final ValueChanged<double>? onUseSuggested;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final bundle = setup.bundle;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bundle != null && bundle.budgetAdvice.missesEssentials) ...[
          BudgetAdviceNotice(
            advice: bundle.budgetAdvice,
            budget: bundle.budget,
            busy: busy,
            onUseSuggested: onUseSuggested,
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        HowZelChose(setup: setup, staging: staging, zones: zones),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            AppButton(
              label: 'Add all to cart',
              icon: Icons.shopping_bag_outlined,
              size: AppButtonSize.small,
              onPressed: onAddAll,
            ),
            AppButton.secondary(
              label: 'Rebuild',
              icon: Icons.tune_rounded,
              size: AppButtonSize.small,
              onPressed: busy ? null : onRebuild,
            ),
            AppButton.ghost(
              label: 'Clear room',
              icon: Icons.restart_alt_rounded,
              size: AppButtonSize.small,
              onPressed: onClear,
            ),
          ],
        ),
      ],
    );
  }
}

/// The expandable "How Zel chose these": why each pick, the budget used, what
/// was left out, and the method in one line (a knapsack under the budget).
class HowZelChose extends StatefulWidget {
  const HowZelChose({super.key, required this.setup, required this.staging, required this.zones});

  final RoomSetup setup;
  final SetupStaging staging;
  final List<RoomZone> zones;

  @override
  State<HowZelChose> createState() => _HowZelChoseState();
}

class _HowZelChoseState extends State<HowZelChose> {
  bool _open = false;

  String _place(String? zoneId) {
    if (zoneId == null) return 'on the floor';
    for (final z in widget.zones) {
      if (z.id == zoneId) return z.label.isEmpty ? zoneId : z.label.toLowerCase().startsWith('the ') ? z.label : 'the ${z.label}';
    }
    return zoneId;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final setup = widget.setup;
    final bundle = setup.bundle;
    final budget = setup.budget <= 0 ? setup.total : setup.budget;
    final usedPct = budget <= 0 ? 0 : (setup.total / budget * 100).round();
    final numbers = {for (final p in widget.staging.pieces) p.item.product.id: p.number};
    final body = bundle?.explanationBody ?? '';
    final skipped = bundle?.skippedRoles ?? const <String>[];
    final tips = bundle?.savingsTips ?? const <String>[];

    final details = Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 0, AppSpacing.sm, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (body.isNotEmpty) ...[
            Text(body, style: t.bodySmall),
            const SizedBox(height: AppSpacing.xs),
          ],
          for (final item in setup.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      numbers[item.product.id] == null ? '•' : '${numbers[item.product.id]}.',
                      style: t.labelMedium!.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: item.role, style: const TextStyle(fontWeight: FontWeight.w700)),
                          TextSpan(text: ': ${item.product.title}, ${Formatters.price(item.product.price)}'),
                          if (budget > 0)
                            TextSpan(
                              text: ' (${(item.product.price / budget * 100).round()}% of budget)',
                              style: TextStyle(color: colors.muted),
                            ),
                          if (item.product.rating > 0)
                            TextSpan(
                              text: ', rated ${Formatters.rating(item.product.rating)}',
                              style: TextStyle(color: colors.muted),
                            ),
                          TextSpan(text: '. Placed ${_place(item.zoneId)}.', style: TextStyle(color: colors.muted)),
                        ],
                      ),
                      style: t.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Budget used: ${Formatters.price(setup.total)} of ${Formatters.price(budget)} ($usedPct%).',
            style: t.bodySmall!.copyWith(fontWeight: FontWeight.w600),
          ),
          if (skipped.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Left out to stay within budget: ${skipped.join(', ')}.',
              style: t.bodySmall!.copyWith(color: colors.muted),
            ),
          ],
          for (final tip in tips.take(2)) ...[
            const SizedBox(height: 4),
            Text('Tip: $tip', style: t.bodySmall!.copyWith(color: colors.muted)),
          ],
          const SizedBox(height: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(color: colors.surfaceRaised, borderRadius: AppRadii.inputAll),
            child: Text(
              'How it works: Zel scores every candidate for each role by rating and fit, then solves a '
              'knapsack problem: the best-scoring combination whose total stays within your budget, '
              'one piece per role. The room shows where each piece goes.',
              style: t.bodySmall!.copyWith(color: colors.muted),
            ),
          ),
        ],
      ),
    );

    return Container(
      key: const ValueKey('how-zel-chose'),
      decoration: BoxDecoration(
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: colors.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            child: InkWell(
              borderRadius: AppRadii.cardAll,
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded, size: 18, color: colors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'How Zel chose these',
                        style: t.labelLarge!.copyWith(color: colors.primary),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: context.motion(AppDurations.normal),
                      child: Icon(Icons.expand_more_rounded, color: colors.primary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: context.motion(AppDurations.normal),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _open ? details : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
