import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/auth/providers/require_auth.dart';
import '../../features/wishlist/providers/wishlist_provider.dart';
import '../models/product.dart';
import '../models/product_preview_cache.dart';
import '../network/api_exception.dart';
import '../router/routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';
import '../utils/formatters.dart';
import 'ai_gradient.dart';
import 'app_network_image.dart';
import 'app_snack.dart';
import 'price_text.dart';
import 'rating_stars.dart';

enum ProductCardVariant {
  /// Vertical tile for grids and rails.
  compact,

  /// Horizontal row for lists (search results, wishlist).
  wide,
}

/// Product tile: a bordered card whose top is a light "studio" image well
/// (wishlist heart, discount tag, AI match badge), then brand eyebrow, 2-line
/// title, rating and price. Hover lifts the border and nudges the photo.
/// Taps open the product page.
///
/// ```dart
/// ProductCard(product: p)                                   // grid tile
/// ProductCard(product: p, variant: ProductCardVariant.wide) // list row
/// ProductCard(product: p, onTap: () => ..., showWishlist: false)
/// ProductCard(product: p, hero: true)  // image flies into the product page
/// ```
/// Use `hero: true` only where a product appears once per screen (grids do;
/// rails don't, since home rails can repeat a product).
/// In grids/rails give it the height from [ProductCard.compactHeight]
/// (ProductGrid / ProductRail already do).
class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.variant = ProductCardVariant.compact,
    this.onTap,
    this.showWishlist = true,
    this.trailing,
    this.hero = false,
  });

  final ProductSummary product;
  final ProductCardVariant variant;

  /// Defaults to opening the product page.
  final VoidCallback? onTap;
  final bool showWishlist;

  /// Extra widget at the end of the wide variant (e.g. a remove button).
  final Widget? trailing;

  /// Wrap the image in a [Hero] tagged `ProductPreviewCache.heroTag(id)`.
  final bool hero;

  // text block height at 1.0 text scale: brand + 2-line title + rating + price + gaps
  static const double _infoTextHeight = 90;
  // card border + paddings + gaps between the text rows
  static const double _infoGaps = 40;

  /// Total tile height for a compact card of [width] at the current text scale.
  static double compactHeight(BuildContext context, double width) =>
      width + _infoGaps + MediaQuery.textScalerOf(context).scale(_infoTextHeight);

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _hovered = false;

  void _open() {
    // lets the product page paint instantly while the details load
    ProductPreviewCache.remember(widget.product);
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      context.push(Routes.product(widget.product.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final label = StringBuffer(p.title);
    if (p.brand != null) label.write(', by ${p.brand}');
    label.write(', ${Formatters.price(p.price)}');
    if (!p.inStock) label.write(', out of stock');

    final compact = widget.variant == ProductCardVariant.compact;

    return Semantics(
      button: true,
      label: label.toString(),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: compact ? _buildCompact(context) : _buildWide(context),
      ),
    );
  }

  Widget _buildCompact(BuildContext context) {
    final colors = context.colors;
    final p = widget.product;
    return AnimatedContainer(
      duration: context.motion(AppDurations.fast),
      decoration: BoxDecoration(
        borderRadius: AppRadii.cardAll,
        boxShadow: _hovered ? colors.shadowMd : const [],
      ),
      child: Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: _hovered ? colors.borderStrong : colors.border),
        ),
        child: InkWell(
          onTap: _open,
          child: Padding(
            // keeps the content inside the 1 px border
            padding: const EdgeInsets.all(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: _ImageTile(
                    product: p,
                    hovered: _hovered,
                    showWishlist: widget.showWishlist,
                    hero: widget.hero,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadii.card - 1)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: _Info(product: p),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final p = widget.product;
    final width = context.isWide ? 128.0 : 104.0;
    return InkWell(
      onTap: _open,
      borderRadius: AppRadii.cardAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: width,
              height: width,
              child: _ImageTile(product: p, hovered: _hovered, showWishlist: false, compactBadges: true),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: _Info(product: p, wide: true)),
            if (widget.showWishlist) _WishlistButton(productId: p.id, floating: false),
            ?widget.trailing,
          ],
        ),
      ),
    );
  }
}

/// The light "studio" well. It is light in both themes on purpose: the
/// catalog photos are cut-outs and many products are black.
class _ImageTile extends StatelessWidget {
  const _ImageTile({
    required this.product,
    required this.hovered,
    required this.showWishlist,
    this.compactBadges = false,
    this.hero = false,
    this.borderRadius = AppRadii.inputAll,
  });

  final ProductSummary product;
  final bool hovered;
  final bool showWishlist;
  final bool compactBadges;
  final bool hero;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final p = product;
    final discount = p.effectiveDiscount;

    return ClipRRect(
      borderRadius: borderRadius,
      child: ColoredBox(
        color: colors.imageWell,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedScale(
              scale: hovered && !context.reduceMotion ? 1.045 : 1,
              duration: AppDurations.slow,
              curve: AppCurves.standard,
              child: Opacity(
                opacity: p.inStock ? 1 : 0.4,
                child: Padding(
                  padding: EdgeInsets.all(compactBadges ? AppSpacing.xs : AppSpacing.md),
                  child: _maybeHero(
                    AppNetworkImage(
                      p.thumbnail,
                      fit: BoxFit.contain,
                      backgroundColor: Colors.transparent,
                      semanticLabel: p.title,
                    ),
                  ),
                ),
              ),
            ),
            if (discount >= 1)
              Positioned(
                top: AppSpacing.xs,
                left: AppSpacing.xs,
                child: _Tag(
                  label: Formatters.discount(discount),
                  color: AppPalette.light.sale,
                  textColor: Colors.white,
                ),
              ),
            if (!p.inStock)
              Positioned(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
                child: _Tag(label: 'Sold out', color: colors.onImageWell, textColor: Colors.white),
              )
            else if (p.match != null && !compactBadges)
              Positioned(
                left: AppSpacing.xs,
                bottom: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AiBadge(label: '${Formatters.percentFromRatio(p.match!.score)} match'),
                ),
              ),
            if (showWishlist) Positioned(top: 0, right: 0, child: _WishlistButton(productId: p.id)),
          ],
        ),
      ),
    );
  }
}

extension on _ImageTile {
  Widget _maybeHero(Widget child) =>
      hero ? Hero(tag: ProductPreviewCache.heroTag(product.id), child: child) : child;
}

class _Info extends StatelessWidget {
  const _Info({required this.product, this.wide = false});

  final ProductSummary product;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final p = product;
    final eyebrow = p.brand ?? p.category?.name ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // keep the line even when empty so tiles in a row align
        Text(
          eyebrow.isEmpty ? ' ' : eyebrow.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.mono(
            TextStyle(fontSize: 10, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.9, color: colors.faint),
          ),
        ),
        const SizedBox(height: 3),
        SizedBox(
          // reserve two lines so prices line up across a grid row
          height: wide ? null : MediaQuery.textScalerOf(context).scale(14 * 1.35 * 2),
          child: Text(
            p.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: t.bodyMedium!.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.35, letterSpacing: -0.1),
          ),
        ),
        const SizedBox(height: 6),
        RatingStars(p.rating, count: p.ratingCount, size: 13),
        const SizedBox(height: 6),
        PriceText(p.price, compareAt: p.compareAtPrice, size: PriceSize.small, singleLine: !wide),
        if (wide && p.isLowStock) ...[
          const SizedBox(height: 6),
          Text(
            'Only ${p.stock} left',
            style: t.labelSmall!.copyWith(color: colors.warning, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, required this.textColor});

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: AppRadii.tagAll),
      child: Text(
        label,
        style: context.textTheme.labelSmall!.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.1,
          fontFeatures: AppType.tabular,
        ),
      ),
    );
  }
}

/// Heart toggle bound to [wishlistIdsProvider]. Guests get a sign-in prompt.
class _WishlistButton extends ConsumerWidget {
  const _WishlistButton({required this.productId, this.floating = true});

  final int productId;

  /// Draws a small white disc behind the icon (over the image well).
  final bool floating;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (!requireAuth(context, ref, message: 'Sign in to save items to your wishlist')) return;
    HapticFeedback.selectionClick();
    try {
      await ref.read(wishlistIdsProvider.notifier).toggle(productId);
    } on ApiException catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final saved = ref.watch(wishlistIdsProvider.select((ids) => ids.contains(productId)));
    // over the (always light) well the heart uses light-theme ink
    final restColor = floating ? colors.onImageWell : colors.muted;
    final savedColor = floating ? AppPalette.light.sale : colors.sale;

    final icon = AnimatedSwitcher(
      duration: context.motion(AppDurations.fast),
      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
      child: Icon(
        saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        key: ValueKey(saved),
        size: floating ? 17 : 20,
        color: saved ? savedColor : restColor,
      ),
    );

    return Semantics(
      toggled: saved,
      child: IconButton(
        onPressed: () => _toggle(context, ref),
        tooltip: saved ? 'Remove from wishlist' : 'Save to wishlist',
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
        icon: floating
            ? Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.onImageWell.withValues(alpha: 0.10)),
                ),
                child: icon,
              )
            : icon,
      ),
    );
  }
}
