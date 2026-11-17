import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product.dart';
import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/wishlist_items_provider.dart';
import '../providers/wishlist_provider.dart';

/// Saved products: grid with "Move to cart" and remove (with undo).
class WishlistScreen extends ConsumerWidget {
  const WishlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(wishlistItemsProvider);
    final ids = ref.watch(wishlistIdsProvider);
    final items = async.value?.where((p) => ids.contains(p.id)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(items == null || items.isEmpty ? 'Wishlist' : 'Wishlist (${items.length})'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(wishlistItemsProvider);
          try {
            await ref.read(wishlistItemsProvider.future);
          } catch (_) {}
        },
        child: switch (async) {
          AsyncValue(:final value?) when items!.isEmpty => _Scroll(
            child: EmptyState(
              icon: Icons.favorite_border_rounded,
              title: value.isEmpty ? 'Nothing saved yet' : 'Your wishlist is empty',
              message: 'Tap the heart on any product to keep it here for later.',
              actionLabel: 'Discover products',
              onAction: () => context.go(Routes.home),
            ),
          ),
          AsyncValue(hasValue: true) => _Grid(items: items!),
          AsyncValue(:final error?) => _Scroll(
            child: ErrorState(error: error, onRetry: () => ref.invalidate(wishlistItemsProvider)),
          ),
          _ => const ProductGrid.loading(count: 6),
        },
      ),
    );
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: c.maxHeight, child: child),
    ),
  );
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items});

  final List<ProductSummary> items;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverResponsiveCenter(
          verticalPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          sliver: SliverLayoutBuilder(
            builder: (context, c) {
              final width = c.crossAxisExtent;
              final columns = ProductGrid.columnsFor(width);
              final tile = (width - ProductGrid.crossSpacing * (columns - 1)) / columns;
              final buttonHeight = 44 + AppSpacing.xs;
              return SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: ProductGrid.crossSpacing,
                  mainAxisSpacing: ProductGrid.mainSpacing,
                  mainAxisExtent: ProductCard.compactHeight(context, tile) + buttonHeight,
                ),
                itemCount: items.length,
                itemBuilder: (context, i) => _WishlistTile(product: items[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WishlistTile extends ConsumerStatefulWidget {
  const _WishlistTile({required this.product});

  final ProductSummary product;

  @override
  ConsumerState<_WishlistTile> createState() => _WishlistTileState();
}

class _WishlistTileState extends ConsumerState<_WishlistTile> {
  bool _moving = false;

  Future<void> _moveToCart() async {
    final p = widget.product;
    setState(() => _moving = true);
    try {
      final res = await ref.read(wishlistActionsProvider).moveToCart(p.id);
      if (!mounted) return;
      AppSnack.success(
        context,
        res.message ?? 'Moved to cart',
        actionLabel: 'View cart',
        onAction: () => context.go(Routes.cart),
      );
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _moving = false);
    }
  }

  Future<void> _remove() async {
    final p = widget.product;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(wishlistIdsProvider.notifier).toggle(p.id);
      if (!mounted) return;
      AppSnack.info(
        context,
        'Removed ${p.title.length > 28 ? '${p.title.substring(0, 28)}…' : p.title}',
        actionLabel: 'Undo',
        onAction: () async {
          try {
            await ref.read(wishlistIdsProvider.notifier).toggle(p.id);
          } on ApiException catch (e) {
            messenger.showSnackBar(SnackBar(content: Text(e.message)));
          }
        },
      );
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: ProductCard(product: p, showWishlist: false, hero: true)),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 44,
          child: Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: p.inStock ? 'Move to cart' : 'Out of stock',
                  size: AppButtonSize.small,
                  loading: _moving,
                  semanticLabel: 'Move ${p.title} to cart, ${Formatters.price(p.price)}',
                  onPressed: p.inStock ? _moveToCart : null,
                ),
              ),
              IconButton(
                tooltip: 'Remove from wishlist',
                onPressed: _remove,
                icon: Icon(Icons.delete_outline_rounded, color: colors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
