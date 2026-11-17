import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';
import 'editorial.dart';

/// Section title in the editorial serif, with an optional mono eyebrow,
/// subtitle, leading widget and "See all" action.
///
/// ```dart
/// SectionHeader(title: 'Trending now', eyebrow: 'This week', index: 2,
///     onSeeAll: () => context.push(Routes.productList(sort: 'popular')))
/// SectionHeader(title: 'Picked for you', leading: AiSparkleIcon(), subtitle: 'Based on your interests')
/// SectionHeader(title: 'Filters', serif: false)   // plain UI heading
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

  /// Small uppercase label above the title ("THIS WEEK", "FOR YOU").
  final String? eyebrow;

  /// Section number shown before the eyebrow ("02 — THIS WEEK").
  final int? index;

  /// Serif display title (default). Use false for utility headings inside
  /// sheets and forms.
  final bool serif;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow != null || index != null) ...[
                  Eyebrow(eyebrow ?? '', index: index),
                  const SizedBox(height: 6),
                ],
                Row(
                  children: [
                    if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.xs)],
                    Flexible(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: serif ? t.headlineSmall!.copyWith(fontSize: 21) : t.titleLarge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: t.bodySmall!.copyWith(fontSize: 13),
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
                // muted at rest, accent on hover: the link earns its color
                foregroundColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.hovered) || s.contains(WidgetState.focused) ? colors.primary : colors.muted,
                ),
                padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.xs)),
                minimumSize: const WidgetStatePropertyAll(Size(44, 36)),
                textStyle: WidgetStatePropertyAll(t.labelLarge!.copyWith(fontSize: 13)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel, semanticsLabel: '$actionLabel $title'),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 15),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
