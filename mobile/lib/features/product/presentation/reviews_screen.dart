import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/providers/require_auth.dart';
import '../data/models/product_detail.dart';
import '../providers/product_providers.dart';
import 'widgets/review_widgets.dart';

/// All reviews of a product: rating summary, sort, infinite scroll, write a review.
class ReviewsScreen extends ConsumerStatefulWidget {
  const ReviewsScreen({super.key, required this.productId});

  final int productId;

  @override
  ConsumerState<ReviewsScreen> createState() => _ReviewsScreenState();
}

class _ReviewsScreenState extends ConsumerState<ReviewsScreen> {
  ReviewSort _sort = ReviewSort.recent;

  ReviewsArgs get _args => (productId: widget.productId, sort: _sort);

  Future<void> _write() async {
    if (!requireAuth(context, ref, message: 'Sign in to write a review')) return;
    final title = ref.read(productDetailProvider('${widget.productId}')).value?.summary.title ?? 'This product';
    await showWriteReviewSheet(context, productId: widget.productId, productTitle: title);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reviewsProvider(_args));
    final title = ref.watch(productDetailProvider('${widget.productId}').select((a) => a.value?.summary.title));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Reviews'),
            if (title != null)
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.bodySmall),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _write,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Write a review'),
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600) ref.read(reviewsProvider(_args).notifier).loadMore();
          return false;
        },
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(reviewsProvider(_args));
            try {
              await ref.read(reviewsProvider(_args).future);
            } catch (_) {}
          },
          child: switch (async) {
            AsyncValue(:final value?) => _list(value),
            AsyncValue(:final error?) => ListView(
              children: [
                const SizedBox(height: AppSpacing.xxl),
                ErrorState(error: error, onRetry: () => ref.invalidate(reviewsProvider(_args))),
              ],
            ),
            _ => const ResponsiveCenter(maxWidth: 760, child: SkeletonList(count: 6, circleLeading: true)),
          },
        ),
      ),
    );
  }

  Widget _list(ReviewsState s) {
    final colors = context.colors;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        ResponsiveCenter(
          maxWidth: 760,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              if (s.stats.count > 0)
                RatingBreakdown(average: s.stats.average, count: s.stats.count, breakdown: s.stats.breakdown),
              const SizedBox(height: AppSpacing.lg),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final sort in ReviewSort.values)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.xs),
                        child: ChoiceChip(
                          label: Text(sort.label),
                          selected: sort == _sort,
                          onSelected: (_) => setState(() => _sort = sort),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (s.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: EmptyState(
                    icon: Icons.rate_review_outlined,
                    title: 'No reviews yet',
                    message: 'Bought it? Help other shoppers decide.',
                    actionLabel: 'Write the first review',
                    onAction: _write,
                  ),
                )
              else
                for (var i = 0; i < s.items.length; i++) ...[
                  if (i > 0) Divider(color: colors.border),
                  ReviewTile(review: s.items[i]),
                ],
              if (s.loadingMore) const SkeletonListTile(circleLeading: true, leadingSize: 36),
              if (s.loadMoreError != null)
                Center(
                  child: AppButton.secondary(
                    label: 'Retry loading more',
                    size: AppButtonSize.small,
                    onPressed: ref.read(reviewsProvider(_args).notifier).loadMore,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
