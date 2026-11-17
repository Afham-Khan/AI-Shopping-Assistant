import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';
import '../utils/formatters.dart';

enum PriceSize { small, medium, large }

/// `Rs 45,999` with optional strikethrough compare-at price and discount.
///
/// Hierarchy: the amount is bold with tabular figures in confident navy-blue
/// (`colors.price`), the "Rs" prefix is lighter so the number leads; the old
/// price is struck through and faint; the discount is a small coral tag.
///
/// ```dart
/// PriceText(product.price, compareAt: product.compareAtPrice)
/// PriceText(total, size: PriceSize.large, showDiscount: true, showSavings: true)
/// ```
class PriceText extends StatelessWidget {
  const PriceText(
    this.amount, {
    super.key,
    this.compareAt,
    this.size = PriceSize.medium,
    this.showDiscount = false,
    this.showSavings = false,
    this.singleLine = false,
    this.color,
    this.style,
  });

  final num amount;

  /// Original price; shown struck through only when greater than [amount].
  final num? compareAt;
  final PriceSize size;

  /// Adds a "-10%" tag after the prices.
  final bool showDiscount;

  /// Adds a "You save Rs 4,100" line under the price (detail pages, cart).
  final bool showSavings;

  /// Keep everything on one line, scaling down slightly if needed
  /// (use in fixed-height tiles like product cards).
  final bool singleLine;
  final Color? color;

  /// Overrides the main price style.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;

    final main = (style ??
            switch (size) {
              PriceSize.small => t.titleSmall!.copyWith(fontWeight: FontWeight.w700),
              PriceSize.medium => t.titleMedium!.copyWith(fontWeight: FontWeight.w700),
              // Inter, not the serif: figures stay tabular and crisp
              PriceSize.large => t.titleLarge!.copyWith(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15),
            })
        .copyWith(color: color ?? colors.price, fontFeatures: AppType.tabular);
    final secondary = switch (size) {
      PriceSize.small => t.bodySmall!,
      PriceSize.medium => t.bodySmall!.copyWith(fontSize: 13),
      PriceSize.large => t.bodyLarge!,
    };

    final hasCompare = compareAt != null && compareAt! > amount;
    final percent = hasCompare ? ((compareAt! - amount) / compareAt! * 100).round() : 0;

    final semantics = StringBuffer('Price ${Formatters.price(amount)}');
    if (hasCompare) semantics.write(', was ${Formatters.price(compareAt)}');

    // "Rs" is set lighter and smaller so the amount carries the weight
    final formatted = Formatters.price(amount);
    final split = formatted.indexOf(' ');
    final mainText = Text.rich(
      TextSpan(
        children: split <= 0
            ? [TextSpan(text: formatted)]
            : [
                TextSpan(
                  text: formatted.substring(0, split + 1),
                  style: TextStyle(
                    fontSize: main.fontSize! * 0.78,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                    color: (color ?? colors.price).withValues(alpha: 0.72),
                  ),
                ),
                TextSpan(text: formatted.substring(split + 1)),
              ],
      ),
      maxLines: 1,
      style: main,
    );
    final compareText = hasCompare
        ? Text(
            Formatters.price(compareAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondary.copyWith(
              color: colors.faint,
              decoration: TextDecoration.lineThrough,
              decorationColor: colors.faint,
              fontFeatures: AppType.tabular,
            ),
          )
        : null;
    final discountText = hasCompare && showDiscount && percent > 0
        ? Container(
            padding: EdgeInsets.symmetric(horizontal: size == PriceSize.large ? 7 : 5, vertical: 2),
            decoration: BoxDecoration(color: colors.saleSoft, borderRadius: AppRadii.tagAll),
            child: Text(
              '-$percent%',
              maxLines: 1,
              style: secondary.copyWith(
                fontSize: size == PriceSize.large ? 13 : 11,
                color: colors.sale,
                fontWeight: FontWeight.w700,
                fontFeatures: AppType.tabular,
              ),
            ),
          )
        : null;

    Widget content = singleLine
        // scale the whole row down a touch rather than clipping digits
        ? FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                mainText,
                if (compareText != null) ...[const SizedBox(width: 6), compareText],
                if (discountText != null) ...[const SizedBox(width: 6), discountText],
              ],
            ),
          )
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [mainText, ?compareText, ?discountText],
          );

    if (showSavings && hasCompare && !singleLine) {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 4),
          Text(
            'You save ${Formatters.price(compareAt! - amount)}',
            style: t.bodySmall!.copyWith(color: colors.sale, fontWeight: FontWeight.w600, fontFeatures: AppType.tabular),
          ),
        ],
      );
    }

    return Semantics(label: semantics.toString(), excludeSemantics: true, child: content);
  }
}
