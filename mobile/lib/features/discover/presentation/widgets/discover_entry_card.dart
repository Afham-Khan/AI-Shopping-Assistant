import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Entry point to Discover (Home and Explore): a fanned little hand of
/// cards next to the pitch.
class DiscoverEntryCard extends StatelessWidget {
  const DiscoverEntryCard({super.key, this.products = const [], this.compact = false});

  /// Up to three products to show as the fanned cards (optional).
  final List<ProductSummary> products;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final thumbs = products.where((p) => p.thumbnail != null).take(3).toList();
    return AppCard(
      onTap: () => context.push(Routes.discover),
      semanticLabel: 'Discover. Swipe to teach Zel your taste',
      padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
      child: Row(
        children: [
          SizedBox(width: compact ? 64 : 92, height: compact ? 64 : 92, child: _Fan(products: thumbs)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AiSparkleIcon(size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'DISCOVER',
                      style: t.labelSmall!.copyWith(color: colors.primary, letterSpacing: 1.1, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Swipe, and Zel learns your taste', style: compact ? t.titleSmall : t.titleMedium),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Like, pass or bag one card at a time. Department stories too.',
                    style: t.bodySmall!.copyWith(color: colors.muted),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.muted),
        ],
      ),
    );
  }
}

class _Fan extends StatelessWidget {
  const _Fan({required this.products});

  final List<ProductSummary> products;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const angles = [-0.22, 0.0, 0.22];
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth * 0.62;
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < 3; i++)
              Transform.rotate(
                angle: angles[i],
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: w,
                  height: w * 1.3,
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: AppRadii.inputAll,
                    border: Border.all(color: colors.border),
                    boxShadow: colors.shadowSm,
                  ),
                  padding: const EdgeInsets.all(3),
                  child: i < products.length
                      ? AppNetworkImage(products[i].thumbnail, fit: BoxFit.contain, borderRadius: AppRadii.tagAll)
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: i == 1 ? colors.primarySoft : colors.imageWell,
                            borderRadius: AppRadii.tagAll,
                          ),
                          child: i == 1 ? Icon(Icons.style_outlined, color: colors.primary, size: w * 0.45) : null,
                        ),
                ),
              ),
          ],
        );
      },
    );
  }
}
