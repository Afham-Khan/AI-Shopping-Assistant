import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/models/json_utils.dart';
import '../../core/models/product.dart';
import '../../core/models/product_preview_cache.dart';
import '../../core/network/api_client.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/category_icons.dart';
import '../../core/utils/debouncer.dart';
import '../../core/utils/extensions.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';

/// Opens the global search palette (Ctrl/⌘ K or `/`): quick links first,
/// then categories and live product results as you type.
Future<void> showCommandPalette(BuildContext context, {required ValueChanged<int> onSelectTab}) {
  return showAppDialog<void>(context, builder: (_) => _CommandPalette(onSelectTab: onSelectTab));
}

/// Category names for instant, offline-friendly matching.
final _paletteCategoriesProvider = FutureProvider<List<({String name, String slug, String department})>>((ref) async {
  try {
    final data = await ref.watch(apiClientProvider).get<List<dynamic>>(
      '/catalog/departments',
      decode: (d) => d is List ? d : const [],
    );
    return [
      for (final dept in data.whereType<Map<String, dynamic>>())
        for (final cat in (dept['categories'] is List ? dept['categories'] as List : const []).whereType<Map<String, dynamic>>())
          (name: JsonX.asString(cat['name']), slug: JsonX.asString(cat['slug']), department: JsonX.asString(dept['slug'])),
    ];
  } on Object {
    return const [];
  }
});

class _Entry {
  const _Entry({required this.section, required this.title, required this.onOpen, this.icon, this.subtitle, this.leading, this.trailing});

  final String section;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final String? trailing;
  final void Function(BuildContext context) onOpen;
}

class _CommandPalette extends ConsumerStatefulWidget {
  const _CommandPalette({required this.onSelectTab});

  final ValueChanged<int> onSelectTab;

  @override
  ConsumerState<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends ConsumerState<_CommandPalette> {
  final _query = TextEditingController();
  final _debouncer = Debouncer(duration: const Duration(milliseconds: 280));
  final _scroll = ScrollController();
  List<ProductSummary> _products = const [];
  bool _searching = false;
  int _selected = 0;
  int _request = 0;

  String get _q => _query.text.trim();

  @override
  void dispose() {
    _query.dispose();
    _debouncer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    setState(() => _selected = 0);
    final q = _q;
    if (q.length < 2) {
      _debouncer.cancel();
      setState(() {
        _products = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debouncer.run(() => _search(q));
  }

  Future<void> _search(String q) async {
    final request = ++_request;
    List<ProductSummary> items = const [];
    try {
      final page = await ref.read(apiClientProvider).getPage(
        '/products',
        query: {'q': q, 'limit': 5},
        item: ProductSummary.fromJson,
      );
      items = page.items;
    } on Object {
      // the palette still offers pages, categories and "see all"
    }
    // ignore answers to older keystrokes
    if (!mounted || request != _request) return;
    setState(() {
      _products = items;
      _searching = false;
    });
  }

  List<_Entry> _entries() {
    final q = _q.toLowerCase();
    void tab(BuildContext c, int i) {
      Navigator.of(c).pop();
      widget.onSelectTab(i);
    }

    void push(BuildContext c, String location) {
      final router = GoRouter.of(c);
      Navigator.of(c).pop();
      router.push(location);
    }

    final pages = <_Entry>[
      _Entry(section: 'Go to', title: 'Home', icon: Icons.home_outlined, trailing: 'Alt 1', onOpen: (c) => tab(c, 0)),
      _Entry(section: 'Go to', title: 'Explore departments', icon: Icons.grid_view_outlined, trailing: 'Alt 2', onOpen: (c) => tab(c, 1)),
      _Entry(
        section: 'Go to',
        title: 'Ask Zel',
        leading: const AiSparkleIcon(size: 16),
        subtitle: 'Describe what you need in plain words',
        trailing: 'Alt 3',
        onOpen: (c) => tab(c, 2),
      ),
      _Entry(
        section: 'Go to',
        title: 'Deals',
        icon: Icons.sell_outlined,
        onOpen: (c) => push(c, Routes.productList(onSale: true, title: 'Deals')),
      ),
      _Entry(section: 'Go to', title: 'Cart', icon: Icons.shopping_bag_outlined, trailing: 'Alt 4', onOpen: (c) => tab(c, 3)),
      _Entry(section: 'Go to', title: 'Wishlist', icon: Icons.favorite_border_rounded, onOpen: (c) => push(c, Routes.wishlist)),
      _Entry(section: 'Go to', title: 'Orders', icon: Icons.receipt_long_outlined, onOpen: (c) => push(c, Routes.orders)),
      _Entry(section: 'Go to', title: 'Settings', icon: Icons.tune_rounded, onOpen: (c) => push(c, Routes.settings)),
    ];
    if (q.isEmpty) return pages;

    final categories = ref.watch(_paletteCategoriesProvider).value ?? const [];
    return [
      ...pages.where((e) => e.title.toLowerCase().contains(q)),
      for (final cat in categories.where((c) => c.name.toLowerCase().contains(q)).take(4))
        _Entry(
          section: 'Categories',
          title: cat.name,
          icon: CategoryIcons.of(cat.slug),
          subtitle: cat.department.titleCase,
          onOpen: (c) => push(c, Routes.productList(category: cat.slug, title: cat.name)),
        ),
      for (final p in _products)
        _Entry(
          section: 'Products',
          title: p.title,
          subtitle: p.brand ?? p.category?.name,
          trailing: Formatters.price(p.price),
          leading: AppNetworkImage(p.thumbnail, width: 32, height: 32, fit: BoxFit.contain, borderRadius: AppRadii.tagAll),
          onOpen: (c) {
            ProductPreviewCache.remember(p);
            push(c, Routes.product(p.id));
          },
        ),
      _Entry(
        section: 'Search',
        title: 'See all results for “$_q”',
        icon: Icons.search_rounded,
        onOpen: (c) => push(c, Routes.searchWith(q: _q)),
      ),
      _Entry(
        section: 'Search',
        title: 'Ask Zel about “$_q”',
        leading: const AiSparkleIcon(size: 16),
        onOpen: (c) => push(c, Routes.assistantWith(prompt: _q)),
      ),
    ];
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, List<_Entry> entries) {
    if (event is KeyUpEvent || entries.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowUp) {
      final step = key == LogicalKeyboardKey.arrowDown ? 1 : -1;
      setState(() => _selected = (_selected + step) % entries.length);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      entries[_selected.clamp(0, entries.length - 1)].onOpen(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final entries = _entries();
    final selected = entries.isEmpty ? 0 : _selected.clamp(0, entries.length - 1);

    final rows = <Widget>[];
    String? section;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      if (e.section != section) {
        section = e.section;
        rows.add(
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.sm, rows.isEmpty ? 4 : AppSpacing.sm, AppSpacing.sm, 6),
            child: Text(
              e.section.toUpperCase(),
              style: AppType.eyebrow(context, color: colors.faint).copyWith(fontSize: 10, letterSpacing: 1.1),
            ),
          ),
        );
      }
      rows.add(_Row(entry: e, selected: i == selected, onHover: () => setState(() => _selected = i)));
    }

    return Align(
      alignment: const Alignment(0, -0.55),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Material(
            color: colors.surface,
            elevation: 16,
            shadowColor: colors.shadow,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.borderStrong)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, 4, AppSpacing.sm, 4),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 20, color: colors.faint),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Focus(
                          onKeyEvent: (node, event) => _onKey(node, event, entries),
                          child: TextField(
                            controller: _query,
                            autofocus: true,
                            onChanged: _onChanged,
                            textInputAction: TextInputAction.search,
                            style: t.bodyLarge,
                            decoration: InputDecoration(
                              hintText: 'Search products, categories or pages',
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              hintStyle: t.bodyLarge!.copyWith(color: colors.faint),
                            ),
                          ),
                        ),
                      ),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.only(right: AppSpacing.xs),
                          child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      const KbdChip('esc'),
                    ],
                  ),
                ),
                Divider(color: colors.border),
                Flexible(
                  child: AnimatedOpacity(
                    // keep the last results on screen and dim them while refetching
                    opacity: _searching ? 0.7 : 1,
                    duration: context.motion(AppDurations.fast),
                    child: ListView(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      children: rows,
                    ),
                  ),
                ),
                Divider(color: colors.border),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 9),
                  child: Row(
                    children: [
                      const KbdChip('↑'),
                      const SizedBox(width: 3),
                      const KbdChip('↓'),
                      const SizedBox(width: 6),
                      Text('to move', style: AppType.data(context, color: colors.faint, size: 11)),
                      const SizedBox(width: AppSpacing.md),
                      const KbdChip('↵'),
                      const SizedBox(width: 6),
                      Text('to open', style: AppType.data(context, color: colors.faint, size: 11)),
                      const Spacer(),
                      Text('esc to close', style: AppType.data(context, color: colors.faint, size: 11)),
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

class _Row extends StatelessWidget {
  const _Row({required this.entry, required this.selected, required this.onHover});

  final _Entry entry;
  final bool selected;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: selected ? colors.surfaceVariant : Colors.transparent,
        borderRadius: AppRadii.inputAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => entry.onOpen(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 8),
            child: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: entry.leading ?? Icon(entry.icon, size: 18, color: selected ? colors.primary : colors.muted),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (entry.subtitle != null)
                        Text(entry.subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall!.copyWith(color: colors.faint)),
                    ],
                  ),
                ),
                if (entry.trailing != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(entry.trailing!, style: AppType.data(context, color: selected ? colors.text : colors.faint, size: 11.5)),
                ],
                if (selected) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Icon(Icons.subdirectory_arrow_left_rounded, size: 14, color: colors.faint),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
