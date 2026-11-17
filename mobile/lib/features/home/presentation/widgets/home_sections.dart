import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/category_icons.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../catalog/data/models/catalog_models.dart';
import '../../../catalog/presentation/widgets/accent.dart';

/// Live "Ends in 02:14:09" pill for flash deals; stops at zero.
class DealCountdown extends StatefulWidget {
  const DealCountdown({super.key, required this.endsAt});

  final DateTime endsAt;

  @override
  State<DealCountdown> createState() => _DealCountdownState();
}

class _DealCountdownState extends State<DealCountdown> {
  Timer? _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void didUpdateWidget(DealCountdown old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt) _tick();
  }

  void _tick() {
    final left = widget.endsAt.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _left = left.isNegative ? Duration.zero : left);
    if (left.isNegative) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    String two(int n) => n.toString().padLeft(2, '0');
    final ended = _left == Duration.zero;
    final h = _left.inHours;
    final text = ended ? 'Ended' : '${two(h)}:${two(_left.inMinutes % 60)}:${two(_left.inSeconds % 60)}';

    return Semantics(
      label: ended ? 'Deals ended' : 'Ends in $h hours ${_left.inMinutes % 60} minutes',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: colors.sale.withValues(alpha: context.isDark ? 0.2 : 0.1), borderRadius: AppRadii.pillAll),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: 14, color: colors.sale),
            const SizedBox(width: 4),
            Text(
              ended ? text : 'Ends in $text',
              style: t.labelMedium!.copyWith(
                color: colors.sale,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Departments as colourful icon tiles — a scrolling strip on phones,
/// a wrapping row on wide screens.
class DepartmentTiles extends StatelessWidget {
  const DepartmentTiles({super.key, required this.departments});

  final List<Department> departments;

  @override
  Widget build(BuildContext context) {
    final tiles = [for (final d in departments) _DepartmentTile(department: d)];
    if (context.isWide) {
      return Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: tiles);
    }
    return SizedBox(
      height: 92 + MediaQuery.textScalerOf(context).scale(32),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
        itemCount: tiles.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) => tiles[i],
      ),
    );
  }
}

class _DepartmentTile extends StatefulWidget {
  const _DepartmentTile({required this.department});

  final Department department;

  @override
  State<_DepartmentTile> createState() => _DepartmentTileState();
}

class _DepartmentTileState extends State<_DepartmentTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.department;
    final tint = AccentTint.department(context, d.slug);
    final t = context.textTheme;

    return SizedBox(
      width: context.isWide ? 132 : 84,
      child: Semantics(
        button: true,
        label: '${d.name}, ${d.productCount} products',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: AppRadii.cardAll,
          onHover: (v) => setState(() => _hovered = v),
          onTap: () => context.push(Routes.productList(department: d.slug, title: d.name)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: context.motion(AppDurations.normal),
                  curve: AppCurves.standard,
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: tint.background,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _hovered ? tint.foreground.withValues(alpha: 0.5) : Colors.transparent),
                  ),
                  child: Icon(CategoryIcons.of(d.icon ?? d.slug), size: 28, color: tint.foreground),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  d.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium!.copyWith(height: 1.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DepartmentTilesSkeleton extends StatelessWidget {
  const DepartmentTilesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92 + MediaQuery.textScalerOf(context).scale(32),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
        itemCount: 7,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, _) => const SizedBox(
          width: 84,
          child: Column(
            children: [
              SizedBox(height: AppSpacing.xs),
              Skeleton(width: 64, height: 64, borderRadius: BorderRadius.all(Radius.circular(20))),
              SizedBox(height: AppSpacing.xs),
              Skeleton(width: 56, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// AI shortcuts under the prompt bar.
class QuickActions extends StatelessWidget {
  const QuickActions({super.key, required this.onCompare});

  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context) {
    final actions = [
      (Icons.photo_camera_outlined, 'Snap & Find', 'Search with a photo', () => context.push(Routes.visualSearch)),
      (Icons.auto_awesome_mosaic_outlined, 'Bundle Builder', 'Complete the set', () => context.push(Routes.bundleBuilder)),
      (Icons.quiz_outlined, 'Guided Finder', 'Answer, get picks', () => context.push(Routes.finder)),
      (Icons.compare_arrows_rounded, 'Compare', 'Side by side', onCompare),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        const gap = AppSpacing.sm;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final a in actions)
              SizedBox(
                width: width,
                child: _QuickAction(icon: a.$1, title: a.$2, subtitle: a.$3, onTap: a.$4),
              ),
          ],
        );
      },
    );
  }
}

class _QuickAction extends StatefulWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_QuickAction> createState() => _QuickActionState();
}

class _QuickActionState extends State<_QuickAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return AnimatedScale(
      scale: _pressed && !context.reduceMotion ? 0.97 : 1,
      duration: AppDurations.fast,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: _hovered ? colors.text.withValues(alpha: 0.4) : colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onHover: (v) => setState(() => _hovered = v),
          onHighlightChanged: (v) => setState(() => _pressed = v),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
                  child: Icon(widget.icon, size: 20, color: colors.text),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                      Text(widget.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
