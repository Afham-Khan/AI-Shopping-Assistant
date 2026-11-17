import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/ai_models.dart';
import '../ai_actions.dart';
import 'ai_ui.dart';
import 'simple_markdown.dart';

/// A built bundle: items by role (with swap), total vs budget, explanation,
/// savings tips and "Add all to cart". Used by Bundle Builder and chat.
class BundleView extends ConsumerStatefulWidget {
  const BundleView({
    super.key,
    required this.bundle,
    this.animate = true,
    this.compact = false,
    this.source = 'bundle',
    this.adviceShownSeparately = false,
  });

  final BundleResult bundle;
  final bool animate;

  /// The screen shows `budgetAdvice` in its own notice, so the explanation
  /// leaves those sentences out instead of repeating them.
  final bool adviceShownSeparately;

  /// Chat card: tighter spacing, tips collapsed.
  final bool compact;
  final String source;

  @override
  ConsumerState<BundleView> createState() => _BundleViewState();
}

class _BundleViewState extends ConsumerState<BundleView> {
  late BundleResult _bundle = widget.bundle;
  bool _adding = false;

  @override
  void didUpdateWidget(BundleView old) {
    super.didUpdateWidget(old);
    if (old.bundle != widget.bundle) _bundle = widget.bundle;
  }

  Future<void> _swap(int index) async {
    final item = _bundle.items[index];
    final picked = await showAppBottomSheet<ProductSummary>(
      context,
      builder: (_) => _AlternativesSheet(item: item),
    );
    if (picked != null && mounted) setState(() => _bundle = _bundle.swap(index, picked));
  }

  Future<void> _addAll() async {
    setState(() => _adding = true);
    await addAllToCart(context, ref, [for (final i in _bundle.items) i.product], source: widget.source);
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final b = _bundle;
    final over = b.overBudget;
    final ratio = b.budget <= 0 ? 0.0 : (b.total / b.budget);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiHeader(title: b.title, caption: '${Formatters.plural(b.items.length, 'item')} picked to fit your budget'),
        SizedBox(height: widget.compact ? AppSpacing.sm : AppSpacing.md),
        for (var i = 0; i < b.items.length; i++)
          SlideFadeIn(
            key: ValueKey('bundle-$i-${b.items[i].product.id}'),
            enabled: widget.animate,
            delay: Duration(milliseconds: 120 * i),
            offset: const Offset(0, 0.08),
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: _BundleItemRow(
                item: b.items[i],
                onSwap: b.items[i].alternatives.isEmpty ? null : () => _swap(i),
                onOpen: () => openAiProduct(context, ref, b.items[i].product.id, source: widget.source),
              ),
            ),
          ),
        AppSpacing.gapSm,
        // total vs budget
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: over ? colors.error.withValues(alpha: 0.08) : colors.primarySoft,
            borderRadius: AppRadii.cardAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: 4,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: 'Total ', style: t.labelLarge),
                        TextSpan(
                          text: Formatters.price(b.total),
                          style: t.titleMedium!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                        if (b.budget > 0) TextSpan(text: '  of ${Formatters.price(b.budget)}', style: t.bodySmall),
                      ],
                    ),
                  ),
                  if (b.budget > 0)
                    Text(
                      over ? '${Formatters.price(-b.remaining)} over' : '${Formatters.price(b.remaining)} left',
                      style: t.labelLarge!.copyWith(color: over ? colors.error : colors.primary),
                    ),
                ],
              ),
              if (b.budget > 0) ...[
                AppSpacing.gapXs,
                AiConfidenceBar(
                  value: ratio,
                  height: 8,
                  color: over ? colors.error : colors.primary,
                  semanticLabel: 'Budget used',
                ),
              ],
            ],
          ),
        ),
        if ((widget.adviceShownSeparately ? b.explanationBody : b.explanation).isNotEmpty) ...[
          AppSpacing.gapMd,
          SimpleMarkdown(widget.adviceShownSeparately ? b.explanationBody : b.explanation),
        ],
        if (b.skippedRoles.isNotEmpty) ...[
          AppSpacing.gapSm,
          Text('Left out to stay on budget: ${b.skippedRoles.join(', ')}', style: t.bodySmall),
        ],
        if (b.savingsTips.isNotEmpty && !widget.compact) ...[
          AppSpacing.gapMd,
          Text('Savings tips', style: t.labelLarge),
          AppSpacing.gapXs,
          for (final tip in b.savingsTips)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 16, color: colors.warning),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(tip, style: t.bodySmall!.copyWith(color: colors.text))),
                ],
              ),
            ),
        ],
        AppSpacing.gapMd,
        AppButton(
          label: 'Add all ${b.items.length} to cart',
          icon: Icons.add_shopping_cart_rounded,
          expand: true,
          loading: _adding,
          onPressed: b.items.isEmpty ? null : _addAll,
        ),
      ],
    );
  }
}

class _BundleItemRow extends StatelessWidget {
  const _BundleItemRow({required this.item, required this.onOpen, this.onSwap});

  final BundleItem item;
  final VoidCallback onOpen;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final p = item.product;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.border)),
      child: InkWell(
        borderRadius: AppRadii.cardAll,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xs),
          child: Row(
            children: [
              AppNetworkImage(p.thumbnail, width: 56, height: 56, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.role.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall!.copyWith(color: colors.ai, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                    ),
                    Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    PriceText(p.price, size: PriceSize.small, singleLine: true),
                  ],
                ),
              ),
              if (onSwap != null)
                TextButton.icon(
                  onPressed: onSwap,
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: const Text('Swap'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlternativesSheet extends StatelessWidget {
  const _AlternativesSheet({required this.item});

  final BundleItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final current = item.product;
    return BottomSheetScaffold(
      title: 'Swap ${item.role.toLowerCase()}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Currently: ${current.title} · ${Formatters.price(current.price)}', style: t.bodySmall),
          AppSpacing.gapSm,
          for (final alt in item.alternatives)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: ProductCard(
                product: alt,
                variant: ProductCardVariant.wide,
                showWishlist: false,
                onTap: () => Navigator.pop(context, alt),
                trailing: Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: _PriceDelta(delta: alt.price - current.price),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PriceDelta extends StatelessWidget {
  const _PriceDelta({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cheaper = delta < 0;
    final label = delta == 0 ? 'Same' : '${cheaper ? '−' : '+'}${Formatters.priceCompact(delta.abs())}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (cheaper ? colors.success : colors.warning).withValues(alpha: 0.12),
        borderRadius: AppRadii.pillAll,
      ),
      child: Text(
        label,
        style: context.textTheme.labelSmall!.copyWith(
          color: cheaper ? colors.success : colors.warning,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
