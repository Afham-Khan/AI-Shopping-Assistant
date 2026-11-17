import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/catalog_models.dart';
import '../../data/models/product_query.dart';

/// Opens the sort picker; resolves to the chosen sort (null if dismissed).
Future<ProductSort?> showSortSheet(BuildContext context, {required ProductQuery query}) {
  final hasQ = query.q?.isNotEmpty ?? false;
  final options = [for (final s in ProductSort.values) if (s != ProductSort.relevance || hasQ) s];
  return showAppBottomSheet<ProductSort>(
    context,
    builder: (context) => BottomSheetScaffold(
      title: 'Sort by',
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: RadioGroup<ProductSort>(
        groupValue: query.effectiveSort,
        onChanged: (s) => Navigator.of(context).pop(s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final s in options)
              RadioListTile<ProductSort>(
                value: s,
                title: Text(s.label),
                contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Opens the filter sheet; resolves to the new query (null if dismissed).
Future<ProductQuery?> showFilterSheet(BuildContext context, {required ProductQuery query, required ProductFacets facets}) {
  return showAppBottomSheet<ProductQuery>(
    context,
    builder: (_) => _FilterSheet(query: query, facets: facets),
  );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.query, required this.facets});

  final ProductQuery query;
  final ProductFacets facets;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late Set<String> _brands = {...widget.query.brands.map((b) => b.toLowerCase())};
  RangeValues? _price;
  late double? _minRating = widget.query.minRating;
  late bool _inStock = widget.query.inStock;
  late bool _onSale = widget.query.onSale;
  bool _showAllBrands = false;

  PriceRange? get _range => widget.facets.priceRange;

  @override
  void initState() {
    super.initState();
    final r = _range;
    if (r != null && r.isUsable) {
      final lo = (widget.query.minPrice ?? r.min).clamp(r.min, r.max);
      final hi = (widget.query.maxPrice ?? r.max).clamp(lo, r.max);
      _price = RangeValues(lo, hi);
    }
  }

  void _reset() => setState(() {
    _brands = {};
    final r = _range;
    _price = (r != null && r.isUsable) ? RangeValues(r.min, r.max) : null;
    _minRating = null;
    _inStock = false;
    _onSale = false;
  });

  void _apply() {
    final r = _range;
    double? minPrice;
    double? maxPrice;
    if (_price != null && r != null) {
      // only send bounds the user actually moved
      if (_price!.start > r.min + 0.5) minPrice = _price!.start;
      if (_price!.end < r.max - 0.5) maxPrice = _price!.end;
    } else {
      minPrice = widget.query.minPrice;
      maxPrice = widget.query.maxPrice;
    }
    // keep the facet's spelling for chips; the API matches case-insensitively
    final brands = [
      for (final b in widget.facets.brands)
        if (_brands.contains(b.name.toLowerCase())) b.name,
      // brands from the URL that aren't in the facets
      for (final b in widget.query.brands)
        if (_brands.contains(b.toLowerCase()) && !widget.facets.brands.any((f) => f.name.toLowerCase() == b.toLowerCase()))
          b,
    ];
    Navigator.of(context).pop(
      widget.query.copyWith(
        brands: brands,
        minPrice: () => minPrice,
        maxPrice: () => maxPrice,
        minRating: () => _minRating,
        inStock: _inStock,
        onSale: _onSale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final brands = widget.facets.brands;
    final shownBrands = _showAllBrands ? brands : brands.take(12).toList();
    final r = _range;

    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(header: true, child: Text(title, style: t.titleSmall)),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );

    return BottomSheetScaffold(
      title: 'Filters',
      trailing: TextButton(onPressed: _reset, child: const Text('Reset')),
      footer: AppButton(label: 'Show results', expand: true, onPressed: _apply),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_price != null && r != null)
            section(
              'Price',
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _PriceBox(label: 'Min', value: _price!.start),
                      const Expanded(child: Divider(indent: AppSpacing.sm, endIndent: AppSpacing.sm)),
                      _PriceBox(label: 'Max', value: _price!.end),
                    ],
                  ),
                  RangeSlider(
                    values: _price!,
                    min: r.min,
                    max: r.max,
                    divisions: 40,
                    labels: RangeLabels(Formatters.priceCompact(_price!.start), Formatters.priceCompact(_price!.end)),
                    onChanged: (v) => setState(() => _price = v),
                  ),
                ],
              ),
            ),
          if (brands.isNotEmpty)
            section(
              'Brand',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final b in shownBrands)
                        FilterChip(
                          selected: _brands.contains(b.name.toLowerCase()),
                          label: Text('${b.name}  ${b.count}'),
                          onSelected: (on) => setState(() {
                            final key = b.name.toLowerCase();
                            on ? _brands.add(key) : _brands.remove(key);
                          }),
                        ),
                    ],
                  ),
                  if (brands.length > 12)
                    TextButton(
                      onPressed: () => setState(() => _showAllBrands = !_showAllBrands),
                      style: TextButton.styleFrom(foregroundColor: colors.secondary),
                      child: Text(_showAllBrands ? 'Show fewer' : 'Show all ${brands.length} brands'),
                    ),
                ],
              ),
            ),
          section(
            'Customer rating',
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final stars in const [4.0, 3.0, 2.0])
                  ChoiceChip(
                    selected: _minRating == stars,
                    avatar: Icon(Icons.star_rounded, size: 16, color: colors.star),
                    label: Text('${stars.toInt()}★ & up'),
                    onSelected: (on) => setState(() => _minRating = on ? stars : null),
                  ),
              ],
            ),
          ),
          section(
            'Availability',
            Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In stock only'),
                  value: _inStock,
                  onChanged: (v) => setState(() => _inStock = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('On sale'),
                  subtitle: const Text('Discounted items'),
                  value: _onSale,
                  onChanged: (v) => setState(() => _onSale = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceBox extends StatelessWidget {
  const _PriceBox({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.textTheme.bodySmall),
          Text(
            Formatters.price(value),
            style: context.textTheme.titleSmall!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ],
      ),
    );
  }
}
