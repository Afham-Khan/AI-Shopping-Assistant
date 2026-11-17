import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../discover/presentation/shop_actions.dart';
import 'scroll_story.dart';

/// Flash deals as a horizontal rail whose cut-outs drift slightly against
/// the scroll (paint-only parallax, see [ParallaxImage]).
class ParallaxDealsRail extends StatelessWidget {
  const ParallaxDealsRail({super.key, required this.products});

  final List<ProductSummary> products;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return SizedBox(
      height: 236 + 34 * (scale - 1),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding, vertical: AppSpacing.xxs),
        itemCount: products.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) => _DealTile(product: products[i]),
      ),
    );
  }
}

class _DealTile extends ConsumerWidget {
  const _DealTile({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final t = context.textTheme;
    return SizedBox(
      width: 156,
      child: Pressable(
        child: Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.cardAll,
            side: BorderSide(color: context.isDark ? colors.border : colors.border.withValues(alpha: 0.6)),
          ),
          child: InkWell(
            onTap: () => openProduct(context, product),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: ClipRRect(
                      borderRadius: AppRadii.inputAll,
                      child: Stack(
                        children: [
                          Positioned.fill(child: ColoredBox(color: colors.imageWell)),
                          Positioned.fill(
                            child: ParallaxImage(
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: AppNetworkImage(
                                  product.thumbnail,
                                  fit: BoxFit.contain,
                                  backgroundColor: Colors.transparent,
                                  semanticLabel: product.title,
                                ),
                              ),
                            ),
                          ),
                          if (product.effectiveDiscount >= 1)
                            Positioned(
                              left: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(color: colors.sale, borderRadius: AppRadii.pillAll),
                                child: Text(
                                  Formatters.discount(product.effectiveDiscount),
                                  style: t.labelSmall!.copyWith(color: colors.onSale, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: IconButton(
                              tooltip: 'Add to cart',
                              onPressed: () => quickAddToCart(context, ref, product, source: 'flash_deals'),
                              icon: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                                child: Icon(Icons.add_rounded, size: 20, color: colors.onPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.sm, 2, AppSpacing.sm, AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(product.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelLarge),
                      const SizedBox(height: 2),
                      PriceText(product.price, compareAt: product.compareAtPrice, size: PriceSize.small, singleLine: true),
                    ],
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
