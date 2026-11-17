import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/shopping_models.dart';
import '../../providers/ai_providers.dart';
import '../ai_actions.dart';
import 'ai_ui.dart';

/// "Complete the look" on a fashion product page: one strong match per
/// outfit slot (Bag, Shoes, Jewellery…) with why it goes together. Add pieces
/// one by one or the whole look at once. Hidden for non-fashion products and
/// when the server has nothing to suggest.
class CompleteTheLookSection extends ConsumerWidget {
  const CompleteTheLookSection({super.key, required this.product, this.departmentSlug});

  final ProductSummary product;
  final String? departmentSlug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isFashionProduct(departmentSlug: departmentSlug, categorySlug: product.category?.slug)) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(completeLookProvider(product.id));
    return switch (async) {
      AsyncValue(:final value?) => value.isOutfit ? _LookView(product: product, look: value) : const SizedBox.shrink(),
      // an older server without the endpoint: just don't show the section
      AsyncValue(:final error?) when ApiException.from(error).isNotFound => const SizedBox.shrink(),
      AsyncValue(:final error?) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xl),
        child: AiInlineError(
          error: error,
          title: "Couldn't load outfit ideas",
          onRetry: () => ref.invalidate(completeLookProvider(product.id)),
        ),
      ),
      _ => const _LookSkeleton(),
    };
  }
}

class _LookView extends ConsumerStatefulWidget {
  const _LookView({required this.product, required this.look});

  final ProductSummary product;
  final CompleteLook look;

  @override
  ConsumerState<_LookView> createState() => _LookViewState();
}

class _LookViewState extends ConsumerState<_LookView> {
  bool _addingAll = false;

  List<ProductSummary> get _all => [
    if (widget.product.inStock) widget.product,
    ...[for (final i in widget.look.items) if (i.product.inStock) i.product],
  ];

  Future<void> _addAll() async {
    setState(() => _addingAll = true);
    try {
      await addAllToCart(context, ref, _all, source: 'complete_look');
    } finally {
      if (mounted) setState(() => _addingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final colors = context.colors;
    final t = context.textTheme;
    final pieces = _all;
    final total = pieces.fold<double>(0, (sum, p) => sum + p.price);

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AiSparkleIcon(size: 18),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Semantics(header: true, child: Text('Complete the look', style: t.titleLarge))),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            look.paletteTip ?? 'Pieces Zel thinks go well with this one.',
            style: t.bodySmall!.copyWith(color: colors.muted, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, c) {
              const gap = AppSpacing.sm;
              final cardW = (c.maxWidth - gap) / 2;
              final items = look.items;
              // every card in a row shares one height (photo + text block + button)
              final rowHeight = cardW / LookCard.imageRatio + MediaQuery.textScalerOf(context).scale(120) + 56;
              return Column(
                children: [
                  for (var i = 0; i < items.length; i += 2)
                    Padding(
                      padding: const EdgeInsets.only(bottom: gap),
                      child: SizedBox(
                        height: rowHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: cardW, child: LookCard(item: items[i])),
                            const SizedBox(width: gap),
                            SizedBox(
                              width: cardW,
                              child: i + 1 < items.length ? LookCard(item: items[i + 1]) : const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (pieces.length > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('The whole look', style: t.titleSmall),
                  Text(
                    '${Formatters.plural(pieces.length, 'piece')} · ${Formatters.price(total)}',
                    style: t.bodySmall!.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Add the look',
                    icon: Icons.add_shopping_cart_rounded,
                    expand: true,
                    loading: _addingAll,
                    semanticLabel: 'Add the whole look, ${Formatters.plural(pieces.length, 'piece')}, ${Formatters.price(total)}',
                    onPressed: _addAll,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One outfit piece: role label, photo, price, why it matches, quick add.
class LookCard extends ConsumerStatefulWidget {
  const LookCard({super.key, required this.item});

  /// Photo aspect ratio (width / height).
  static const imageRatio = 1.1;

  final LookItem item;

  @override
  ConsumerState<LookCard> createState() => _LookCardState();
}

class _LookCardState extends ConsumerState<LookCard> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await quickAddToCart(context, ref, widget.item.product, source: 'complete_look', label: widget.item.role);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final p = item.product;
    final colors = context.colors;
    final t = context.textTheme;
    final reason = p.match?.reasons.firstOrNull;

    return AppCard(
      padding: EdgeInsets.zero,
      semanticLabel: '${item.role}: ${p.title}, ${Formatters.price(p.price)}',
      onTap: () => openAiProduct(context, ref, p.id, source: 'complete_look'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Stack(
            children: [
              AspectRatio(
                aspectRatio: LookCard.imageRatio,
                child: AppNetworkImage(p.thumbnail, fit: BoxFit.contain, semanticLabel: p.title),
              ),
              Positioned(
                top: AppSpacing.xs,
                left: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadii.pillAll,
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    item.role,
                    style: t.labelSmall!.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            // a fixed-height text block: never scrolls, never overflows
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xs, AppSpacing.xs, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title, style: t.labelLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  PriceText(p.price, compareAt: p.compareAtPrice, size: PriceSize.small, singleLine: true),
                  if (reason != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      reason,
                      style: t.bodySmall!.copyWith(color: colors.muted, height: 1.3),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: AppButton.secondary(
              label: p.inStock ? 'Add' : 'Sold out',
              icon: p.inStock ? Icons.add_shopping_cart_rounded : null,
              size: AppButtonSize.small,
              expand: true,
              loading: _adding,
              semanticLabel: 'Add ${p.title} to cart',
              onPressed: p.inStock ? _add : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _LookSkeleton extends StatelessWidget {
  const _LookSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiThinking(messages: ['Styling an outfit…', 'Matching colours…'], lines: 0, compact: true),
          SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: Skeleton(height: 220, borderRadius: AppRadii.cardAll)),
              SizedBox(width: AppSpacing.sm),
              Expanded(child: Skeleton(height: 220, borderRadius: AppRadii.cardAll)),
            ],
          ),
        ],
      ),
    );
  }
}
