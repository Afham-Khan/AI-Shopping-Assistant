import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../discover/presentation/widgets/discover_entry_card.dart';
import '../data/models/catalog_models.dart';
import '../providers/catalog_providers.dart';
import 'widgets/accent.dart';

/// Departments and their categories. Two panes from 900 px (department list
/// left, categories right); department pills above the grid on phones.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final departments = ref.watch(departmentsProvider);
    final twoPane = context.screenWidth >= 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => context.push(Routes.search),
            icon: const Icon(Icons.search_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: switch (departments) {
        AsyncValue(:final value?) when value.isEmpty => const EmptyState(
          icon: Icons.category_outlined,
          title: 'No departments yet',
          message: 'The catalog is empty right now.',
        ),
        AsyncValue(:final value?) => _body(value, twoPane),
        AsyncValue(:final error?) => ErrorState(error: error, onRetry: () => ref.invalidate(departmentsProvider)),
        _ => _ExploreSkeleton(twoPane: twoPane),
      },
    );
  }

  Widget _body(List<Department> list, bool twoPane) {
    final index = _selected.clamp(0, list.length - 1);
    final dept = list[index];
    void select(int i) => setState(() => _selected = i);

    if (twoPane) {
      return ResponsiveCenter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 260,
              child: ListView.separated(
                padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xl),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 2),
                itemBuilder: (context, i) =>
                    _DepartmentListItem(department: list[i], selected: i == index, onTap: () => select(i)),
              ),
            ),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: AnimatedSwitcher(
                duration: context.motion(AppDurations.normal),
                child: _CategoryPane(key: ValueKey(dept.id), department: dept),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(context.pagePadding, 0, context.pagePadding, AppSpacing.sm),
          child: const DiscoverEntryCard(compact: true),
        ),
        SizedBox(
          height: 44 + MediaQuery.textScalerOf(context).scale(8),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, i) => _DepartmentPill(department: list[i], selected: i == index, onTap: () => select(i)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: AnimatedSwitcher(
            duration: context.motion(AppDurations.normal),
            child: Padding(
              key: ValueKey(dept.id),
              padding: EdgeInsets.symmetric(horizontal: context.pagePadding),
              child: _CategoryPane(department: dept),
            ),
          ),
        ),
      ],
    );
  }
}

class _DepartmentPill extends StatelessWidget {
  const _DepartmentPill({required this.department, required this.selected, required this.onTap});

  final Department department;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = AccentTint.department(context, department.slug);
    final t = context.textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? tint.background : context.colors.surface,
        shape: StadiumBorder(side: BorderSide(color: selected ? tint.foreground : context.colors.border)),
        child: InkWell(
          borderRadius: AppRadii.pillAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CategoryIcons.of(department.icon ?? department.slug),
                  size: 18,
                  color: tint.foreground,
                ),
                const SizedBox(width: 6),
                Text(department.name, style: t.labelLarge),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DepartmentListItem extends StatelessWidget {
  const _DepartmentListItem({required this.department, required this.selected, required this.onTap});

  final Department department;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tint = AccentTint.department(context, department.slug);
    final colors = context.colors;
    final t = context.textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.surfaceVariant : Colors.transparent,
        borderRadius: AppRadii.cardAll,
        child: InkWell(
          borderRadius: AppRadii.cardAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: tint.background, borderRadius: AppRadii.inputAll),
                  child: Icon(
                    CategoryIcons.of(department.icon ?? department.slug),
                    size: 20,
                    color: tint.foreground,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        department.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall!.copyWith(color: colors.text),
                      ),
                      Text(Formatters.plural(department.productCount, 'product'), style: t.bodySmall),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.chevron_right_rounded, color: colors.text),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Department header + its category grid.
class _CategoryPane extends StatelessWidget {
  const _CategoryPane({super.key, required this.department});

  final Department department;

  @override
  Widget build(BuildContext context) {
    final d = department;
    final tint = AccentTint.department(context, d.slug);
    final t = context.textTheme;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(color: tint.background, borderRadius: AppRadii.sheetAll),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(d.name, style: t.headlineSmall),
                      ),
                      if (d.description != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(d.description!, style: t.bodyMedium!.copyWith(color: context.colors.muted)),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Shop all ${Formatters.number(d.productCount)}',
                        trailingIcon: Icons.arrow_forward_rounded,
                        size: AppButtonSize.small,
                        onPressed: () => context.push(Routes.productList(department: d.slug, title: d.name)),
                      ),
                    ],
                  ),
                ),
                if (context.screenWidth >= 420 && d.imageUrl != null) ...[
                  const SizedBox(width: AppSpacing.md),
                  AppNetworkImage(d.imageUrl, width: 96, height: 96, fit: BoxFit.contain, backgroundColor: Colors.transparent),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
            child: Text('Categories', style: t.titleMedium),
          ),
        ),
        SliverLayoutBuilder(
          builder: (context, c) {
            final width = c.crossAxisExtent;
            final columns = width < 520 ? 2 : (width < 820 ? 3 : 4);
            final tile = (width - AppSpacing.sm * (columns - 1)) / columns;
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: AppSpacing.sm,
                mainAxisSpacing: AppSpacing.sm,
                mainAxisExtent: tile * 0.75 + MediaQuery.textScalerOf(context).scale(52),
              ),
              itemCount: d.categories.length,
              itemBuilder: (context, i) => _CategoryCard(category: d.categories[i], tint: tint),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),
      ],
    );
  }
}

class _CategoryCard extends StatefulWidget {
  const _CategoryCard({required this.category, required this.tint});

  final CategorySummary category;
  final AccentTint tint;

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.category;
    final t = context.textTheme;
    final colors = context.colors;
    return Semantics(
      button: true,
      label: '${c.name}, ${c.productCount} products',
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: _hovered ? colors.text.withValues(alpha: 0.4) : colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onHover: (v) => setState(() => _hovered = v),
          onTap: () => context.push(Routes.productList(category: c.slug, title: c.name)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(
                  color: widget.tint.background,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      AnimatedScale(
                        scale: _hovered && !context.reduceMotion ? 1.06 : 1,
                        duration: AppDurations.normal,
                        curve: AppCurves.standard,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          child: AppNetworkImage(
                            c.imageUrl,
                            fit: BoxFit.contain,
                            backgroundColor: Colors.transparent,
                            fallbackIcon: CategoryIcons.of(c.slug),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                    Text(Formatters.plural(c.productCount, 'item'), style: t.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExploreSkeleton extends StatelessWidget {
  const _ExploreSkeleton({required this.twoPane});

  final bool twoPane;

  @override
  Widget build(BuildContext context) {
    final grid = GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 140),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        crossAxisSpacing: AppSpacing.sm,
        mainAxisSpacing: AppSpacing.sm,
      ),
      itemCount: 6,
      itemBuilder: (_, _) => const Skeleton(borderRadius: AppRadii.cardAll),
    );
    return ResponsiveCenter(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (twoPane) ...[
            const SizedBox(width: 260, child: SkeletonList(count: 7)),
            const SizedBox(width: AppSpacing.xl),
          ],
          Expanded(
            child: Stack(
              children: [
                const Skeleton(height: 124, borderRadius: AppRadii.sheetAll),
                grid,
              ],
            ),
          ),
        ],
      ),
    );
  }
}
