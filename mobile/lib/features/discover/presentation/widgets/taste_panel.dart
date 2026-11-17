import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/deck_model.dart';
import '../../data/discover_models.dart';

/// Opacity ramp for the category bars: one accent, decreasing strength.
double _shade(int i) => (1 - i * 0.18).clamp(0.3, 1.0);

/// One-line taste summary above the deck: a stacked bar of category shares
/// that re-flows after every swipe, plus a confidence readout. Tap for detail.
class TasteStrip extends StatelessWidget {
  const TasteStrip({super.key, required this.state, required this.onTap});

  final DeckState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final taste = state.taste;
    final cats = taste.categories.take(4).toList();
    final duration = context.motion(const Duration(milliseconds: 450));
    final pct = (taste.confidence * 100).round();

    return Semantics(
      button: true,
      label: cats.isEmpty
          ? 'Your taste. Swipe a few cards to start.'
          : 'Your taste: ${cats.map((c) => '${c.name} ${(c.share * 100).round()} percent').join(', ')}. $pct percent confident.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.inputAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const AiSparkleIcon(size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      cats.isEmpty ? 'Swipe to teach Zel your taste' : 'Into ${cats.map((c) => c.name).take(2).join(' · ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelLarge,
                    ),
                  ),
                  Text(
                    '$pct% sure',
                    style: t.labelMedium!.copyWith(color: colors.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 18, color: colors.muted),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: AppRadii.pillAll,
                child: SizedBox(
                  height: 8,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final rest = 1 - cats.fold(0.0, (a, b) => a + b.share);
                      return Row(
                        children: [
                          for (var i = 0; i < cats.length; i++)
                            AnimatedContainer(
                              duration: duration,
                              curve: AppCurves.standard,
                              width: (c.maxWidth * cats[i].share - 2).clamp(0.0, c.maxWidth),
                              margin: const EdgeInsets.only(right: 2),
                              color: colors.primary.withValues(alpha: _shade(i)),
                            ),
                          Expanded(
                            child: AnimatedContainer(
                              duration: duration,
                              color: rest > 0.01 || cats.isEmpty ? colors.surfaceRaised : Colors.transparent,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full taste readout (sheet): category shares, price appetite,
/// confidence, the strongest signals and swipe counts.
class TastePanel extends StatelessWidget {
  const TastePanel({super.key, required this.state, this.onShopTaste});

  final DeckState state;
  final VoidCallback? onShopTaste;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final taste = state.taste;
    final duration = context.motion(const Duration(milliseconds: 450));
    final tabular = t.labelMedium!.copyWith(color: colors.muted, fontFeatures: const [FontFeature.tabularFigures()]);

    if (taste.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'No signal yet',
        message: 'Like or bag a card and this page starts to build itself.',
        compact: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _Count(label: 'Liked', value: state.count(SwipeAction.like), color: colors.success),
            _Count(label: 'Bagged', value: state.count(SwipeAction.bag), color: colors.primary),
            _Count(label: 'Passed', value: state.count(SwipeAction.pass), color: colors.sale),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('What you keep', style: t.titleSmall),
        const SizedBox(height: AppSpacing.xs),
        for (var i = 0; i < taste.categories.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 112,
                  child: Text(taste.categories[i].name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: AppRadii.pillAll,
                    child: SizedBox(
                      height: 8,
                      child: LayoutBuilder(
                        builder: (context, c) => Stack(
                          children: [
                            Positioned.fill(child: ColoredBox(color: colors.surfaceRaised)),
                            AnimatedContainer(
                              duration: duration,
                              curve: AppCurves.standard,
                              width: c.maxWidth * taste.categories[i].share,
                              color: colors.primary.withValues(alpha: _shade(i)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(taste.categories[i].share * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: tabular,
                  ),
                ),
              ],
            ),
          ),
        if (!taste.priceAppetite.isEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text('Price appetite', style: t.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          _PriceRange(appetite: taste.priceAppetite),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: Text('Confidence', style: t.titleSmall)),
            Text('${(taste.confidence * 100).round()}%', style: tabular),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (var i = 0; i < 10; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: duration,
                  height: 8,
                  margin: EdgeInsets.only(right: i == 9 ? 0 : 3),
                  decoration: BoxDecoration(
                    color: i < (taste.confidence * 10).round() ? colors.primary : colors.surfaceRaised,
                    borderRadius: AppRadii.pillAll,
                  ),
                ),
              ),
          ],
        ),
        if (taste.topSignals.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Signals', style: t.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in taste.topSignals)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.pillAll),
                  child: Text(s, style: t.labelMedium!.copyWith(color: colors.primary)),
                ),
            ],
          ),
        ],
        if (onShopTaste != null && taste.categories.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          AppButton.secondary(
            label: 'Shop ${taste.categories.first.name.toLowerCase()}',
            trailingIcon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: onShopTaste,
          ),
        ],
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value, required this.color});

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: t.headlineSmall!.copyWith(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
          Text(label, style: t.labelMedium!.copyWith(color: context.colors.muted)),
        ],
      ),
    );
  }
}

/// min ─── avg ─── max on a track, labelled underneath.
class _PriceRange extends StatelessWidget {
  const _PriceRange({required this.appetite});

  final PriceAppetite appetite;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final span = appetite.max - appetite.min;
    final avgAt = span <= 0 ? 0.5 : ((appetite.avg - appetite.min) / span).clamp(0.0, 1.0);
    final style = t.labelMedium!.copyWith(color: colors.muted, fontFeatures: const [FontFeature.tabularFigures()]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (context, c) => Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.pillAll),
                ),
                AnimatedPositioned(
                  duration: context.motion(const Duration(milliseconds: 450)),
                  curve: AppCurves.standard,
                  left: (c.maxWidth - 18) * avgAt,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text(Formatters.priceCompact(appetite.min), style: style),
            Expanded(
              child: Text('avg ${Formatters.priceCompact(appetite.avg)}', textAlign: TextAlign.center, style: style),
            ),
            Text(Formatters.priceCompact(appetite.max), style: style),
          ],
        ),
      ],
    );
  }
}
