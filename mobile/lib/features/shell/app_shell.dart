import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/app_config.dart';
import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/extensions.dart';
import '../../core/widgets/widgets.dart';
import '../cart/providers/cart_provider.dart';

/// One tab of the shell. Order must match the branches in app_router.dart.
class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, {this.isAi = false, this.isCart = false});

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool isAi;
  final bool isCart;
}

const _tabs = [
  _Tab('Home', Icons.home_outlined, Icons.home_rounded),
  _Tab('Explore', Icons.grid_view_outlined, Icons.grid_view_rounded),
  _Tab('Assistant', Icons.auto_awesome_outlined, Icons.auto_awesome, isAi: true),
  _Tab('Cart', Icons.shopping_bag_outlined, Icons.shopping_bag, isCart: true),
  _Tab('Account', Icons.person_outline_rounded, Icons.person_rounded),
];

/// "Ctrl" everywhere except Apple platforms, where it is "⌘".
bool get _applePlatform =>
    defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;

/// Tab scaffold: bottom bar on narrow portrait screens, NavigationRail
/// otherwise (extended from 1100 px). Each tab keeps its own stack/state.
///
/// Keyboard: Ctrl/⌘ K opens search from anywhere, Alt 1–5 switches tabs.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  void _select(int index) {
    final shell = widget.navigationShell;
    if (index != shell.currentIndex) HapticFeedback.selectionClick();
    // tapping the current tab pops it back to its root
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  void _openSearch() {
    final router = GoRouter.of(context);
    final path = router.routerDelegate.currentConfiguration.uri.path;
    if (path != Routes.search) router.push(Routes.search);
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final keys = HardwareKeyboard.instance;

    if (event.logicalKey == LogicalKeyboardKey.keyK && (keys.isControlPressed || keys.isMetaPressed)) {
      _openSearch();
      return true;
    }
    // tab switching only while the shell itself is on top
    if (keys.isAltPressed && (ModalRoute.of(context)?.isCurrent ?? true)) {
      final index = _digits.indexOf(event.logicalKey);
      if (index >= 0) {
        _select(index);
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.navigationShell.currentIndex;

    if (context.useBottomNav) {
      return Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: _BottomBar(index: index, onSelect: _select),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _SideRail(index: index, onSelect: _select, onSearch: _openSearch, extended: context.isDesktop),
          VerticalDivider(width: 1, thickness: 1, color: context.colors.border),
          Expanded(child: widget.navigationShell),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.border))),
      child: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: onSelect,
        destinations: [
          for (var i = 0; i < _tabs.length; i++)
            NavigationDestination(
              icon: _TabIcon(tab: _tabs[i], selected: false),
              selectedIcon: _TabIcon(tab: _tabs[i], selected: true),
              label: _tabs[i].label,
              tooltip: _tabs[i].label,
            ),
        ],
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.index, required this.onSelect, required this.onSearch, required this.extended});

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: onSelect,
      extended: extended,
      labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
      groupAlignment: -1,
      // short landscape phones scroll the destinations instead of overflowing
      scrollable: true,
      trailingAtBottom: true,
      leading: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: extended ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            InkWell(
              onTap: () => onSelect(0),
              borderRadius: AppRadii.inputAll,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                child: AppLogo(size: 30, showWordmark: extended),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _RailSearch(extended: extended, onTap: onSearch),
          ],
        ),
      ),
      trailing: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: extended
            ? _RailFooter(onSettings: () => context.push(Routes.settings))
            : IconButton(
                onPressed: () => context.push(Routes.settings),
                icon: Icon(Icons.tune_rounded, color: colors.muted, size: 20),
                tooltip: 'Settings',
              ),
      ),
      destinations: [
        for (final tab in _tabs)
          NavigationRailDestination(
            icon: _TabIcon(tab: tab, selected: false),
            selectedIcon: _TabIcon(tab: tab, selected: true),
            label: Text(tab.label),
            padding: const EdgeInsets.symmetric(vertical: 2),
          ),
      ],
    );
  }
}

/// Search entry in the rail: a field-shaped button with the shortcut it
/// answers to. Collapses to an icon on the narrow rail.
class _RailSearch extends StatelessWidget {
  const _RailSearch({required this.extended, required this.onTap});

  final bool extended;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final modifier = _applePlatform ? '⌘' : 'Ctrl';

    if (!extended) {
      return IconButton(
        onPressed: onTap,
        icon: Icon(Icons.search_rounded, color: colors.muted),
        tooltip: 'Search ($modifier K)',
      );
    }

    return Semantics(
      button: true,
      label: 'Search',
      excludeSemantics: true,
      child: SizedBox(
        width: 200,
        child: Material(
          color: colors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: AppRadii.inputAll, side: BorderSide(color: colors.border)),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 17, color: colors.faint),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text('Search', style: context.textTheme.bodyMedium!.copyWith(color: colors.faint)),
                  ),
                  KbdChip(modifier),
                  const SizedBox(width: 3),
                  const KbdChip('K'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom of the extended rail: settings link and the build in mono.
class _RailFooter extends StatelessWidget {
  const _RailFooter({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: 200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onSettings,
            borderRadius: AppRadii.inputAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.tune_rounded, size: 18, color: colors.muted),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Settings',
                      style: context.textTheme.labelMedium!.copyWith(color: colors.muted, fontWeight: FontWeight.w500, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Text(
              'ZELORA ${AppConfig.appVersion}',
              style: AppType.eyebrow(context, color: colors.faint).copyWith(fontSize: 10, letterSpacing: 1.1),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab icon: Zel's spark for the assistant, count badge for the cart.
class _TabIcon extends ConsumerWidget {
  const _TabIcon({required this.tab, required this.selected});

  final _Tab tab;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = selected ? tab.selectedIcon : tab.icon;

    if (tab.isAi) {
      final theme = IconTheme.of(context);
      // the assistant always carries the accent, outlined until selected
      return SizedBox.square(
        dimension: theme.size ?? 22,
        child: Center(child: AiSparkleIcon(size: (theme.size ?? 22) - 2, filled: selected)),
      );
    }
    if (tab.isCart) {
      final count = ref.watch(cartCountProvider);
      return AppBadge(count: count, child: Icon(icon));
    }
    return Icon(icon);
  }
}
