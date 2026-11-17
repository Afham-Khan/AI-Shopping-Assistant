import 'package:material_ui/material_ui.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';

/// Shimmering placeholder block. Fills its parent unless sized.
/// Shimmer is disabled under reduced motion.
///
/// ```dart
/// Skeleton(width: 120, height: 14)
/// Skeleton.circle(size: 40)
/// ```
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height, this.borderRadius = AppRadii.inputAll});

  const Skeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = AppRadii.pillAll;

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final base = colors.surfaceVariant;
    final highlight = colors.surfaceRaised;
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      enabled: !context.reduceMotion,
      period: const Duration(milliseconds: 1600),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: base, borderRadius: borderRadius),
      ),
    );
  }
}

/// Placeholder lines of text. Last line is shorter.
class SkeletonText extends StatelessWidget {
  const SkeletonText({super.key, this.lines = 3, this.lineHeight = 12, this.spacing = 8});

  final int lines;
  final double lineHeight;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < lines; i++) ...[
          if (i > 0) SizedBox(height: spacing),
          FractionallySizedBox(
            widthFactor: i == lines - 1 && lines > 1 ? 0.6 : 1,
            child: Skeleton(height: lineHeight),
          ),
        ],
      ],
    );
  }
}

/// Matches the compact [ProductCard] layout (use inside a ProductGrid slot).
class SkeletonProductCard extends StatelessWidget {
  const SkeletonProductCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    // same shell as the real card (surface + hairline), so nothing jumps on load
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: colors.border),
      ),
      child: const Padding(
        padding: EdgeInsets.all(1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Skeleton(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card - 1))),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(10, 12, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Skeleton(width: 52, height: 9, borderRadius: AppRadii.tagAll),
                  SizedBox(height: AppSpacing.xs),
                  Skeleton(height: 11, borderRadius: AppRadii.tagAll),
                  SizedBox(height: 6),
                  Skeleton(width: 92, height: 11, borderRadius: AppRadii.tagAll),
                  SizedBox(height: AppSpacing.sm),
                  Skeleton(width: 76, height: 14, borderRadius: AppRadii.tagAll),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Matches a list row with a leading thumbnail.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key, this.leadingSize = 56, this.circleLeading = false});

  final double leadingSize;
  final bool circleLeading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          circleLeading
              ? Skeleton.circle(size: leadingSize)
              : Skeleton(width: leadingSize, height: leadingSize),
          const SizedBox(width: AppSpacing.md),
          const Expanded(child: SkeletonText(lines: 2)),
        ],
      ),
    );
  }
}

/// A vertical list of [SkeletonListTile]s for loading states.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.circleLeading = false});

  final int count;
  final bool circleLeading;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: count,
      itemBuilder: (_, _) => SkeletonListTile(circleLeading: circleLeading),
    );
  }
}
