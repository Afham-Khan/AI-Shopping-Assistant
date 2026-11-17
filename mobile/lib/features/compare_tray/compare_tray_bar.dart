import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/extensions.dart';
import '../../core/widgets/widgets.dart';
import 'compare_tray_provider.dart';

/// Docked "Compare (n)" bar with the picked thumbnails. Renders nothing when
/// the tray is empty and expands in/out as items are added.
///
/// Put it in a screen's `bottomNavigationBar` slot (stack it above any sticky
/// action bar with a Column).
class CompareTrayBar extends ConsumerWidget {
  const CompareTrayBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(compareTrayProvider);
    final colors = context.colors;
    final t = context.textTheme;

    Widget bar() => DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: context.pagePadding, vertical: AppSpacing.xs),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Breakpoints.maxContent),
              child: Row(
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < CompareTrayController.maxItems; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: AppSpacing.xs),
                              child: i < items.length
                                  ? _Thumb(
                                      url: items[i].thumbnail,
                                      label: items[i].title,
                                      onRemove: () => ref.read(compareTrayProvider.notifier).remove(items[i].id),
                                    )
                                  : const _EmptySlot(),
                            ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Clear compare',
                    onPressed: () => ref.read(compareTrayProvider.notifier).clear(),
                    icon: Icon(Icons.close_rounded, size: 20, color: colors.muted),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  AppButton(
                    label: items.length < 2 ? 'Add 1 more' : 'Compare (${items.length})',
                    icon: Icons.compare_arrows_rounded,
                    size: AppButtonSize.small,
                    onPressed: items.length < 2
                        ? null
                        : () => context.push(Routes.compareOf(ref.read(compareTrayProvider.notifier).ids)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedSize(
      duration: context.motion(AppDurations.normal),
      curve: AppCurves.standard,
      alignment: Alignment.topCenter,
      child: items.isEmpty
          ? const SizedBox(width: double.infinity)
          : Semantics(
              container: true,
              label: '${items.length} of ${CompareTrayController.maxItems} products selected to compare',
              child: DefaultTextStyle.merge(style: t.bodyMedium, child: bar()),
            ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url, required this.label, required this.onRemove});

  final String? url;
  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: 'Remove $label',
      child: InkWell(
        onTap: onRemove,
        borderRadius: AppRadii.inputAll,
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: AppRadii.inputAll,
            border: Border.all(color: colors.border),
          ),
          child: AppNetworkImage(url, fit: BoxFit.contain, backgroundColor: Colors.transparent, semanticLabel: label),
        ),
      ),
    );
  }
}

class _EmptySlot extends StatelessWidget {
  const _EmptySlot();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: AppRadii.inputAll,
        border: Border.all(color: colors.border),
      ),
      child: Icon(Icons.add_rounded, size: 16, color: colors.muted),
    );
  }
}
