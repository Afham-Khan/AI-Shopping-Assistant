import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/paged_controller.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/models/order.dart';
import '../data/orders_repository.dart';
import '../providers/orders_providers.dart';
import 'widgets/order_widgets.dart';

/// Orders in three tabs: Active / Delivered / Cancelled.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: OrderFilter.values.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My orders'),
          bottom: TabBar(
            tabAlignment: TabAlignment.fill,
            tabs: [for (final f in OrderFilter.values) Tab(text: f.label)],
          ),
        ),
        body: TabBarView(children: [for (final f in OrderFilter.values) _OrdersTab(filter: f)]),
      ),
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.filter});

  final OrderFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ordersProvider(filter));
    Future<void> refresh() async {
      ref.invalidate(ordersProvider(filter));
      try {
        await ref.read(ordersProvider(filter).future);
      } catch (_) {}
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) ref.read(ordersProvider(filter).notifier).loadMore();
          return false;
        },
        child: switch (async) {
          AsyncValue(:final value?) when value.isEmpty => _EmptyScroll(filter: filter),
          AsyncValue(:final value?) => _list(context, value),
          AsyncValue(:final error?) => ListView(
            children: [
              const SizedBox(height: AppSpacing.xxl),
              ErrorState(error: error, onRetry: () => ref.invalidate(ordersProvider(filter))),
            ],
          ),
          _ => const ResponsiveCenter(maxWidth: 760, child: SkeletonList(count: 4)),
        },
      ),
    );
  }

  Widget _list(BuildContext context, PagedState<OrderSummary> s) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(
        horizontal: SliverResponsiveCenter.sidePadding(context, context.screenWidth, maxWidth: 760),
        vertical: AppSpacing.md,
      ),
      itemCount: s.items.length + (s.loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) => i < s.items.length ? _OrderCard(order: s.items[i]) : const SkeletonListTile(),
    );
  }
}

class _EmptyScroll extends StatelessWidget {
  const _EmptyScroll({required this.filter});

  final OrderFilter filter;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (filter) {
      OrderFilter.active => ('No active orders', 'Orders on their way will show up here.'),
      OrderFilter.delivered => ('Nothing delivered yet', 'Your completed orders will appear here.'),
      OrderFilter.cancelled => ('No cancelled orders', 'Good news — nothing was cancelled.'),
    };
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: c.maxHeight,
          child: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: title,
            message: message,
            actionLabel: filter == OrderFilter.active ? 'Start shopping' : null,
            onAction: filter == OrderFilter.active ? () => context.go(Routes.home) : null,
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.orderDetailOf(order.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.orderNumber, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('Placed ${Formatters.date(order.placedAt)}', style: t.bodySmall),
                      ],
                    ),
                  ),
                  OrderStatusChip(status: order.status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final fit = ((c.maxWidth + AppSpacing.xs) / (56 + AppSpacing.xs)).floor().clamp(1, 3);
                        final shown = order.previewImages.take(fit).toList();
                        final more = order.itemCount - shown.length;
                        return Row(
                          children: [
                            for (final img in shown)
                              Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.xs),
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
                                  child: AppNetworkImage(img, width: 48, fit: BoxFit.contain, backgroundColor: Colors.transparent),
                                ),
                              ),
                            if (more > 0 && shown.length < fit)
                              Container(
                                width: 56,
                                height: 56,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
                                child: Text('+$more', style: t.titleSmall),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(Formatters.price(order.total), style: t.titleMedium),
                      Text(Formatters.plural(order.itemCount, 'item'), style: t.bodySmall),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
