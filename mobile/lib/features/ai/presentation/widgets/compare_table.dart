import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/ai_models.dart';
import 'ai_ui.dart';

/// Column width so 2 products fit a phone and 3–4 scroll horizontally.
double compareColumnWidth(double available, int count, {double min = 140}) {
  if (count <= 0) return available;
  return math.max(min, available / count);
}

/// Extra height a "Best for you" label slot adds to the header.
const double compareBadgeSlot = 26;

/// Height of [CompareHeaderRow] at the current text scale (for pinned headers).
double compareHeaderHeight(BuildContext context, {double image = 64, bool badgeSlot = false}) {
  final s = MediaQuery.textScalerOf(context);
  return image + 8 + s.scale(38) + 4 + s.scale(22) + 20 + (badgeSlot ? s.scale(compareBadgeSlot) : 0);
}

/// Product heads (image, title, price) for the columns.
class CompareHeaderRow extends StatelessWidget {
  const CompareHeaderRow({
    super.key,
    required this.products,
    required this.columnWidth,
    this.onRemove,
    this.onOpen,
    this.imageSize = 64,
    this.bestForYouId,
  });

  final List<ProductSummary> products;
  final double columnWidth;
  final ValueChanged<ProductSummary>? onRemove;
  final ValueChanged<ProductSummary>? onOpen;
  final double imageSize;

  /// The product the server picked for the shopper's need: gets a label.
  /// When set, every column reserves the label's slot so photos stay aligned.
  final int? bestForYouId;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final s = MediaQuery.textScalerOf(context);
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in products)
          SizedBox(
            width: columnWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 10, AppSpacing.xs, 10),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  InkWell(
                    onTap: onOpen == null ? null : () => onOpen!(p),
                    borderRadius: AppRadii.inputAll,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (bestForYouId != null)
                          SizedBox(
                            height: s.scale(compareBadgeSlot),
                            child: p.id == bestForYouId
                                ? Align(
                                    alignment: Alignment.topLeft,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadii.pillAll),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          AiSparkleIcon(size: 12, color: colors.onPrimary),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'Best for you',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: t.labelSmall!.copyWith(color: colors.onPrimary, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                        AppNetworkImage(
                          p.thumbnail,
                          width: imageSize,
                          height: imageSize,
                          fit: BoxFit.contain,
                          borderRadius: AppRadii.inputAll,
                          semanticLabel: p.title,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: s.scale(38),
                          child: Text(
                            p.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelLarge!.copyWith(height: 1.3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        PriceText(p.price, size: PriceSize.small, singleLine: true),
                      ],
                    ),
                  ),
                  if (onRemove != null)
                    Positioned(
                      top: -10,
                      right: -8,
                      child: IconButton(
                        tooltip: 'Remove ${p.title}',
                        onPressed: () => onRemove!(p),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Aligned spec rows; the best value per row (bestIndex) is highlighted.
class CompareSpecRows extends StatelessWidget {
  const CompareSpecRows({super.key, required this.rows, required this.count, required this.columnWidth, this.maxRows});

  final List<CompareRow> rows;
  final int count;
  final double columnWidth;
  final int? maxRows;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final shown = maxRows == null ? rows : rows.take(maxRows!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var r = 0; r < shown.length; r++)
          Container(
            decoration: BoxDecoration(
              color: r.isEven ? colors.surfaceVariant.withValues(alpha: 0.5) : null,
              border: Border(top: BorderSide(color: colors.border.withValues(alpha: 0.6))),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: Text(
                    shown[r].label.toUpperCase(),
                    style: t.labelSmall!.copyWith(color: colors.muted, letterSpacing: 0.6, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < count; i++)
                        SizedBox(
                          width: columnWidth,
                          child: _ValueCell(
                            value: i < shown[r].values.length ? shown[r].values[i] : '—',
                            best: shown[r].bestIndex == i,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ValueCell extends StatelessWidget {
  const _ValueCell({required this.value, required this.best});

  final String value;
  final bool best;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final text = value.trim().isEmpty ? '—' : value;
    return Semantics(
      label: best ? '$text, best' : text,
      excludeSemantics: true,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: best
            ? BoxDecoration(
                color: colors.primarySoft,
                borderRadius: AppRadii.inputAll,
                border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                text,
                style: t.bodyMedium!.copyWith(
                  fontWeight: best ? FontWeight.w700 : FontWeight.w400,
                  color: best ? colors.primary : colors.text,
                ),
              ),
            ),
            if (best) Icon(Icons.verified_rounded, size: 16, color: colors.primary),
          ],
        ),
      ),
    );
  }
}

/// Simple non-sticky table (chat cards): header + rows in one horizontal scroll.
class CompareTable extends StatelessWidget {
  const CompareTable({super.key, required this.result, this.maxRows, this.onOpen});

  final CompareResult result;
  final int? maxRows;
  final ValueChanged<ProductSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final n = result.products.length;
    return LayoutBuilder(
      builder: (context, c) {
        final colW = compareColumnWidth(c.maxWidth, n, min: 132);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: colW * n,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CompareHeaderRow(products: result.products, columnWidth: colW, onOpen: onOpen, imageSize: 52),
                CompareSpecRows(rows: result.rows, count: n, columnWidth: colW, maxRows: maxRows),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Visual style of a verdict pick label.
({IconData icon, Color color}) verdictStyle(AppPalette colors, String label) {
  final l = label.toLowerCase();
  if (l.contains('value')) return (icon: Icons.savings_outlined, color: colors.primary);
  if (l.contains('rated')) return (icon: Icons.star_rounded, color: colors.star);
  if (l.contains('budget')) return (icon: Icons.account_balance_wallet_outlined, color: colors.warning);
  if (l.contains('premium')) return (icon: Icons.diamond_outlined, color: colors.secondary);
  return (icon: Icons.emoji_events_outlined, color: colors.ai);
}

/// Verdict cards: Best value / Top rated / Budget / Premium with reasons.
class VerdictCards extends StatelessWidget {
  const VerdictCards({super.key, required this.result, this.onOpen});

  final CompareResult result;
  final ValueChanged<ProductSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final picks = result.picks;
    if (picks.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 2 : 1);
        final w = (c.maxWidth - AppSpacing.sm * (cols - 1)) / cols;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < picks.length; i++)
              SizedBox(
                width: w,
                child: SlideFadeIn(
                  delay: Duration(milliseconds: 80 * i),
                  child: _VerdictCard(pick: picks[i], product: result.productById(picks[i].productId), onOpen: onOpen),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VerdictCard extends StatelessWidget {
  const _VerdictCard({required this.pick, required this.product, this.onOpen});

  final VerdictPick pick;
  final ProductSummary? product;
  final ValueChanged<ProductSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final style = verdictStyle(colors, pick.label);
    final p = product;
    return Material(
      color: Color.alphaBlend(style.color.withValues(alpha: context.isDark ? 0.14 : 0.07), colors.surface),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadii.cardAll,
        side: BorderSide(color: style.color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: AppRadii.cardAll,
        onTap: p == null || onOpen == null ? null : () => onOpen!(p),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: style.color.withValues(alpha: 0.16), shape: BoxShape.circle),
                    child: Icon(style.icon, size: 16, color: style.color),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(pick.label, style: t.labelLarge!.copyWith(color: style.color, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              if (p != null) ...[
                AppSpacing.gapXs,
                Row(
                  children: [
                    AppNetworkImage(p.thumbnail, width: 36, height: 36, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(child: Text(p.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
              if (pick.reason.isNotEmpty) ...[
                AppSpacing.gapXs,
                Text(pick.reason, style: t.bodySmall!.copyWith(color: colors.text, height: 1.4)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
