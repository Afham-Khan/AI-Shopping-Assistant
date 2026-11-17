import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/validators.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../catalog/data/catalog_repository.dart';
import '../../data/models/product_detail.dart';
import '../../providers/product_providers.dart';

/// Big average + 5→1 star distribution bars.
class RatingBreakdown extends StatelessWidget {
  const RatingBreakdown({super.key, required this.average, required this.count, required this.breakdown});

  final double average;
  final int count;
  final Map<int, int> breakdown;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final max = breakdown.values.fold<int>(0, (m, v) => v > m ? v : m);
    final total = breakdown.values.fold<int>(0, (s, v) => s + v);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          children: [
            Text(Formatters.rating(average), style: t.displaySmall),
            RatingStars.full(average, size: 14),
            const SizedBox(height: AppSpacing.xxs),
            Text(Formatters.plural(count, 'rating'), style: t.bodySmall),
          ],
        ),
        const SizedBox(width: AppSpacing.xl),
        Expanded(
          child: Column(
            children: [
              for (var star = 5; star >= 1; star--)
                Semantics(
                  label: '$star stars: ${breakdown[star] ?? 0} reviews',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(width: 14, child: Text('$star', style: t.labelMedium)),
                        Icon(Icons.star_rounded, size: 12, color: colors.star),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: AppRadii.pillAll,
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0, end: max == 0 ? 0 : (breakdown[star] ?? 0) / max),
                              duration: context.motion(AppDurations.slow),
                              curve: AppCurves.standard,
                              builder: (_, v, _) => LinearProgressIndicator(
                                value: v,
                                minHeight: 6,
                                color: colors.star,
                                backgroundColor: colors.surfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        SizedBox(
                          width: 34,
                          child: Text(
                            total == 0 ? '0%' : '${((breakdown[star] ?? 0) / total * 100).round()}%',
                            textAlign: TextAlign.end,
                            style: t.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ReviewTile extends StatefulWidget {
  const ReviewTile({super.key, required this.review});

  final Review review;

  @override
  State<ReviewTile> createState() => _ReviewTileState();
}

class _ReviewTileState extends State<ReviewTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final colors = context.colors;
    final t = context.textTheme;
    final long = r.comment.length > 220;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.surfaceVariant,
                child: Text(r.userInitials, style: t.labelMedium!.copyWith(color: colors.text)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.userName, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Wrap(
                      spacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        RatingStars.full(r.rating.toDouble(), size: 12),
                        Text(Formatters.relative(r.createdAt), style: t.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
              if (r.isVerified)
                Tooltip(
                  message: 'Bought this product',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.verified_rounded, size: 16, color: colors.success),
                      const SizedBox(width: 4),
                      Text('Verified', style: t.labelSmall!.copyWith(color: colors.success)),
                    ],
                  ),
                ),
            ],
          ),
          if (r.title != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(r.title!, style: t.titleSmall),
          ],
          const SizedBox(height: AppSpacing.xxs),
          AnimatedSize(
            duration: context.motion(AppDurations.normal),
            alignment: Alignment.topLeft,
            child: Text(
              r.comment,
              maxLines: _expanded || !long ? null : 4,
              overflow: _expanded || !long ? null : TextOverflow.ellipsis,
              style: t.bodyMedium,
            ),
          ),
          if (long)
            TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: colors.secondary),
              child: Text(_expanded ? 'Show less' : 'Read more'),
            ),
          if (r.helpfulCount > 0) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text('${Formatters.plural(r.helpfulCount, 'person', 'people')} found this helpful', style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// Opens the write-a-review sheet. Resolves to true when a review was posted.
Future<bool> showWriteReviewSheet(BuildContext context, {required int productId, required String productTitle}) async {
  final posted = await showAppBottomSheet<bool>(
    context,
    builder: (_) => _WriteReviewSheet(productId: productId, productTitle: productTitle),
  );
  return posted ?? false;
}

class _WriteReviewSheet extends ConsumerStatefulWidget {
  const _WriteReviewSheet({required this.productId, required this.productTitle});

  final int productId;
  final String productTitle;

  @override
  ConsumerState<_WriteReviewSheet> createState() => _WriteReviewSheetState();
}

class _WriteReviewSheetState extends ConsumerState<_WriteReviewSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _comment = TextEditingController();
  int _rating = 0;
  bool _busy = false;
  bool _ratingMissing = false;
  ApiException? _error;

  static const _labels = ['', 'Poor', 'Fair', 'Good', 'Very good', 'Excellent'];

  @override
  void dispose() {
    _title.dispose();
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final validForm = _form.currentState!.validate();
    setState(() => _ratingMissing = _rating == 0);
    if (!validForm || _rating == 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(catalogRepositoryProvider)
          .addReview(widget.productId, rating: _rating, title: _title.text, comment: _comment.text);
      ref
        ..invalidate(topReviewsProvider(widget.productId))
        ..invalidate(reviewsProvider)
        ..invalidate(productDetailProvider);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppSnack.success(context, 'Thanks! Your review is live.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.isConflict ? const ApiException('You already reviewed this product.', statusCode: 409) : e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return BottomSheetScaffold(
      title: 'Write a review',
      footer: AppButton(label: 'Post review', expand: true, loading: _busy, onPressed: _submit),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.productTitle, style: t.bodyMedium!.copyWith(color: colors.muted), maxLines: 2),
            const SizedBox(height: AppSpacing.md),
            FormErrorBanner(message: _error?.hasFieldErrors == true ? null : _error?.message),
            Text('Your rating', style: t.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  Semantics(
                    button: true,
                    selected: _rating == star,
                    label: '$star star${star == 1 ? '' : 's'}',
                    child: IconButton(
                      onPressed: () => setState(() {
                        _rating = star;
                        _ratingMissing = false;
                      }),
                      icon: AnimatedScale(
                        scale: star <= _rating && !context.reduceMotion ? 1.1 : 1,
                        duration: AppDurations.fast,
                        child: Icon(
                          star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 34,
                          color: star <= _rating ? colors.star : colors.muted,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(child: Text(_labels[_rating], style: t.titleSmall)),
              ],
            ),
            if (_ratingMissing)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: Text('Tap a star to rate', style: t.bodySmall!.copyWith(color: colors.error)),
              ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Title (optional)',
              controller: _title,
              hint: 'Sum it up in a few words',
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              errorText: _error?.fieldError('title'),
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Your review',
              controller: _comment,
              hint: 'What did you like or dislike? How did you use it?',
              minLines: 4,
              maxLines: 8,
              maxLength: 2000,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              textCapitalization: TextCapitalization.sentences,
              errorText: _error?.fieldError('comment'),
              validator: Validators.combine([
                Validators.required('Review'),
                Validators.minLength(10, 'Review'),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
