import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_preview_cache.dart';
import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../ai/presentation/widgets/bought_together_rail.dart';
import '../../ai/presentation/widgets/review_summary_card.dart';
import '../../ai/presentation/widgets/similar_products_rail.dart';
import '../../auth/providers/require_auth.dart';
import '../../cart/providers/cart_controller.dart';
import '../../cart/providers/cart_provider.dart';
import '../../compare_tray/compare_tray_bar.dart';
import '../../compare_tray/compare_tray_provider.dart';
import '../../wishlist/providers/wishlist_provider.dart';
import '../data/models/product_detail.dart';
import '../providers/product_providers.dart';
import 'widgets/product_gallery.dart';
import 'widgets/review_widgets.dart';

/// Product page. Paints instantly from [ProductPreviewCache] (hero image,
/// title, price) while the full detail loads. Phones get a sticky buy bar;
/// from 900 px the purchase panel is a sticky right column.
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({super.key, required this.idOrSlug});

  final String idOrSlug;

  @override
  ConsumerState<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  late final ProductSummary? _preview = ProductPreviewCache.lookup(widget.idOrSlug);
  int _quantity = 1;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productDetailProvider(widget.idOrSlug));
    final detail = async.value;
    final summary = detail?.summary ?? _preview;
    final twoColumn = context.screenWidth >= 900;

    if (summary == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.hasError
            ? ErrorState(
                error: async.error,
                message: ApiException.from(async.error!).isNotFound ? 'This product is no longer available.' : null,
                onRetry: () => ref.invalidate(productDetailProvider(widget.idOrSlug)),
              )
            : const _DetailSkeleton(),
      );
    }

    final purchase = _PurchaseControls(
      product: summary,
      quantity: _quantity,
      onQuantity: (q) => setState(() => _quantity = q),
      enabled: detail != null,
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          _ShareButton(product: summary),
          _WishlistAction(productId: summary.id),
          const _CartAction(),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CompareTrayBar(),
          if (!twoColumn) _StickyBuyBar(child: purchase),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(productDetailProvider(widget.idOrSlug));
          try {
            await ref.read(productDetailProvider(widget.idOrSlug).future);
          } catch (_) {}
        },
        child: twoColumn
            ? _TwoColumn(summary: summary, detail: detail, error: async.error, purchase: purchase, onRetry: _retry)
            : _OneColumn(summary: summary, detail: detail, error: async.error, onRetry: _retry),
      ),
    );
  }

  void _retry() => ref.invalidate(productDetailProvider(widget.idOrSlug));
}

// ---------------------------------------------------------------------------
// layouts

class _OneColumn extends StatelessWidget {
  const _OneColumn({required this.summary, required this.detail, required this.error, required this.onRetry});

  final ProductSummary summary;
  final ProductDetail? detail;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(context.pagePadding, 0, context.pagePadding, AppSpacing.xxl),
      children: [
        ResponsiveCenter(
          maxWidth: 640,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProductGallery(
                productId: summary.id,
                images: detail?.gallery ?? const [],
                thumbnail: summary.thumbnail,
                title: summary.title,
                dimmed: !summary.inStock,
              ),
              const SizedBox(height: AppSpacing.lg),
              _Headline(summary: summary, detail: detail),
              const SizedBox(height: AppSpacing.lg),
              _AiAndCompareRow(product: summary),
            ],
          ),
        ),
        ..._DetailSections.build(context, summary: summary, detail: detail, error: error, onRetry: onRetry),
      ],
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({
    required this.summary,
    required this.detail,
    required this.error,
    required this.purchase,
    required this.onRetry,
  });

  final ProductSummary summary;
  final ProductDetail? detail;
  final Object? error;
  final Widget purchase;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ResponsiveCenter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              children: [
                ProductGallery(
                  productId: summary.id,
                  images: detail?.gallery ?? const [],
                  thumbnail: summary.thumbnail,
                  title: summary.title,
                  dimmed: !summary.inStock,
                ),
                ..._DetailSections.build(context, summary: summary, detail: detail, error: error, onRetry: onRetry),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xxl),
          // sticky purchase panel
          SizedBox(
            width: context.screenWidth >= 1200 ? 400 : 360,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadii.sheetAll,
                  border: Border.all(color: colors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Headline(summary: summary, detail: detail),
                    const SizedBox(height: AppSpacing.lg),
                    purchase,
                    const SizedBox(height: AppSpacing.md),
                    _AiAndCompareRow(product: summary),
                    if (detail != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const Divider(),
                      const SizedBox(height: AppSpacing.md),
                      _ServiceInfo(detail: detail!, vertical: true),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything below the fold (shared by both layouts).
abstract final class _DetailSections {
  static List<Widget> build(
    BuildContext context, {
    required ProductSummary summary,
    required ProductDetail? detail,
    required Object? error,
    required VoidCallback onRetry,
  }) {
    final twoColumn = context.screenWidth >= 900;
    if (detail == null) {
      if (error != null) {
        return [
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl),
            child: ErrorState(error: error, compact: true, onRetry: onRetry),
          ),
        ];
      }
      return const [
        SizedBox(height: AppSpacing.xl),
        SkeletonText(lines: 4),
        SizedBox(height: AppSpacing.xl),
        SkeletonText(lines: 6),
      ];
    }

    Widget section(String title, Widget child, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Semantics(header: true, child: Text(title, style: context.textTheme.titleLarge))),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );

    return [
      if (!twoColumn) ...[const SizedBox(height: AppSpacing.xl), _ServiceInfo(detail: detail)],
      if (detail.highlights.isNotEmpty) section('Highlights', _Highlights(items: detail.highlights)),
      if (detail.description != null) section('About this item', _ExpandableText(detail.description!)),
      if (detail.specs.isNotEmpty) section('Specifications', _SpecsTable(specs: detail.specs)),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxl),
        child: ReviewSummaryCard(productId: detail.id),
      ),
      section(
        'Ratings & reviews',
        _ReviewsBlock(detail: detail),
        trailing: Consumer(
          builder: (context, ref, _) => TextButton.icon(
            onPressed: () async {
              if (!requireAuth(context, ref, message: 'Sign in to write a review')) return;
              await showWriteReviewSheet(context, productId: detail.id, productTitle: detail.summary.title);
            },
            style: TextButton.styleFrom(foregroundColor: context.colors.secondary),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Write a review'),
          ),
        ),
      ),
      Padding(padding: const EdgeInsets.only(top: AppSpacing.xxl), child: BoughtTogetherRail(productId: detail.id, padding: 0)),
      Padding(padding: const EdgeInsets.only(top: AppSpacing.xl), child: SimilarProductsRail(productId: detail.id, padding: 0)),
    ];
  }
}

// ---------------------------------------------------------------------------
// headline & purchase

class _Headline extends StatelessWidget {
  const _Headline({required this.summary, required this.detail});

  final ProductSummary summary;
  final ProductDetail? detail;

  @override
  Widget build(BuildContext context) {
    final p = summary;
    final colors = context.colors;
    final t = context.textTheme;
    final eyebrow = [?p.brand, ?p.category?.name].join(' · ');
    final savings = p.hasDiscount ? p.compareAtPrice! - p.price : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow.isNotEmpty)
          InkWell(
            onTap: p.category == null
                ? null
                : () => context.push(Routes.productList(category: p.category!.slug, title: p.category!.name)),
            child: Text(eyebrow, style: t.labelLarge!.copyWith(color: colors.muted)),
          ),
        const SizedBox(height: AppSpacing.xxs),
        Semantics(header: true, child: Text(p.title, style: t.headlineSmall)),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              onTap: () => context.push(Routes.reviewsOf(p.id)),
              borderRadius: AppRadii.inputAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: RatingStars(p.rating, count: p.ratingCount, size: 15),
              ),
            ),
            if (detail != null && detail!.soldCount > 0)
              Text('${Formatters.compact(detail!.soldCount)} sold', style: t.bodySmall),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        PriceText(p.price, compareAt: p.compareAtPrice, size: PriceSize.large, showDiscount: true),
        if (savings >= 1) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'You save ${Formatters.price(savings)}',
            style: t.labelLarge!.copyWith(color: colors.success),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        _StockLine(product: p),
      ],
    );
  }
}

class _StockLine extends StatelessWidget {
  const _StockLine({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (icon, color, text) = !product.inStock
        ? (Icons.remove_shopping_cart_outlined, colors.error, 'Out of stock')
        : product.isLowStock
        ? (Icons.local_fire_department_outlined, colors.warning, 'Only ${product.stock} left — order soon')
        : (Icons.check_circle_outline_rounded, colors.success, 'In stock');
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: Text(text, style: context.textTheme.labelLarge!.copyWith(color: color))),
      ],
    );
  }
}

/// Quantity + Add to cart + Buy now. Used in the sticky bar and the side panel.
class _PurchaseControls extends ConsumerStatefulWidget {
  const _PurchaseControls({
    required this.product,
    required this.quantity,
    required this.onQuantity,
    required this.enabled,
  });

  final ProductSummary product;
  final int quantity;
  final ValueChanged<int> onQuantity;
  final bool enabled;

  @override
  ConsumerState<_PurchaseControls> createState() => _PurchaseControlsState();
}

class _PurchaseControlsState extends ConsumerState<_PurchaseControls> {
  bool _adding = false;
  bool _buying = false;
  bool _added = false;

  int get _max {
    final stock = widget.product.stock;
    if (stock <= 0) return 1;
    return stock < 10 ? stock : 10;
  }

  Future<bool> _add({required bool buyNow}) async {
    if (!requireAuth(context, ref, message: 'Sign in to add items to your cart')) return false;
    setState(() => buyNow ? _buying = true : _adding = true);
    try {
      final res = await ref
          .read(cartProvider.notifier)
          .add(widget.product.id, quantity: widget.quantity, source: 'product_detail');
      if (!mounted) return false;
      HapticFeedback.lightImpact();
      if (!buyNow) {
        setState(() => _added = true);
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _added = false);
        });
        AppSnack.success(
          context,
          res.message ?? 'Added to cart',
          actionLabel: 'View cart',
          onAction: () => context.go(Routes.cart),
        );
      } else if (res.message != null) {
        AppSnack.info(context, res.message!);
      }
      return true;
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
      return false;
    } finally {
      if (mounted) setState(() => _adding = _buying = false);
    }
  }

  Future<void> _buyNow() async {
    if (await _add(buyNow: true) && mounted) context.push(Routes.checkout);
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final canBuy = widget.enabled && p.inStock;

    if (!p.inStock) {
      return AppButton.secondary(label: 'Out of stock', expand: true, onPressed: null);
    }

    final addButton = AnimatedSwitcher(
      duration: context.motion(AppDurations.normal),
      transitionBuilder: (child, anim) => ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(anim), child: FadeTransition(opacity: anim, child: child)),
      child: _added
          ? AppButton.secondary(
              key: const ValueKey('added'),
              label: 'Added',
              icon: Icons.check_rounded,
              expand: true,
              onPressed: () => context.go(Routes.cart),
              semanticLabel: 'Added to cart. Open cart',
            )
          : AppButton.secondary(
              key: const ValueKey('add'),
              label: 'Add to cart',
              icon: Icons.add_shopping_cart_rounded,
              expand: true,
              loading: _adding,
              onPressed: canBuy && !_buying ? () => _add(buyNow: false) : null,
            ),
    );

    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < 360 || MediaQuery.textScalerOf(context).scale(1) > 1.4;
        final stepper = QuantityStepper(
          value: widget.quantity.clamp(1, _max),
          max: _max,
          onChanged: canBuy ? widget.onQuantity : null,
        );
        final buy = AppButton(
          label: 'Buy now',
          expand: true,
          loading: _buying,
          onPressed: canBuy && !_adding ? _buyNow : null,
        );
        if (stacked) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  stepper,
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: addButton),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              buy,
            ],
          );
        }
        return Row(
          children: [
            stepper,
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: addButton),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: buy),
          ],
        );
      },
    );
  }
}

class _StickyBuyBar extends StatelessWidget {
  const _StickyBuyBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.sm, context.pagePadding, AppSpacing.sm),
          child: child,
        ),
      ),
    );
  }
}

class _AiAndCompareRow extends ConsumerWidget {
  const _AiAndCompareRow({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inTray = ref.watch(compareTrayProvider.select((l) => l.any((p) => p.id == product.id)));
    final colors = context.colors;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        ActionChip(
          avatar: Icon(Icons.auto_awesome_outlined, size: 18, color: colors.ai),
          label: const Text('Ask about this product'),
          onPressed: () => context.push(Routes.productAskOf(product.id)),
        ),
        FilterChip(
          selected: inTray,
          avatar: Icon(
            inTray ? Icons.check_rounded : Icons.compare_arrows_rounded,
            size: 18,
            color: inTray ? colors.onPrimary : colors.muted,
          ),
          label: Text(inTray ? 'In compare' : 'Compare'),
          onSelected: (_) {
            final result = ref.read(compareTrayProvider.notifier).toggle(product);
            if (result == CompareToggleResult.full) {
              AppSnack.info(context, 'You can compare up to ${CompareTrayController.maxItems} products');
            }
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// info sections

class _ServiceInfo extends StatelessWidget {
  const _ServiceInfo({required this.detail, this.vertical = false});

  final ProductDetail detail;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.local_shipping_outlined, 'Delivery', detail.shippingInfo ?? 'Free over Rs 5,000'),
      (Icons.assignment_return_outlined, 'Returns', detail.returnPolicy ?? 'Easy returns'),
      (Icons.verified_user_outlined, 'Warranty', detail.warranty ?? 'Seller warranty'),
    ];
    final tiles = [for (final i in items) _InfoTile(icon: i.$1, title: i.$2, value: i.$3)];
    if (vertical) {
      return Column(
        children: [
          for (final tile in tiles) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: tile),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < 520) {
          return Column(
            children: [
              for (final tile in tiles) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: tile),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: tiles[i]),
            ],
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.title, required this.value});

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
          child: Icon(icon, size: 20, color: colors.text),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleSmall),
              Text(value, style: t.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: [
        for (final h in items)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_rounded, size: 18, color: colors.primary),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(h, style: context.textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText(this.text);

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 280;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: context.motion(AppDurations.normal),
          alignment: Alignment.topLeft,
          child: Text(
            widget.text,
            maxLines: _open || !long ? null : 4,
            overflow: _open || !long ? null : TextOverflow.ellipsis,
            style: context.textTheme.bodyMedium!.copyWith(height: 1.6),
          ),
        ),
        if (long)
          TextButton(
            onPressed: () => setState(() => _open = !_open),
            style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: context.colors.secondary),
            child: Text(_open ? 'Show less' : 'Read more'),
          ),
      ],
    );
  }
}

class _SpecsTable extends StatefulWidget {
  const _SpecsTable({required this.specs});

  final List<MapEntry<String, String>> specs;

  @override
  State<_SpecsTable> createState() => _SpecsTableState();
}

class _SpecsTableState extends State<_SpecsTable> {
  static const _collapsed = 6;
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final rows = _all ? widget.specs : widget.specs.take(_collapsed).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadii.cardAll,
            border: Border.all(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: AnimatedSize(
            duration: context.motion(AppDurations.normal),
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++)
                  Container(
                    color: i.isEven ? colors.surfaceVariant.withValues(alpha: 0.6) : colors.surface,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 2, child: Text(rows[i].key, style: t.bodyMedium!.copyWith(color: colors.muted))),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(flex: 3, child: Text(rows[i].value, style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w500))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (widget.specs.length > _collapsed)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _all = !_all),
              style: TextButton.styleFrom(foregroundColor: colors.secondary),
              icon: Icon(_all ? Icons.expand_less_rounded : Icons.expand_more_rounded),
              label: Text(_all ? 'Show fewer' : 'Show all ${widget.specs.length} specifications'),
            ),
          ),
      ],
    );
  }
}

class _ReviewsBlock extends ConsumerWidget {
  const _ReviewsBlock({required this.detail});

  final ProductDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = detail.summary;
    final top = ref.watch(topReviewsProvider(p.id));
    final count = p.ratingCount;

    if (count == 0) {
      return EmptyState(
        compact: true,
        icon: Icons.rate_review_outlined,
        title: 'No reviews yet',
        message: 'Be the first to share what you think.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RatingBreakdown(average: p.rating, count: count, breakdown: detail.ratingBreakdown),
        const SizedBox(height: AppSpacing.md),
        switch (top) {
          AsyncValue(:final value?) => Column(
            children: [
              for (var i = 0; i < value.items.length; i++) ...[
                if (i > 0) const Divider(),
                ReviewTile(review: value.items[i]),
              ],
            ],
          ),
          AsyncValue(:final error?) => ErrorState(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(topReviewsProvider(p.id)),
          ),
          _ => const SkeletonList(count: 2, circleLeading: true),
        },
        const SizedBox(height: AppSpacing.sm),
        AppButton.secondary(
          label: 'See all ${Formatters.plural(count, 'review')}',
          trailingIcon: Icons.chevron_right_rounded,
          onPressed: () => context.push(Routes.reviewsOf(p.id)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// app bar actions

class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Copy link',
      icon: const Icon(Icons.ios_share_rounded),
      onPressed: () async {
        final path = Routes.product(product.slug.isEmpty ? product.id : product.slug);
        // on web the page URL is shareable; elsewhere share a readable line
        final text = kIsWeb
            ? '${Uri.base.origin}$path'
            : '${product.title} — ${Formatters.price(product.price)} on ${AppConfig.appName}';
        await Clipboard.setData(ClipboardData(text: text));
        if (context.mounted) AppSnack.success(context, kIsWeb ? 'Link copied' : 'Copied to clipboard');
      },
    );
  }
}

class _WishlistAction extends ConsumerWidget {
  const _WishlistAction({required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(wishlistIdsProvider.select((ids) => ids.contains(productId)));
    final colors = context.colors;
    return IconButton(
      tooltip: saved ? 'Remove from wishlist' : 'Save to wishlist',
      onPressed: () async {
        if (!requireAuth(context, ref, message: 'Sign in to save items to your wishlist')) return;
        HapticFeedback.selectionClick();
        try {
          final now = await ref.read(wishlistIdsProvider.notifier).toggle(productId);
          if (context.mounted) AppSnack.info(context, now ? 'Saved to wishlist' : 'Removed from wishlist');
        } on ApiException catch (e) {
          if (context.mounted) AppSnack.error(context, e);
        }
      },
      icon: AnimatedSwitcher(
        duration: context.motion(AppDurations.fast),
        transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
        child: Icon(
          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          key: ValueKey(saved),
          color: saved ? colors.sale : null,
        ),
      ),
    );
  }
}

class _CartAction extends ConsumerWidget {
  const _CartAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(cartCountProvider);
    return IconButton(
      tooltip: count > 0 ? 'Cart, $count items' : 'Cart',
      onPressed: () => context.go(Routes.cart),
      icon: AppBadge(count: count, child: const Icon(Icons.shopping_bag_outlined)),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
      children: const [
        ResponsiveCenter(
          maxWidth: 640,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(aspectRatio: 1, child: Skeleton(borderRadius: AppRadii.sheetAll)),
              SizedBox(height: AppSpacing.lg),
              Skeleton(width: 120, height: 12),
              SizedBox(height: AppSpacing.sm),
              Skeleton(height: 22),
              SizedBox(height: AppSpacing.sm),
              Skeleton(width: 160, height: 14),
              SizedBox(height: AppSpacing.lg),
              Skeleton(width: 140, height: 28),
            ],
          ),
        ),
      ],
    );
  }
}
