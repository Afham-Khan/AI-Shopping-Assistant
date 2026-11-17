import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../catalog/presentation/widgets/open_target.dart';
import '../providers/notifications_providers.dart';

/// Notifications grouped by day; tap marks read and opens the related screen.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markAll(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(notificationsProvider.notifier).markAllRead();
    } on ApiException catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: () => _markAll(context, ref),
              style: TextButton.styleFrom(foregroundColor: context.colors.secondary),
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          try {
            await ref.read(notificationsProvider.future);
          } catch (_) {}
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) ref.read(notificationsProvider.notifier).loadMore();
            return false;
          },
          child: switch (async) {
            AsyncValue(:final value?) when value.isEmpty => LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: c.maxHeight,
                  child: const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'You\'re all caught up',
                    message: 'Order updates, price drops and offers will appear here.',
                  ),
                ),
              ),
            ),
            AsyncValue(:final value?) => _GroupedList(items: value.items, loadingMore: value.loadingMore),
            AsyncValue(:final error?) => ListView(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                ErrorState(error: error, onRetry: () => ref.invalidate(notificationsProvider)),
              ],
            ),
            _ => const ResponsiveCenter(maxWidth: 760, child: SkeletonList(count: 7, circleLeading: true)),
          },
        ),
      ),
    );
  }
}

class _GroupedList extends StatelessWidget {
  const _GroupedList({required this.items, required this.loadingMore});

  final List<AppNotification> items;
  final bool loadingMore;

  static String _dayLabel(DateTime? d) {
    if (d == null) return 'Earlier';
    final local = d.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return 'This week';
    return Formatters.date(local);
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    String? current;
    for (final n in items) {
      final label = _dayLabel(n.createdAt);
      if (label != current) {
        current = label;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.xs),
            child: Semantics(header: true, child: Text(label, style: context.textTheme.titleSmall!.copyWith(color: context.colors.muted))),
          ),
        );
      }
      rows.add(_NotificationTile(n: n));
    }
    if (loadingMore) rows.add(const SkeletonListTile(circleLeading: true));

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        SliverResponsiveCenter.sidePadding(context, context.screenWidth, maxWidth: 760),
        0,
        SliverResponsiveCenter.sidePadding(context, context.screenWidth, maxWidth: 760),
        AppSpacing.xxl,
      ),
      children: rows,
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.n});

  final AppNotification n;

  void _open(BuildContext context, WidgetRef ref) {
    ref.read(notificationsProvider.notifier).markRead(n);
    final orderId = n.orderId;
    final productId = n.productId;
    final target = n.target;
    if (orderId != null) {
      context.push(Routes.orderDetailOf(orderId));
    } else if (productId != null) {
      context.push(Routes.product(productId));
    } else if (target != null) {
      openTarget(context, type: JsonX.asString(target['type']), value: JsonX.asStringOrNull(target['value']));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final t = context.textTheme;
    final (icon, color) = switch (n.type) {
      'order' => (Icons.local_shipping_outlined, colors.primary),
      'price_drop' => (Icons.trending_down_rounded, colors.sale),
      'promo' => (Icons.local_offer_outlined, colors.warning),
      'ai' => (Icons.auto_awesome_outlined, colors.ai),
      _ => (Icons.notifications_none_rounded, colors.secondary),
    };

    return Semantics(
      button: true,
      label: '${n.isUnread ? 'Unread. ' : ''}${n.title}. ${n.body}',
      excludeSemantics: true,
      child: Material(
        color: n.isUnread ? colors.surfaceVariant.withValues(alpha: 0.6) : Colors.transparent,
        borderRadius: AppRadii.cardAll,
        child: InkWell(
          borderRadius: AppRadii.cardAll,
          onTap: () => _open(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: context.isDark ? 0.18 : 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: t.titleSmall!.copyWith(fontWeight: n.isUnread ? FontWeight.w700 : FontWeight.w500),
                      ),
                      const SizedBox(height: 2),
                      Text(n.body, style: t.bodyMedium!.copyWith(color: colors.muted)),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(Formatters.relative(n.createdAt), style: t.bodySmall),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  opacity: n.isUnread ? 1 : 0,
                  duration: context.motion(AppDurations.normal),
                  child: Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.xs, top: 6),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: colors.primary, shape: BoxShape.circle),
                    ),
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
