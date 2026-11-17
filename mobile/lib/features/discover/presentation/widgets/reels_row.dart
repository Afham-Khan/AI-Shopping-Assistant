import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/discover_models.dart';

/// Department story circles. A coloured ring marks stories not opened yet.
class ReelsRow extends StatelessWidget {
  const ReelsRow({super.key, required this.reels, required this.seen, required this.onOpen});

  final List<DiscoverReel> reels;
  final Set<String> seen;
  final ValueChanged<int> onOpen;

  static double heightOf(BuildContext context) => 84 + MediaQuery.textScalerOf(context).scale(16);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: heightOf(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
        itemCount: reels.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) => _ReelCircle(reel: reels[i], seen: seen.contains(reels[i].slug), onTap: () => onOpen(i)),
      ),
    );
  }

  static Widget loading(BuildContext context) => SizedBox(
    height: heightOf(context),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
      itemBuilder: (_, _) => const Column(
        children: [
          Skeleton.circle(size: 64),
          SizedBox(height: 6),
          Skeleton(width: 48, height: 10),
        ],
      ),
    ),
  );
}

class _ReelCircle extends StatelessWidget {
  const _ReelCircle({required this.reel, required this.seen, required this.onTap});

  final DiscoverReel reel;
  final bool seen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hue = colors.departmentAccent(reel.slug);
    final cover = reel.cover;
    return SizedBox(
      width: 68,
      child: Semantics(
        button: true,
        label: '${reel.department} story${seen ? ', seen' : ''}',
        excludeSemantics: true,
        child: Pressable(
          child: GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Column(
              children: [
                Container(
                  width: 66,
                  height: 66,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: seen ? colors.border : hue, width: 2.5),
                  ),
                  child: ClipOval(
                    child: AppNetworkImage(cover, fit: BoxFit.contain, fallbackIcon: Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  reel.department.split(RegExp(r'\s*&\s*|\s+')).first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.labelSmall!.copyWith(color: seen ? colors.muted : colors.text),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
