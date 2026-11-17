import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';
import 'editorial.dart';

/// Section title row: bold title on the left, a blue "See all" link on the
/// right (the reference's "Popular Products ··· See All"), with an optional
/// eyebrow, subtitle and leading widget.
///
/// ```dart
/// SectionHeader(title: 'Trending now', onSeeAll: () => context.push(Routes.productList(sort: 'popular')))
/// SectionHeader(title: 'Picked for you', leading: AiSparkleIcon(), subtitle: 'Based on your interests')
/// SectionHeader(title: 'Filters', serif: false)   // smaller utility heading (sheets, forms)
/// ```
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.onSeeAll,
    this.actionLabel = 'See all',
    this.padding = EdgeInsets.zero,
    this.eyebrow,
    this.index,
    this.serif = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final VoidCallback? onSeeAll;
  final String actionLabel;
  final EdgeInsetsGeometry padding;

  /// Optional small uppercase label above the title. Use sparingly.
  final String? eyebrow;

  /// Legacy section number (no longer drawn).
  final int? index;

  /// Section-size title (default, 19 px bold). False = utility heading
  /// (16 px) for sheets and forms. (Named for the old serif voice.)
  final bool serif;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final hasEyebrow = eyebrow != null && eyebrow!.isNotEmpty;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: hasEyebrow || subtitle != null ? CrossAxisAlignment.end : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasEyebrow) ...[
                  Eyebrow(eyebrow!),
                  const SizedBox(height: 4),
                ],
                Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.xs)],
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: serif ? t.titleLarge!.copyWith(fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -0.3) : t.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: t.bodySmall!.copyWith(fontSize: 13, color: colors.muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: ButtonStyle(
                foregroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed) ? colors.primaryHover : colors.primary,
                ),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.xs)),
                minimumSize: const WidgetStatePropertyAll(Size(44, 36)),
                textStyle: WidgetStatePropertyAll(t.labelLarge!.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
              child: Text(actionLabel, semanticsLabel: '$actionLabel $title'),
            ),
        ],
      ),
    );
  }
}
