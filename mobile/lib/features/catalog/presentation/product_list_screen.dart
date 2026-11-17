import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../compare_tray/compare_tray_bar.dart';
import '../data/models/catalog_models.dart';
import '../data/models/product_query.dart';
import '../providers/catalog_providers.dart';
import 'widgets/product_filter_sheets.dart';

/// Products for a category / department / brand / search query, with sort,
/// filters (facets from the API), grid/list toggle and infinite scroll.
class ProductListScreen extends ConsumerStatefulWidget {
  const ProductListScreen({
    super.key,
    this.category,
    this.department,
    this.brand,
    this.q,
    this.sort,
    this.onSale = false,
    this.title,
  });

  final String? category;
  final String? department;
  final String? brand;
  final String? q;
  final String? sort;
  final bool onSale;
  final String? title;

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  late ProductQuery _query = _initialQuery();
  bool _grid = true;

  /// Facets of the last successful load, so the filter sheet works while a new query loads.
  ProductFacets _facets = const ProductFacets();

  /// Last results shown, kept (dimmed) while a new sort/filter loads.
  ProductListState? _last;

  ProductQuery _initialQuery() => ProductQuery(
    q: widget.q,
    category: widget.category,
    department: widget.department,
    brands: [
      for (final b in (widget.brand ?? '').split(','))
        if (b.trim().isNotEmpty) b.trim(),
    ],
    onSale: widget.onSale,
    sort: ProductSort.parse(widget.sort),
  );

  @override
  void didUpdateWidget(ProductListScreen old) {
    super.didUpdateWidget(old);
    if (old.q != widget.q ||
        old.category != widget.category ||
        old.department != widget.department ||
        old.brand != widget.brand ||
        old.sort != widget.sort ||
        old.onSale != widget.onSale) {
      _query = _initialQuery();
    }
  }

  String get _title {
    if (widget.title != null) return widget.title!;
    if (widget.q != null) return '"${widget.q}"';
    final scope = widget.category ?? widget.department ?? widget.brand;
    return scope?.titleCase ?? 'All products';
  }

  void _setQuery(ProductQuery q) => setState(() => _query = q);

  Future<void> _openSort() async {
    final sort = await showSortSheet(context, query: _query);
    if (sort != null) _setQuery(_query.copyWith(sort: () => sort));
  }

  Future<void> _openFilters() async {
    final next = await showFilterSheet(context, query: _query, facets: _facets);
    if (next != null) _setQuery(next);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 800) {
      ref.read(productListProvider(_query).notifier).loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productListProvider(_query));
    final data = async.value;
    if (data != null && !async.isLoading) {
      _facets = data.facets;
      _last = data;
    }
    final shownData = data ?? (async.isLoading ? _last : null);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => context.push(Routes.searchWith(q: widget.q)),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: _grid ? 'Show as list' : 'Show as grid',
            onPressed: () => setState(() => _grid = !_grid),
            icon: AnimatedSwitcher(
              duration: context.motion(AppDurations.fast),
              child: Icon(
                _grid ? Icons.view_agenda_outlined : Icons.grid_view_rounded,
                key: ValueKey(_grid),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      bottomNavigationBar: const CompareTrayBar(),
      body: Column(
        children: [
          ResponsiveCenter(
            child: _Toolbar(
              query: _query,
              total: shownData?.total,
              shown: shownData?.items.length ?? 0,
              onSort: _openSort,
              onFilter: _openFilters,
            ),
          ),
          if (_query.activeFilterCount > 0)
            _ActiveFilters(query: _query, onChanged: _setQuery),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: RefreshIndicator(
                onRefresh: () async {
                  try {
                    ref.invalidate(productListProvider(_query));
                    await ref.read(productListProvider(_query).future);
                  } catch (_) {}
                },
                child: _results(async),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results(AsyncValue<ProductListState> async) {
    final fresh = async.isLoading && !async.isRefreshing ? null : async.value;
    // a new sort/filter keeps the previous results on screen, dimmed
    final stale = fresh == null && async.isLoading ? _last : null;
    final data = fresh ?? stale;

    if (data == null) {
      if (async.hasError && !async.isLoading) {
        return _Scrollable(
          child: ErrorState(error: async.error, onRetry: () => ref.invalidate(productListProvider(_query))),
        );
      }
      return CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverResponsiveCenter(
            verticalPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            sliver: _grid
                ? const SliverProductGrid.loading()
                : SliverList.builder(itemCount: 6, itemBuilder: (_, _) => const SkeletonListTile(leadingSize: 104)),
          ),
        ],
      );
    }

    if (data.items.isEmpty) return _Scrollable(child: _empty());

    final notifier = ref.read(productListProvider(_query).notifier);
    final list = CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (_query.q != null)
          SliverResponsiveCenter(
            sliver: SliverToBoxAdapter(child: _SmartSearchHint(query: _query.q!, relaxed: data.relaxedSearch)),
          ),
        SliverResponsiveCenter(
          verticalPadding: const EdgeInsets.only(top: AppSpacing.sm),
          sliver: _grid
              ? SliverProductGrid(products: data.items, loadingMore: data.loadingMore)
              : SliverList.separated(
                  itemCount: data.items.length + (data.loadingMore ? 2 : 0),
                  separatorBuilder: (_, _) => const Divider(height: AppSpacing.md),
                  itemBuilder: (context, i) => i < data.items.length
                      ? ProductCard(product: data.items[i], variant: ProductCardVariant.wide)
                      : const SkeletonListTile(leadingSize: 104),
                ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(
              child: data.loadMoreError != null
                  ? AppButton.secondary(
                      label: 'Couldn\'t load more — retry',
                      icon: Icons.refresh_rounded,
                      size: AppButtonSize.small,
                      onPressed: notifier.loadMore,
                    )
                  : (!data.hasMore && data.items.length > 8)
                  ? Text("You've reached the end", style: context.textTheme.bodySmall)
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      ],
    );
    if (stale == null) return list;
    return Stack(
      children: [
        IgnorePointer(
          child: AnimatedOpacity(opacity: 0.45, duration: context.motion(AppDurations.fast), child: list),
        ),
        const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
      ],
    );
  }

  Widget _empty() {
    final ask = _query.q ?? widget.title ?? _title;
    final hasFilters = _query.activeFilterCount > 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No products found',
          message: hasFilters
              ? 'Nothing matches these filters. Remove some, or describe what you want to Zel.'
              : "No match yet. Describe it to Zel, our AI assistant.",
          actionLabel: hasFilters ? 'Clear filters' : null,
          onAction: hasFilters ? () => _setQuery(_query.clearFilters()) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: _AskAiButton(onTap: () => context.go(Routes.assistantWith(prompt: 'Help me find $ask'))),
        ),
      ],
    );
  }
}

/// Lets empty/error states be pulled to refresh.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _AskAiButton extends StatelessWidget {
  const _AskAiButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(label: 'Ask Zel instead', icon: Icons.auto_awesome_outlined, onPressed: onTap);
  }
}

class _SmartSearchHint extends StatelessWidget {
  const _SmartSearchHint({required this.query, required this.relaxed});

  final String query;
  final bool relaxed;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Material(
        color: context.colors.aiSoft,
        borderRadius: AppRadii.cardAll,
        child: InkWell(
          borderRadius: AppRadii.cardAll,
          onTap: () => context.push(Routes.smartSearchOf(query)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              children: [
                const AiSparkleIcon(size: 18),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    relaxed
                        ? 'Showing close matches. Try Smart AI search for "$query".'
                        : 'Describe it naturally? Try Smart AI search.',
                    style: t.bodySmall!.copyWith(color: context.colors.text),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.colors.ai),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.query,
    required this.total,
    required this.shown,
    required this.onSort,
    required this.onFilter,
  });

  final ProductQuery query;
  final int? total;
  final int shown;
  final VoidCallback onSort;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final filters = query.activeFilterCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: AnimatedSwitcher(
              duration: context.motion(AppDurations.fast),
              child: total == null
                  ? const Align(alignment: Alignment.centerLeft, child: Skeleton(width: 80, height: 12))
                  : Text(
                      total == 0
                          ? 'No results'
                          : '1–${Formatters.number(shown)} of ${Formatters.plural(total!, 'result')}',
                      key: ValueKey('$shown/$total'),
                      style: t.bodyMedium!.copyWith(color: colors.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
          _ToolButton(
            icon: Icons.swap_vert_rounded,
            label: query.effectiveSort.label,
            onTap: onSort,
            semantic: 'Sort, currently ${query.effectiveSort.label}',
          ),
          const SizedBox(width: AppSpacing.xs),
          _ToolButton(
            icon: Icons.tune_rounded,
            label: 'Filter',
            onTap: onFilter,
            badge: filters,
            semantic: filters > 0 ? 'Filters, $filters active' : 'Filters',
          ),
        ],
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.label, required this.onTap, required this.semantic, this.badge = 0});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String semantic;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final active = badge > 0;
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Material(
        color: active ? colors.primarySoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.pillAll,
          side: BorderSide(color: active ? colors.primary.withValues(alpha: 0.4) : colors.border),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 40, maxWidth: context.screenWidth < 380 ? 130 : 220),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: active ? colors.primary : colors.text),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelLarge!.copyWith(color: active ? colors.primary : colors.text),
                    ),
                  ),
                  if (active) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadii.pillAll),
                      child: Text('$badge', style: context.textTheme.labelSmall!.copyWith(color: colors.onPrimary)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.query, required this.onChanged});

  final ProductQuery query;
  final ValueChanged<ProductQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final q = query;
    final chips = <(String, ProductQuery)>[
      for (final b in q.brands) (b, q.copyWith(brands: [...q.brands]..remove(b))),
      if (q.hasPrice)
        (
          q.minPrice != null && q.maxPrice != null
              ? '${Formatters.priceCompact(q.minPrice)} – ${Formatters.priceCompact(q.maxPrice)}'
              : q.minPrice != null
              ? 'From ${Formatters.priceCompact(q.minPrice)}'
              : 'Up to ${Formatters.priceCompact(q.maxPrice)}',
          q.copyWith(minPrice: () => null, maxPrice: () => null),
        ),
      if (q.minRating != null) ('${q.minRating!.toInt()}★ & up', q.copyWith(minRating: () => null)),
      if (q.inStock) ('In stock', q.copyWith(inStock: false)),
      if (q.onSale) ('On sale', q.copyWith(onSale: false)),
    ];
    final colors = context.colors;

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(
          horizontal: SliverResponsiveCenter.sidePadding(context, context.screenWidth),
          vertical: 4,
        ),
        children: [
          for (final (label, next) in chips)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: InputChip(
                label: Text(label),
                selected: true,
                onPressed: () => onChanged(next),
                onDeleted: () => onChanged(next),
                deleteIcon: Icon(Icons.close_rounded, size: 16, color: colors.onPrimary),
                deleteButtonTooltipMessage: 'Remove $label',
              ),
            ),
          TextButton(
            onPressed: () => onChanged(q.clearFilters()),
            style: TextButton.styleFrom(foregroundColor: colors.secondary),
            child: const Text('Reset all'),
          ),
        ],
      ),
    );
  }
}
