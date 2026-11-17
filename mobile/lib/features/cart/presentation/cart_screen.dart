import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product_preview_cache.dart';
import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../ai/presentation/widgets/cart_insights_card.dart';
import '../data/models/cart.dart';
import '../providers/cart_controller.dart';
import 'widgets/cart_summary.dart';

/// The cart: lines with optimistic quantity edits, remove with undo, coupons,
/// free-delivery progress, AI insights and an order summary with checkout.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(cartProvider);
    final cart = async.value;
    final twoColumn = context.screenWidth >= 900;
    final count = cart?.summary.itemCount ?? 0;

    return Scaffold(
      appBar: AppBar(title: Text(count > 0 ? 'Cart ($count)' : 'Cart')),
      bottomNavigationBar: (cart != null && !cart.isEmpty && !twoColumn) ? _CheckoutBar(cart: cart) : null,
      body: RefreshIndicator(
        onRefresh: () => ref.read(cartProvider.notifier).refresh().catchError((_) {}),
        child: switch (async) {
          AsyncValue(:final value?) when value.isEmpty => const _EmptyCart(),
          AsyncValue(:final value?) => twoColumn ? _TwoColumn(cart: value) : _OneColumn(cart: value),
          AsyncValue(:final error?) => _Fill(
            child: ErrorState(error: error, onRetry: () => ref.invalidate(cartProvider)),
          ),
          _ => const _CartSkeleton(),
        },
      ),
    );
  }
}

class _OneColumn extends StatelessWidget {
  const _OneColumn({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        ResponsiveCenter(
          maxWidth: 720,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FreeShippingProgress(summary: cart.summary),
              const SizedBox(height: AppSpacing.md),
              if (cart.unavailable.isNotEmpty) _UnavailableBanner(count: cart.unavailable.length),
              _Lines(cart: cart),
              const SizedBox(height: AppSpacing.lg),
              CouponCard(summary: cart.summary),
              const SizedBox(height: AppSpacing.md),
              const _Insights(),
              const SizedBox(height: AppSpacing.md),
              SummaryCard(summary: cart.summary),
            ],
          ),
        ),
      ],
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return ResponsiveCenter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                FreeShippingProgress(summary: cart.summary),
                const SizedBox(height: AppSpacing.md),
                if (cart.unavailable.isNotEmpty) _UnavailableBanner(count: cart.unavailable.length),
                _Lines(cart: cart),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          SizedBox(
            width: 380,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CouponCard(summary: cart.summary),
                  const SizedBox(height: AppSpacing.md),
                  const _Insights(),
                  const SizedBox(height: AppSpacing.md),
                  SummaryCard(summary: cart.summary),
                  const SizedBox(height: AppSpacing.md),
                  _CheckoutButton(cart: cart),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// AI cart insights; reloads the cart after a one-tap swap.
class _Insights extends ConsumerWidget {
  const _Insights();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      CartInsightsCard(onCartChanged: () => ref.read(cartProvider.notifier).refresh().catchError((_) {}));
}

class _Lines extends StatelessWidget {
  const _Lines({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < cart.items.length; i++) ...[
          if (i > 0) const Divider(),
          _CartLine(key: ValueKey(cart.items[i].productId), item: cart.items[i]),
        ],
      ],
    );
  }
}

class _CartLine extends ConsumerWidget {
  const _CartLine({super.key, required this.item});

  final CartItem item;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final notifier = ref.read(cartProvider.notifier);
    try {
      final removed = await notifier.remove(item.productId);
      if (removed == null || !context.mounted) return;
      AppSnack.info(
        context,
        'Removed from cart',
        actionLabel: 'Undo',
        onAction: () => notifier.restore(removed).catchError((_) {}),
      );
    } on ApiException catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  Future<void> _setQty(BuildContext context, WidgetRef ref, int q) async {
    if (q <= 0) return _remove(context, ref);
    try {
      final res = await ref.read(cartProvider.notifier).setQuantity(item.productId, q);
      if (res.message != null && context.mounted) AppSnack.info(context, res.message!);
    } on ApiException catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = item.product;
    final colors = context.colors;
    final t = context.textTheme;
    final available = p.inStock;
    final imageSize = context.isWide ? 112.0 : 88.0;

    void open() {
      ProductPreviewCache.remember(p);
      context.push(Routes.product(p.id));
    }

    return Dismissible(
      key: ValueKey('dismiss-${item.productId}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _remove(context, ref),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.lg),
        decoration: BoxDecoration(color: colors.error.withValues(alpha: 0.12), borderRadius: AppRadii.cardAll),
        child: Icon(Icons.delete_outline_rounded, color: colors.error),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Open ${p.title}',
              child: InkWell(
                onTap: open,
                borderRadius: AppRadii.cardAll,
                child: Opacity(
                  opacity: available ? 1 : 0.45,
                  child: Container(
                    width: imageSize,
                    height: imageSize,
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.cardAll),
                    child: AppNetworkImage(p.thumbnail, width: imageSize - 16, fit: BoxFit.contain, backgroundColor: Colors.transparent),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (p.brand != null) Text(p.brand!, style: t.labelSmall!.copyWith(color: colors.muted)),
                            InkWell(
                              onTap: open,
                              child: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w500)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove ${p.title}',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _remove(context, ref),
                        icon: Icon(Icons.close_rounded, size: 20, color: colors.muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  PriceText(p.price, compareAt: p.compareAtPrice, size: PriceSize.small),
                  if (!available)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Text('Out of stock — remove to checkout', style: t.labelMedium!.copyWith(color: colors.error)),
                    )
                  else if (p.isLowStock)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxs),
                      child: Text('Only ${p.stock} left', style: t.labelMedium!.copyWith(color: colors.warning)),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: [
                      QuantityStepper(
                        value: item.quantity,
                        min: 0,
                        max: item.maxQuantity,
                        compact: true,
                        onChanged: available ? (q) => _setQty(context, ref, q) : null,
                      ),
                      if (item.quantity > 1 && available)
                        Text(
                          Formatters.price(item.lineTotal),
                          style: t.titleSmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableBanner extends StatelessWidget {
  const _UnavailableBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => FormErrorBanner(
    message:
        '${Formatters.plural(count, 'item')} in your cart ${count == 1 ? 'is' : 'are'} out of stock. Remove ${count == 1 ? 'it' : 'them'} to check out.',
  );
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surface, border: Border(top: BorderSide(color: colors.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.sm, context.pagePadding, AppSpacing.sm),
          child: Row(
            children: [
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total', style: t.bodySmall),
                    AnimatedSwitcher(
                      duration: context.motion(AppDurations.fast),
                      child: FittedBox(
                        key: ValueKey(cart.summary.total),
                        fit: BoxFit.scaleDown,
                        child: Text(
                          Formatters.price(cart.summary.total),
                          style: t.titleLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _CheckoutButton(cart: cart)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutButton extends StatelessWidget {
  const _CheckoutButton({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context) {
    final blocked = cart.unavailable.isNotEmpty;
    return AppButton(
      label: 'Checkout',
      trailingIcon: Icons.arrow_forward_rounded,
      expand: true,
      size: AppButtonSize.large,
      onPressed: blocked ? null : () => context.push(Routes.checkout),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return _Fill(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'Your cart is empty',
            message: 'Find something you love, or let our AI assistant suggest a few ideas.',
            actionLabel: 'Start shopping',
            onAction: () => context.go(Routes.home),
          ),
          AppButton.ghost(
            label: 'Ask the assistant',
            icon: Icons.auto_awesome_outlined,
            onPressed: () => context.go(Routes.assistantWith(prompt: 'Suggest something I might like')),
          ),
        ],
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: c.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}

class _CartSkeleton extends StatelessWidget {
  const _CartSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ResponsiveCenter(
      maxWidth: 720,
      child: Column(
        children: [
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 64, borderRadius: AppRadii.cardAll),
          SizedBox(height: AppSpacing.md),
          SkeletonListTile(leadingSize: 88),
          SkeletonListTile(leadingSize: 88),
          SkeletonListTile(leadingSize: 88),
          SizedBox(height: AppSpacing.md),
          Skeleton(height: 160, borderRadius: AppRadii.cardAll),
        ],
      ),
    );
  }
}
