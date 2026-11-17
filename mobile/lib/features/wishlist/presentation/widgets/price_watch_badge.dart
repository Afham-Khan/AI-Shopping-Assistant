import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../providers/price_watch_providers.dart';
import 'watch_price_sheet.dart';

/// Height reserved for [PriceWatchBadge] in a fixed-height grid tile.
double priceWatchBadgeHeight(BuildContext context) => MediaQuery.textScalerOf(context).scale(34) + 12;

/// Wishlist tile status: "Watching · target Rs X" (tap to edit) or a quiet
/// "Watch price" chip (tap to start).
class PriceWatchBadge extends ConsumerWidget {
  const PriceWatchBadge({super.key, required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watch = ref.watch(priceWatchForProvider(product.id));
    final colors = context.colors;
    final t = context.textTheme;
    final watching = watch != null;

    final label = watching ? (watch.hasTarget ? 'Watching' : 'Watching · any drop') : 'Watch price';
    final second = watching && watch.hasTarget ? 'target ${Formatters.price(watch.targetPrice)}' : null;
    final semantics = watching
        ? 'Watching the price of ${product.title}, ${watch.hasTarget ? 'target ${Formatters.price(watch.targetPrice)}' : 'any drop'}. Edit alert'
        : 'Watch the price of ${product.title}';

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        color: watching ? colors.primarySoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.inputAll,
          side: BorderSide(color: watching ? colors.primary.withValues(alpha: 0.3) : colors.border),
        ),
        child: InkWell(
          borderRadius: AppRadii.inputAll,
          onTap: () => showWatchPriceSheet(context, ref, product: product),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: priceWatchBadgeHeight(context)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    watching ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                    size: 16,
                    color: watching ? colors.primary : colors.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelMedium!.copyWith(
                            color: watching ? colors.primary : colors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (second != null)
                          Text(
                            second,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.labelSmall!.copyWith(color: colors.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
