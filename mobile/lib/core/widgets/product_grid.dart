import 'package:material_ui/material_ui.dart';

import '../models/product.dart';
import '../theme/app_spacing.dart';
import '../utils/extensions.dart';
import 'product_card.dart';
import 'skeleton.dart';

/// Responsive product grid: 2 / 3 / 4 / 5 columns by available width.
/// Tiles use hero images (each product appears once in a grid).
///
/// ```dart
/// ProductGrid(products: items)                          // standalone, scrolls
/// ProductGrid.loading()                                 // skeleton
/// CustomScrollView(slivers: [SliverProductGrid(products: items, loadingMore: isFetchingNext)])
/// ```
class ProductGrid extends StatelessWidget {
  const ProductGrid({
    super.key,
    required List<ProductSummary> this.products,
    this.padding,
    this.shrinkWrap = false,
    this.physics,
    this.controller,
    this.loadingMore = false,
  }) : skeletonCount = 0;

  const ProductGrid.loading({super.key, int count = 8, this.padding, this.shrinkWrap = false, this.physics})
    : products = null,
      skeletonCount = count,
      controller = null,
      loadingMore = false;

  final List<ProductSummary>? products;
  final int skeletonCount;
  final EdgeInsetsGeometry? padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final ScrollController? controller;

  /// Appends a row of skeleton tiles (next page loading).
  final bool loadingMore;

  static const double mainSpacing = AppSpacing.lg;
  static const double crossSpacing = AppSpacing.sm;

  /// Column count for a content width.
  static int columnsFor(double width) {
    if (width < 560) return 2;
    if (width < 840) return 3;
    if (width < 1100) return 4;
    return 5;
  }

  /// Grid delegate sized so compact [ProductCard]s never overflow, at any text scale.
  static SliverGridDelegate delegateFor(BuildContext context, double width) {
    final columns = columnsFor(width);
    final tileWidth = (width - crossSpacing * (columns - 1)) / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisSpacing: mainSpacing,
      crossAxisSpacing: crossSpacing,
      mainAxisExtent: ProductCard.compactHeight(context, tileWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedPadding = (padding ?? EdgeInsets.all(context.pagePadding)).resolve(Directionality.of(context));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth - resolvedPadding.horizontal;
        final items = products;
        final extra = items == null ? skeletonCount : (loadingMore ? columnsFor(width) : 0);
        final count = (items?.length ?? 0) + extra;
        return GridView.builder(
          controller: controller,
          padding: resolvedPadding,
          shrinkWrap: shrinkWrap,
          physics: physics,
          gridDelegate: delegateFor(context, width),
          itemCount: count,
          itemBuilder: (context, i) => (items != null && i < items.length)
              ? ProductCard(product: items[i], hero: true)
              : const SkeletonProductCard(),
        );
      },
    );
  }
}

/// Sliver version of [ProductGrid] for CustomScrollView pages.
/// Wrap in [SliverResponsiveCenter] (or a SliverPadding) for gutters.
class SliverProductGrid extends StatelessWidget {
  const SliverProductGrid({super.key, required List<ProductSummary> this.products, this.loadingMore = false})
    : skeletonCount = 0;

  const SliverProductGrid.loading({super.key, int count = 8})
    : products = null,
      skeletonCount = count,
      loadingMore = false;

  final List<ProductSummary>? products;
  final int skeletonCount;
  final bool loadingMore;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final items = products;
        final extra = items == null ? skeletonCount : (loadingMore ? ProductGrid.columnsFor(width) : 0);
        return SliverGrid.builder(
          gridDelegate: ProductGrid.delegateFor(context, width),
          itemCount: (items?.length ?? 0) + extra,
          itemBuilder: (context, i) => (items != null && i < items.length)
              ? ProductCard(product: items[i], hero: true)
              : const SkeletonProductCard(),
        );
      },
    );
  }
}

/// Horizontally scrolling row of compact product cards (home sections, AI rails).
///
/// ```dart
/// ProductRail(products: home.trending)
/// ProductRail.loading()
/// ```
class ProductRail extends StatelessWidget {
  const ProductRail({super.key, required List<ProductSummary> this.products, this.cardWidth, this.padding})
    : skeletonCount = 0;

  const ProductRail.loading({super.key, int count = 4, this.cardWidth, this.padding})
    : products = null,
      skeletonCount = count;

  final List<ProductSummary>? products;
  final int skeletonCount;

  /// Defaults to 160 on phones, 200 on wider screens.
  final double? cardWidth;

  /// Defaults to the page gutter horizontally.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = cardWidth ?? (context.isWide ? 200.0 : 160.0);
    final items = products;
    final count = items?.length ?? skeletonCount;
    return SizedBox(
      height: ProductCard.compactHeight(context, width),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding ?? EdgeInsets.symmetric(horizontal: context.pagePadding),
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: ProductGrid.crossSpacing),
        itemBuilder: (context, i) => SizedBox(
          width: width,
          child: items == null ? const SkeletonProductCard() : ProductCard(product: items[i]),
        ),
      ),
    );
  }
}
