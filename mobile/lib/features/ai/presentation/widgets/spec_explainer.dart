import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/shopping_models.dart';
import '../../providers/ai_providers.dart';
import 'ai_ui.dart';

/// Opens "Explain these specs". Pass [preloaded] (e.g. from a chat reply) to
/// skip the request; otherwise the explainer for [productId] is fetched.
Future<void> showSpecExplainerSheet(
  BuildContext context, {
  int productId = 0,
  String? productTitle,
  SpecExplainer? preloaded,
}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _SpecExplainerSheet(productId: productId, productTitle: productTitle, preloaded: preloaded),
  );
}

class _SpecExplainerSheet extends ConsumerWidget {
  const _SpecExplainerSheet({required this.productId, this.productTitle, this.preloaded});

  final int productId;
  final String? productTitle;
  final SpecExplainer? preloaded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Widget body;
    if (preloaded != null) {
      body = SpecExplainerBody(data: preloaded!);
    } else {
      final async = ref.watch(specExplainerProvider(productId));
      body = switch (async) {
        AsyncValue(:final value?) => SpecExplainerBody(data: value),
        AsyncValue(:final error?) => ErrorState(
          error: error,
          compact: true,
          onRetry: () => ref.invalidate(specExplainerProvider(productId)),
        ),
        _ => const _ExplainerSkeleton(),
      };
    }
    final subtitle = productTitle ?? preloaded?.productTitle;
    return BottomSheetScaffold(
      title: 'Explain these specs',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (subtitle != null) ...[
            Text(subtitle, style: context.textTheme.bodySmall!.copyWith(color: context.colors.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: AppSpacing.sm),
          ],
          body,
        ],
      ),
    );
  }
}

/// "Who it's for" plus each spec in plain words with a 1–5 level bar.
class SpecExplainerBody extends StatelessWidget {
  const SpecExplainerBody({super.key, required this.data});

  final SpecExplainer data;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;

    if (data.isEmpty) {
      return const EmptyState(
        compact: true,
        icon: Icons.menu_book_outlined,
        title: 'Nothing to explain yet',
        message: "This product doesn't have a spec sheet Zel can read.",
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data.summary.isNotEmpty || data.whoFor.isNotEmpty)
          AiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AiHeader(title: "Who it's for"),
                if (data.summary.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(data.summary, style: t.bodyMedium!.copyWith(height: 1.5)),
                ],
                if (data.whoFor.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [for (final w in data.whoFor) StatusBadge(w, tone: StatusTone.accent)],
                  ),
                ],
              ],
            ),
          ),
        if (data.specs.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Semantics(header: true, child: Text('Spec by spec', style: t.titleSmall)),
          const SizedBox(height: AppSpacing.xs),
          for (final s in data.specs)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: SpecExplanationTile(spec: s),
            ),
        ],
        if (data.others.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Semantics(header: true, child: Text('Also listed', style: t.titleSmall)),
          const SizedBox(height: AppSpacing.xxs),
          for (final o in data.others) KeyValueRow(label: o.key, value: o.value),
        ],
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Levels compare this spec with similar products in the store.',
          style: t.bodySmall!.copyWith(color: colors.faint),
        ),
      ],
    );
  }
}

/// One spec: name and value, what it means, and the level bar.
class SpecExplanationTile extends StatelessWidget {
  const SpecExplanationTile({super.key, required this.spec, this.compact = false});

  final SpecExplanation spec;

  /// Chat card: no meaning paragraph.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: AppRadii.inputAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 2, child: Text(spec.label, style: t.labelLarge!.copyWith(color: colors.muted))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 3,
                child: Text(spec.value, textAlign: TextAlign.end, style: t.labelLarge!.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (!compact && spec.meaning.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(spec.meaning, style: t.bodyMedium!.copyWith(height: 1.45)),
          ],
          if (spec.isRated) ...[
            const SizedBox(height: AppSpacing.xs),
            SpecLevelBar(level: spec.level, label: spec.label, scale: spec.scale, levelLabel: spec.levelLabel),
          ],
        ],
      ),
    );
  }
}

/// Five segments filled up to [level] (1–5), with what it measures and a
/// word for the level ("Good"). Low levels use the warning tone, the rest the
/// accent.
class SpecLevelBar extends StatelessWidget {
  const SpecLevelBar({super.key, required this.level, required this.label, this.scale, this.levelLabel});

  final int level;
  final String label;
  final String? scale;
  final String? levelLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final filled = level <= 2 ? colors.warning : colors.primary;
    final word = levelLabel ?? specLevelLabel(level);
    return Semantics(
      label: '${scale ?? label}: $word, level $level of 5',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: context.motion(AppDurations.normal),
                    height: 6,
                    margin: EdgeInsets.only(right: i == 5 ? 0 : 4),
                    decoration: BoxDecoration(
                      color: i <= level ? filled : colors.surfaceRaised,
                      borderRadius: AppRadii.pillAll,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(scale ?? '', style: t.labelSmall!.copyWith(color: colors.faint), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Text('$word · $level/5', style: t.labelSmall!.copyWith(color: colors.muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact version for a chat reply: summary, the top specs and a way to see all.
class SpecExplainerCard extends StatelessWidget {
  const SpecExplainerCard({super.key, required this.data});

  final SpecExplainer data;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AiHeader(title: 'Specs, explained', caption: data.productTitle),
          if (data.summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(data.summary, style: t.bodyMedium!.copyWith(height: 1.45)),
          ],
          for (final s in data.highlights)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: SpecExplanationTile(spec: s, compact: true),
            ),
          if (data.specs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton.secondary(
                label: 'See all ${data.specs.length} specs',
                size: AppButtonSize.small,
                trailingIcon: Icons.arrow_forward_rounded,
                onPressed: () => showSpecExplainerSheet(context, preloaded: data),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExplainerSkeleton extends StatelessWidget {
  const _ExplainerSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiThinking(messages: ['Reading the spec sheet…', 'Translating into plain words…'], lines: 2),
        SizedBox(height: AppSpacing.md),
        Skeleton(height: 92, borderRadius: AppRadii.inputAll),
        SizedBox(height: AppSpacing.xs),
        Skeleton(height: 92, borderRadius: AppRadii.inputAll),
        SizedBox(height: AppSpacing.xs),
        Skeleton(height: 92, borderRadius: AppRadii.inputAll),
      ],
    );
  }
}
