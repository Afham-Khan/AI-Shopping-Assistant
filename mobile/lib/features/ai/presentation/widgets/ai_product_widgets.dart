import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../ai_actions.dart';
import 'ai_ui.dart';

/// Height of the "Why this?" chip row under an AI product card.
double whyChipHeight(BuildContext context) => MediaQuery.textScalerOf(context).scale(20) + 24;

/// Compact product card + "Why this?" chip. Taps log `ai_click` with [source].
class AiProductTile extends ConsumerWidget {
  const AiProductTile({super.key, required this.product, this.source = 'assistant', this.showWhy = true});

  final ProductSummary product;
  final String source;
  final bool showWhy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasWhy = showWhy && product.match != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ProductCard(product: product, onTap: () => openAiProduct(context, ref, product.id, source: source)),
        ),
        if (showWhy)
          SizedBox(
            height: whyChipHeight(context),
            child: hasWhy
                ? Align(alignment: Alignment.centerLeft, child: WhyThisChip(product: product, source: source))
                : null,
          ),
      ],
    );
  }
}

/// "✦ Why this?" — opens the reasons sheet.
class WhyThisChip extends StatelessWidget {
  const WhyThisChip({super.key, required this.product, this.source = 'assistant'});

  final ProductSummary product;
  final String source;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      label: 'Why was ${product.title} recommended?',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showWhyThisSheet(context, product, source: source),
        borderRadius: AppRadii.pillAll,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, size: 14, color: colors.ai),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'Why this?',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.labelMedium!.copyWith(color: colors.ai, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet explaining a recommendation: score bar + reasons.
Future<void> showWhyThisSheet(BuildContext context, ProductSummary product, {String source = 'assistant'}) {
  return showAppBottomSheet<void>(
    context,
    builder: (_) => _WhyThisSheet(product: product, source: source),
  );
}

class _WhyThisSheet extends ConsumerWidget {
  const _WhyThisSheet({required this.product, required this.source});

  final ProductSummary product;
  final String source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.textTheme;
    final colors = context.colors;
    final match = product.match;
    final reasons = match?.reasons ?? const <String>[];
    return BottomSheetScaffold(
      title: 'Why this pick?',
      footer: AppButton(
        label: 'View product',
        expand: true,
        trailingIcon: Icons.arrow_forward_rounded,
        onPressed: () {
          Navigator.pop(context);
          openAiProduct(context, ref, product.id, source: source);
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppNetworkImage(product.thumbnail, width: 64, height: 64, borderRadius: AppRadii.inputAll),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    PriceText(product.price, compareAt: product.compareAtPrice, size: PriceSize.small),
                  ],
                ),
              ),
            ],
          ),
          if (match != null) ...[
            AppSpacing.gapLg,
            Row(
              children: [
                Expanded(child: Text('Match score', style: t.labelLarge)),
                AiText(Formatters.percentFromRatio(match.score), style: t.titleMedium),
              ],
            ),
            AppSpacing.gapXs,
            AiConfidenceBar(value: match.score, height: 8, semanticLabel: 'Match score'),
          ],
          AppSpacing.gapLg,
          Text('What ${AppConfig.appName} AI considered', style: t.labelLarge),
          AppSpacing.gapSm,
          if (reasons.isEmpty)
            Text('Popular with shoppers and highly rated in this category.', style: t.bodyMedium)
          else
            for (var i = 0; i < reasons.length; i++)
              SlideFadeIn(
                delay: Duration(milliseconds: 60 * i),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 1),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: colors.aiSoft, shape: BoxShape.circle),
                        child: Icon(Icons.check_rounded, size: 14, color: colors.ai),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(reasons[i], style: t.bodyMedium)),
                    ],
                  ),
                ),
              ),
          AppSpacing.gapXs,
          Text(
            'Scores blend relevance to your request, ratings, price fit and your activity.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Horizontal rail of [AiProductTile]s with staggered slide-in.
class AiProductRail extends StatelessWidget {
  const AiProductRail({
    super.key,
    required this.products,
    this.source = 'assistant',
    this.showWhy = true,
    this.cardWidth,
    this.padding,
    this.animate = true,
  });

  final List<ProductSummary> products;
  final String source;
  final bool showWhy;
  final double? cardWidth;
  final EdgeInsetsGeometry? padding;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final width = cardWidth ?? (context.isWide ? 184.0 : 156.0);
    final height = ProductCard.compactHeight(context, width) + (showWhy ? whyChipHeight(context) : 0);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding ?? EdgeInsets.symmetric(horizontal: context.pagePadding),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => SizedBox(
          width: width,
          child: SlideFadeIn(
            enabled: animate,
            delay: Duration(milliseconds: 70 * i.clamp(0, 6)),
            offset: const Offset(0.06, 0),
            child: AiProductTile(product: products[i], source: source, showWhy: showWhy),
          ),
        ),
      ),
    );
  }
}

/// Sliver grid of [AiProductTile]s (results pages). Wrap in SliverResponsiveCenter.
class SliverAiProductGrid extends StatelessWidget {
  const SliverAiProductGrid({super.key, required this.products, this.source = 'ai', this.showWhy = true});

  final List<ProductSummary> products;
  final String source;
  final bool showWhy;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = ProductGrid.columnsFor(width);
        final tileWidth = (width - ProductGrid.crossSpacing * (columns - 1)) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: ProductGrid.crossSpacing,
            mainAxisExtent: ProductCard.compactHeight(context, tileWidth) + (showWhy ? whyChipHeight(context) : 0),
          ),
          itemCount: products.length,
          itemBuilder: (context, i) => SlideFadeIn(
            delay: Duration(milliseconds: 40 * (i % 10)),
            child: AiProductTile(product: products[i], source: source, showWhy: showWhy),
          ),
        );
      },
    );
  }
}
