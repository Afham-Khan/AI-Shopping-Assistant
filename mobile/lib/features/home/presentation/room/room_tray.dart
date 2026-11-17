import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../discover/presentation/shop_actions.dart';
import '../../../wishlist/providers/wishlist_provider.dart';
import 'room_layout.dart';

/// The tray that slides up under the room when a zone is open: the zone's
/// products in a horizontal row, each with save / add / open.
class RoomTray extends StatelessWidget {
  const RoomTray({
    super.key,
    required this.zone,
    required this.products,
    required this.placedIds,
    required this.onClose,
    required this.onSeeAll,
  });

  final RoomZone zone;
  final List<ProductSummary> products;

  /// Products placed by the current setup (marked "In your setup").
  final Set<int> placedIds;
  final VoidCallback onClose;
  final VoidCallback onSeeAll;

  static double heightOf(BuildContext context) => 236 + MediaQuery.textScalerOf(context).scale(24) - 24;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final hue = colors.departmentAccent(zone.department);
    return SizedBox(
      height: heightOf(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, 0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: hue, shape: BoxShape.circle),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(zone.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                      ),
                      if (zone.data.tagline != null)
                        Text(
                          zone.data.tagline!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall!.copyWith(color: colors.muted),
                        ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: onSeeAll,
                  child: Text('See all', semanticsLabel: 'See all in ${zone.department.titleCase}'),
                ),
                IconButton(
                  tooltip: 'Back to the room',
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Text('Nothing here yet', style: t.bodyMedium!.copyWith(color: colors.muted)),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.md),
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
                    itemBuilder: (_, i) => RoomProductTile(
                      product: products[i],
                      inSetup: placedIds.contains(products[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Compact product tile for the tray: cut-out on the image well with a heart
/// and a one-tap add on top, then title and price.
class RoomProductTile extends ConsumerWidget {
  const RoomProductTile({super.key, required this.product, this.inSetup = false, this.width = 148});

  final ProductSummary product;
  final bool inSetup;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.textTheme;
    final colors = context.colors;
    final saved = ref.watch(wishlistIdsProvider.select((ids) => ids.contains(product.id)));
    return SizedBox(
      width: width,
      child: Pressable(
        child: Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.inputAll,
            side: BorderSide(color: inSetup ? colors.primary : colors.border, width: inSetup ? 1.5 : 1),
          ),
          child: InkWell(
            onTap: () => openProduct(context, product),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AppNetworkImage(
                            product.thumbnail,
                            fit: BoxFit.contain,
                            borderRadius: AppRadii.tagAll,
                            semanticLabel: product.title,
                          ),
                        ),
                        if (inSetup)
                          Positioned(
                            left: 4,
                            top: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadii.pillAll),
                              child: Text('In setup', style: t.labelSmall!.copyWith(color: colors.onPrimary)),
                            ),
                          ),
                        Positioned(
                          right: -4,
                          top: -4,
                          child: _MiniIcon(
                            tooltip: saved ? 'Remove from wishlist' : 'Save to wishlist',
                            icon: saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                            color: saved ? colors.sale : colors.onImageWell.withValues(alpha: 0.7),
                            onTap: () => quickToggleSave(context, ref, product),
                          ),
                        ),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: _MiniIcon(
                            tooltip: 'Add to cart',
                            icon: Icons.add_rounded,
                            color: colors.onPrimary,
                            filled: colors.primary,
                            onTap: () => quickAddToCart(context, ref, product, source: 'room'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(product.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelLarge),
                  PriceText(product.price, size: PriceSize.small, singleLine: true),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({required this.tooltip, required this.icon, required this.color, required this.onTap, this.filled});

  final String tooltip;
  final IconData icon;
  final Color color;
  final Color? filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 44 px hit target around a small visual
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      icon: filled == null
          ? Icon(icon, size: 20, color: color)
          : Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: filled, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: color),
            ),
    );
  }
}
