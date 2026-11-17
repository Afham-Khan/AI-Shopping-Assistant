import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../wishlist/presentation/widgets/watch_price_sheet.dart';
import '../../../wishlist/providers/price_watch_providers.dart';
import '../../data/models/price_history.dart';
import '../../providers/product_providers.dart';
import 'price_history_chart.dart';

/// "Price history" on the product page: a mini chart of real recorded price
/// changes, and the "Watch price" action. With no history yet it says so
/// ("Tracking started today") instead of faking a chart.
class PriceHistoryCard extends ConsumerWidget {
  const PriceHistoryCard({super.key, required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(priceHistoryProvider(product.id));
    final watch = ref.watch(priceWatchForProvider(product.id));
    final t = context.textTheme;
    final colors = context.colors;
    final history = async.value;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // a Wrap: on a narrow screen or at large text the trend badge drops below the title
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.show_chart_rounded, size: 20, color: colors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(child: Semantics(header: true, child: Text('Price history', style: t.titleMedium))),
                ],
              ),
              if (history != null && history.hasChanges) _TrendBadge(trend: history.trend),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          switch (async) {
            AsyncValue(:final value?) => _HistoryBody(history: value),
            AsyncValue(hasError: true) => _InlineErrorLine(
              message: 'Could not load the price history.',
              onRetry: () => ref.invalidate(priceHistoryProvider(product.id)),
            ),
            _ => const Skeleton(height: 120, borderRadius: AppRadii.inputAll),
          },
          const SizedBox(height: AppSpacing.md),
          if (watch != null) ...[
            Row(
              children: [
                Icon(Icons.notifications_active_rounded, size: 18, color: colors.primary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    watch.badgeLabel,
                    style: t.labelLarge!.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          AppButton(
            label: watch == null ? 'Watch price' : 'Edit price alert',
            icon: watch == null ? Icons.notifications_none_rounded : Icons.tune_rounded,
            expand: true,
            onPressed: () => showWatchPriceSheet(context, ref, product: product),
          ),
        ],
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.history});

  final PriceHistory history;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;

    if (history.isEmpty) {
      return const _Note(
        icon: Icons.timeline_rounded,
        title: 'Tracking started today',
        message: "We'll chart every price change from now on. Watch this price and Zel tells you about the first drop.",
      );
    }
    if (!history.hasChanges) {
      // one recorded price and no change since: say since when, don't fake a line
      final since = history.points.first.at;
      final now = DateTime.now();
      final today = since.year == now.year && since.month == now.month && since.day == now.day;
      return _Note(
        icon: Icons.horizontal_rule_rounded,
        title: today ? 'Tracking started today' : 'Tracking since ${Formatters.date(since)}',
        message:
            'No price changes yet. It has held at ${Formatters.price(history.currentPrice)}. '
            'Watch it and Zel tells you about the first drop.',
      );
    }

    final series = history.series();
    final label =
        'Price history: ${Formatters.plural(history.changes, 'change')} in ${history.days} days, '
        'lowest ${Formatters.price(history.low)}, highest ${Formatters.price(history.high)}, '
        'now ${Formatters.price(history.currentPrice)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PriceHistoryChart(points: series, semanticLabel: label),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Lowest', value: Formatters.price(history.low), color: colors.success)),
            if (history.average != null) Expanded(child: _Stat(label: 'Average', value: Formatters.price(history.average))),
            Expanded(child: _Stat(label: 'Highest', value: Formatters.price(history.high))),
          ],
        ),
        if (history.insight != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(top: 2), child: AiSparkleIcon(size: 14)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(history.insight!, style: t.bodySmall!.copyWith(color: colors.muted, height: 1.4)),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Semantics(
      label: '$label $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelSmall!.copyWith(color: colors.faint)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: t.titleSmall!.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.trend});

  final String trend;

  @override
  Widget build(BuildContext context) {
    return switch (trend) {
      'down' => const StatusBadge('Price is down', tone: StatusTone.success, icon: Icons.trending_down_rounded),
      'up' => const StatusBadge('Price is up', tone: StatusTone.warning, icon: Icons.trending_up_rounded),
      _ => const StatusBadge('Steady', icon: Icons.trending_flat_rounded),
    };
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: colors.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: colors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(title, style: t.titleSmall)),
                const SizedBox(height: 2),
                Text(message, style: t.bodySmall!.copyWith(color: colors.muted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One-line inline failure with a retry link (the chart is optional, the page isn't).
class _InlineErrorLine extends StatelessWidget {
  const _InlineErrorLine({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: colors.muted),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(message, style: context.textTheme.bodySmall!.copyWith(color: colors.muted))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
