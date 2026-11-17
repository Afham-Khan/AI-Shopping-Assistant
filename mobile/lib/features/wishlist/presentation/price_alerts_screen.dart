import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/price_watch_models.dart';
import '../providers/price_watch_providers.dart';
import 'widgets/watch_price_sheet.dart';

/// Every product the user watches: current price vs. target, edit or stop.
class PriceAlertsScreen extends ConsumerWidget {
  const PriceAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(priceWatchesProvider);

    Future<void> reload() async {
      ref.invalidate(priceWatchesProvider);
      try {
        await ref.read(priceWatchesProvider.future);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Price alerts')),
      body: RefreshIndicator(
        onRefresh: reload,
        child: switch (async) {
          AsyncValue(:final value?) when value.isEmpty => _Scroll(
            child: EmptyState(
              icon: Icons.notifications_none_rounded,
              title: 'No price alerts yet',
              message: 'Tap "Watch price" on any product. Zel tells you when it drops or comes back in stock.',
              actionLabel: 'Explore products',
              onAction: () => context.go(Routes.explore),
            ),
          ),
          AsyncValue(:final value?) => _List(watches: value),
          AsyncValue(:final error?) => _Scroll(child: ErrorState(error: error, onRetry: reload)),
          _ => const ResponsiveCenter(maxWidth: 640, child: SkeletonList(count: 4)),
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

class _List extends StatelessWidget {
  const _List({required this.watches});

  final List<PriceWatch> watches;

  @override
  Widget build(BuildContext context) {
    final atTarget = watches.where((w) => w.status.targetReached).length;
    final colors = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.sm, context.pagePadding, AppSpacing.xxl),
      children: [
        ResponsiveCenter(
          maxWidth: 640,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                liveRegion: true,
                child: Text(
                  atTarget > 0
                      ? '${Formatters.plural(watches.length, 'product')} watched · $atTarget at your target'
                      : '${Formatters.plural(watches.length, 'product')} watched',
                  style: context.textTheme.labelLarge!.copyWith(color: colors.muted),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final w in watches)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _WatchCard(watch: w),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WatchCard extends ConsumerWidget {
  const _WatchCard({required this.watch});

  final PriceWatch watch;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final p = watch.product;
    String? message;
    final removed = await ConfirmDialog.show(
      context,
      title: 'Stop watching this price?',
      message: "You won't get alerts for ${p.title} any more.",
      confirmLabel: 'Stop watching',
      icon: Icons.notifications_off_outlined,
      onConfirm: () async => message = await ref.read(priceWatchesProvider.notifier).remove(p.id),
    );
    if (removed && context.mounted) AppSnack.info(context, message ?? 'Stopped watching');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = watch.product;
    final s = watch.status;
    final colors = context.colors;
    final t = context.textTheme;
    final price = watch.currentPrice;

    final badges = <Widget>[
      if (!s.inStock) const StatusBadge('Out of stock', tone: StatusTone.warning, icon: Icons.remove_shopping_cart_outlined),
      if (s.targetReached) const StatusBadge('Target reached', tone: StatusTone.success, icon: Icons.check_rounded),
      if (s.dropSinceWatch >= 1)
        StatusBadge('Down ${Formatters.price(s.dropSinceWatch)}', tone: StatusTone.success, icon: Icons.trending_down_rounded),
      if (watch.notifyRestock) const StatusBadge('Restock alert on', tone: StatusTone.info, icon: Icons.inventory_2_outlined),
    ];

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      semanticLabel: '${p.title}, ${Formatters.price(price)}, ${watch.targetLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: AppRadii.inputAll,
            onTap: () => context.push(Routes.product(p.id)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppNetworkImage(
                  p.thumbnail,
                  width: 76,
                  height: 76,
                  fit: BoxFit.contain,
                  borderRadius: AppRadii.inputAll,
                  semanticLabel: p.title,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      PriceText(price, compareAt: p.compareAtPrice, size: PriceSize.small),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.notifications_active_outlined, size: 14, color: colors.primary),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              watch.targetLabel,
                              style: t.labelMedium!.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (s.summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.summary, style: t.bodySmall!.copyWith(color: colors.muted, height: 1.4)),
          ],
          if (badges.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: badges),
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: AppButton.secondary(
                  label: 'Edit alert',
                  icon: Icons.tune_rounded,
                  size: AppButtonSize.small,
                  onPressed: () => showWatchPriceSheet(context, ref, product: p),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: AppButton.ghost(
                  label: 'Stop watching',
                  size: AppButtonSize.small,
                  semanticLabel: 'Stop watching ${p.title}',
                  onPressed: () => _remove(context, ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
