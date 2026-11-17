import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../cart/presentation/widgets/cart_summary.dart';
import '../../cart/providers/cart_controller.dart';
import '../data/models/order.dart';
import '../providers/orders_providers.dart';
import 'widgets/order_widgets.dart';

/// One order: live status timeline (pull to refresh — the demo server
/// advances status over time), items, address, payment, totals, cancel and
/// "Buy again".
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderDetailProvider(orderId));
    final order = async.value;

    return Scaffold(
      appBar: AppBar(title: Text(order?.orderNumber ?? 'Order')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(orderDetailProvider(orderId));
          try {
            await ref.read(orderDetailProvider(orderId).future);
          } catch (_) {}
        },
        child: switch (async) {
          AsyncValue(:final value?) => _Body(order: value),
          AsyncValue(:final error?) => ListView(
            children: [
              const SizedBox(height: AppSpacing.xxl),
              ErrorState(
                error: error,
                message: ApiException.from(error).isNotFound ? 'We couldn\'t find this order.' : null,
                onRetry: () => ref.invalidate(orderDetailProvider(orderId)),
              ),
            ],
          ),
          _ => const ResponsiveCenter(
            maxWidth: 760,
            child: Column(
              children: [
                SizedBox(height: AppSpacing.md),
                Skeleton(height: 96, borderRadius: AppRadii.cardAll),
                SizedBox(height: AppSpacing.md),
                SkeletonList(count: 4, circleLeading: true),
              ],
            ),
          ),
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final twoColumn = context.screenWidth >= 900;
    final left = [
      _StatusHeader(order: order),
      _Card(title: 'Tracking', child: OrderTimeline(order: order)),
      _Card(
        title: 'Items (${order.itemCount})',
        child: Column(children: [for (final i in order.items) _ItemRow(item: i)]),
      ),
    ];
    final right = [
      if (order.shippingAddress != null)
        _Card(
          title: 'Delivery address',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${order.shippingAddress!.fullName} · ${order.shippingAddress!.phone}',
                style: context.textTheme.bodyMedium,
              ),
              Text(order.shippingAddress!.oneLine, style: context.textTheme.bodySmall),
            ],
          ),
        ),
      _Card(
        title: 'Payment',
        child: Row(
          children: [
            Icon(order.paymentMethod == 'card' ? Icons.credit_card_rounded : Icons.payments_outlined, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(order.paymentLabel, style: context.textTheme.bodyMedium)),
            Text(order.paymentStatus.capitalized, style: context.textTheme.labelLarge!.copyWith(
              color: order.paymentStatus == 'paid' ? context.colors.success : context.colors.muted,
            )),
          ],
        ),
      ),
      if (order.notes != null) _Card(title: 'Notes', child: Text(order.notes!, style: context.textTheme.bodyMedium)),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: SummaryBox(
          title: 'Payment summary',
          subtotal: order.subtotal,
          discount: order.discount,
          couponCode: order.couponCode,
          shippingFee: order.shippingFee,
          total: order.total,
        ),
      ),
      _Actions(order: order),
    ];

    if (twoColumn) {
      return ResponsiveCenter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                children: left,
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            SizedBox(
              width: 380,
              child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: AppSpacing.xl), child: Column(children: right)),
            ),
          ],
        ),
      );
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        ResponsiveCenter(maxWidth: 760, child: Column(children: [...left, ...right])),
      ],
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final s = order.status;
    final (title, subtitle) = switch (s) {
      OrderStatus.delivered => ('Delivered', 'on ${Formatters.date(order.deliveredAt ?? order.estimatedDelivery)}'),
      OrderStatus.cancelled => ('Cancelled', 'on ${Formatters.date(order.cancelledAt)}'),
      _ => (
        s == OrderStatus.outForDelivery ? 'Arriving today' : 'Arriving ${Formatters.date(order.estimatedDelivery)}',
        s.stepTitle,
      ),
    };
    final icon = switch (s) {
      OrderStatus.delivered => Icons.inventory_2_outlined,
      OrderStatus.cancelled => Icons.cancel_outlined,
      OrderStatus.shipped || OrderStatus.outForDelivery => Icons.local_shipping_outlined,
      _ => Icons.schedule_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.cardAll),
        child: Row(
          children: [
            Icon(icon, size: 32, color: s == OrderStatus.cancelled ? colors.error : colors.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(liveRegion: true, child: Text(title, style: t.titleLarge)),
                  Text(subtitle, style: t.bodySmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text('Placed ${Formatters.dateTime(order.placedAt)}', style: t.bodySmall),
                ],
              ),
            ),
            OrderStatusChip(status: s),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.cardAll,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(header: true, child: Text(title, style: context.textTheme.titleMedium)),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return InkWell(
      onTap: () => context.push(Routes.product(item.productId)),
      borderRadius: AppRadii.inputAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            AppNetworkImage(item.thumbnail, width: 56, height: 56, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium),
                  Text('Qty ${item.quantity} × ${Formatters.price(item.unitPrice)}', style: t.bodySmall),
                  Text(Formatters.price(item.lineTotal), style: t.titleSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.order});

  final OrderDetail order;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _buying = false;

  Future<void> _cancel() async {
    final paid = widget.order.paymentStatus == 'paid';
    final cancelled = await ConfirmDialog.show(
      context,
      title: 'Cancel this order?',
      message: paid
          ? 'This action cannot be undone. ${Formatters.price(widget.order.total)} will be refunded to your card.'
          : 'This action cannot be undone.',
      confirmLabel: 'Cancel order',
      cancelLabel: 'Keep order',
      icon: Icons.cancel_outlined,
      onConfirm: () async {
        try {
          await ref.read(orderDetailProvider(widget.order.id).notifier).cancel();
        } on ApiException catch (e) {
          // status moved on (e.g. shipped): show the latest
          if (e.isConflict) ref.invalidate(orderDetailProvider(widget.order.id));
          rethrow;
        }
      },
    );
    if (cancelled && mounted) AppSnack.success(context, 'Order cancelled');
  }

  Future<void> _buyAgain() async {
    setState(() => _buying = true);
    final result = await ref.read(cartProvider.notifier).addAll([
      for (final i in widget.order.items) (productId: i.productId, quantity: i.quantity),
    ], source: 'buy_again');
    final added = result.added;
    if (!mounted) return;
    setState(() => _buying = false);
    if (added == 0) {
      AppSnack.error(context, result.error ?? 'Couldn\'t add these items');
    } else {
      AppSnack.success(
        context,
        added == widget.order.items.length ? 'Items added to your cart' : 'Added $added of ${widget.order.items.length} items',
        actionLabel: 'View cart',
        onAction: () => context.go(Routes.cart),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(label: 'Buy again', icon: Icons.replay_rounded, expand: true, loading: _buying, onPressed: _buyAgain),
          if (o.status.canCancel) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton.ghost(label: 'Cancel order', expand: true, onPressed: _cancel),
          ],
        ],
      ),
    );
  }
}
