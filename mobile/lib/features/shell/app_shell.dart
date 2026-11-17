import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/router/routes.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/utils/extensions.dart';
import '../../core/widgets/widgets.dart';
import '../auth/providers/auth_controller.dart';
import '../cart/providers/cart_provider.dart';
import '../notifications/providers/notifications_providers.dart';
import '../wishlist/providers/wishlist_provider.dart';
import 'command_palette.dart';

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

/// Tab scaffold. Phones in portrait get a bottom bar; everything wider gets
/// a storefront header (logo, primary nav, search, wishlist / alerts / cart /
/// account) — a shop, not an admin panel. Each tab keeps its own stack/state.
///
/// Keyboard: `/` or Ctrl/⌘ K opens search from anywhere, Alt 1–5 switches tabs.
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

  bool _paletteOpen = false;

  /// Wide screens get the command palette; phones go to the search screen.
  Future<void> _openSearch() async {
    if (context.useBottomNav) {
      final router = GoRouter.of(context);
      final path = router.routerDelegate.currentConfiguration.uri.path;
      if (path != Routes.search) router.push(Routes.search);
      return;
    }
    if (_paletteOpen) return;
    _paletteOpen = true;
    await showCommandPalette(context, onSelectTab: _select);
    _paletteOpen = false;
  }

  bool get _typing {
    final widget = FocusManager.instance.primaryFocus?.context?.widget;
    return widget is EditableText;
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    final keys = HardwareKeyboard.instance;

    if (event.logicalKey == LogicalKeyboardKey.keyK && (keys.isControlPressed || keys.isMetaPressed)) {
      _openSearch();
      return true;
    }
    // "/" is only a shortcut when nobody is typing
    if (event.logicalKey == LogicalKeyboardKey.slash && !_typing && !keys.isControlPressed && !keys.isAltPressed) {
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
      body: Column(
        children: [
          StoreHeader(index: index, onSelect: _select, onSearch: _openSearch),
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

/// The storefront header for tablet / desktop / web: solid surface, hairline
/// bottom border, content capped at the page max-width.
///
/// `logo · Home  Explore  Ask Zel  Deals · [ search  Ctrl K ] · ♡  bell  bag  avatar`
class StoreHeader extends ConsumerWidget {
  const StoreHeader({super.key, required this.index, required this.onSelect, required this.onSearch});

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onSearch;

  static const double height = 64;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final width = context.screenWidth;
    final roomy = width >= 1000; // wordmark + search field
    final field = width >= 880;
    final extras = width >= 780; // wishlist + notifications icons

    final signedIn = ref.watch(isAuthenticatedProvider);
    final cart = ref.watch(cartCountProvider);
    final saved = signedIn ? ref.watch(wishlistIdsProvider.select((ids) => ids.length)) : 0;
    final unread = signedIn ? ref.watch(unreadNotificationsProvider) : 0;

    return Material(
      key: const Key('store-header'),
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.border))),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: height,
            child: ResponsiveCenter(
              alignment: Alignment.center,
              child: Row(
                children: [
                  InkWell(
                    onTap: () => onSelect(0),
                    borderRadius: AppRadii.inputAll,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs, horizontal: 2),
                      child: AppLogo(size: 28, showWordmark: roomy),
                    ),
                  ),
                  SizedBox(width: roomy ? AppSpacing.xl : AppSpacing.sm),
                  _NavLink(label: 'Home', selected: index == 0, onTap: () => onSelect(0)),
                  _NavLink(label: 'Explore', selected: index == 1, onTap: () => onSelect(1)),
                  _NavLink(
                    label: 'Ask Zel',
                    selected: index == 2,
                    onTap: () => onSelect(2),
                    leading: AiSparkleIcon(size: 13, filled: index == 2),
                  ),
                  _NavLink(
                    label: 'Deals',
                    selected: false,
                    onTap: () => context.push(Routes.productList(onSale: true, title: 'Deals')),
                    dot: colors.sale,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  if (field)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 380),
                          child: _SearchField(onTap: onSearch),
                        ),
                      ),
                    )
                  else ...[
                    const Spacer(),
                    _HeaderAction(icon: Icons.search_rounded, tooltip: 'Search', onTap: onSearch),
                  ],
                  const SizedBox(width: AppSpacing.xs),
                  if (extras) ...[
                    _HeaderAction(
                      icon: Icons.favorite_border_rounded,
                      tooltip: 'Wishlist',
                      count: saved,
                      quietCount: true,
                      onTap: () => context.push(Routes.wishlist),
                    ),
                    _HeaderAction(
                      icon: Icons.notifications_none_rounded,
                      tooltip: 'Notifications',
                      dot: unread > 0,
                      onTap: () => context.push(Routes.notifications),
                    ),
                  ],
                  _HeaderAction(
                    icon: index == 3 ? Icons.shopping_bag : Icons.shopping_bag_outlined,
                    tooltip: 'Cart',
                    count: cart,
                    selected: index == 3,
                    onTap: () => onSelect(3),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  _AccountMenu(selected: index == 4, onAccount: () => onSelect(4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary nav link: muted at rest, ink on hover, and a 2 px accent rule
/// sitting on the header's bottom edge when current.
class _NavLink extends StatefulWidget {
  const _NavLink({required this.label, required this.selected, required this.onTap, this.leading, this.dot});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;

  /// Small status dot after the label (e.g. coral for Deals).
  final Color? dot;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final on = widget.selected;
    final ink = on || _hovered ? colors.text : colors.muted;

    return Semantics(
      button: true,
      selected: on,
      label: widget.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (h) => setState(() => _hovered = h),
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: AppRadii.tagAll,
        child: SizedBox(
          height: StoreHeader.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 6)],
                    AnimatedDefaultTextStyle(
                      duration: context.motion(AppDurations.fast),
                      style: context.textTheme.labelLarge!.copyWith(
                        color: ink,
                        fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                      ),
                      child: Text(widget.label),
                    ),
                    if (widget.dot != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(color: widget.dot, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 0,
                child: AnimatedContainer(
                  duration: context.motion(AppDurations.normal),
                  curve: AppCurves.standard,
                  height: 2,
                  decoration: BoxDecoration(
                    color: on ? colors.primary : (_hovered ? colors.borderStrong : Colors.transparent),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Field-shaped search entry with the shortcut it answers to.
class _SearchField extends StatefulWidget {
  const _SearchField({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final modifier = _applePlatform ? '\u2318' : 'Ctrl';

    return Semantics(
      button: true,
      label: 'Search products',
      excludeSemantics: true,
      child: Material(
        color: colors.background,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.inputAll,
          side: BorderSide(color: _hovered ? colors.borderStrong : colors.border),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (h) => setState(() => _hovered = h),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 9, 0),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, size: 18, color: colors.faint),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Search products, brands, categories',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodyMedium!.copyWith(color: colors.faint),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
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

/// Icon action on the right of the header, with an optional count or dot.
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.count = 0,
    this.dot = false,
    this.selected = false,
    this.quietCount = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int count;
  final bool dot;
  final bool selected;

  /// Show the count as a neutral chip rather than the accent badge
  /// (the cart owns the accent).
  final bool quietCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    Widget glyph = Icon(icon, size: 21, color: selected ? colors.primary : colors.text);
    if (dot) {
      glyph = AppBadge.dot(show: true, child: glyph);
    } else if (count > 0 && quietCount) {
      glyph = Badge(
        label: Text(count > 99 ? '99+' : '$count'),
        backgroundColor: colors.surfaceRaised,
        textColor: colors.text,
        offset: const Offset(6, -4),
        child: glyph,
      );
    } else if (count > 0) {
      glyph = AppBadge(count: count, child: glyph);
    }
    return IconButton(onPressed: onTap, tooltip: tooltip, icon: glyph);
  }
}

enum _AccountAction { account, orders, wishlist, settings, signIn, register, signOut }

/// Avatar (initials) that opens the account menu; guests get sign-in options.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu({required this.selected, required this.onAccount});

  final bool selected;
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final t = context.textTheme;
    final user = ref.watch(currentUserProvider);

    PopupMenuItem<_AccountAction> item(_AccountAction value, IconData icon, String label, {Color? color}) => PopupMenuItem(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? colors.muted),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: t.bodyMedium!.copyWith(color: color ?? colors.text, fontWeight: FontWeight.w500)),
        ],
      ),
    );

    return PopupMenuButton<_AccountAction>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(minWidth: 232),
      onSelected: (action) async {
        switch (action) {
          case _AccountAction.account:
            onAccount();
          case _AccountAction.orders:
            context.push(Routes.orders);
          case _AccountAction.wishlist:
            context.push(Routes.wishlist);
          case _AccountAction.settings:
            context.push(Routes.settings);
          case _AccountAction.signIn:
            context.push(Routes.login);
          case _AccountAction.register:
            context.push(Routes.register);
          case _AccountAction.signOut:
            await ref.read(authControllerProvider.notifier).logout();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem<_AccountAction>(
          enabled: false,
          height: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(user?.name ?? 'Browsing as guest', style: t.titleSmall!.copyWith(color: colors.text)),
              const SizedBox(height: 2),
              Text(
                user?.email ?? 'Sign in to save items and check out',
                style: AppType.data(context, color: colors.faint, size: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        if (user != null) ...[
          item(_AccountAction.account, Icons.person_outline_rounded, 'Account'),
          item(_AccountAction.orders, Icons.receipt_long_outlined, 'Orders'),
          item(_AccountAction.wishlist, Icons.favorite_border_rounded, 'Wishlist'),
        ] else ...[
          item(_AccountAction.signIn, Icons.login_rounded, 'Sign in', color: colors.primary),
          item(_AccountAction.register, Icons.person_add_alt_outlined, 'Create account'),
          item(_AccountAction.account, Icons.person_outline_rounded, 'Account'),
        ],
        item(_AccountAction.settings, Icons.tune_rounded, 'Settings'),
        if (user != null) ...[
          const PopupMenuDivider(height: 8),
          item(_AccountAction.signOut, Icons.logout_rounded, 'Sign out'),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AppAvatar(name: user?.name, imageUrl: user?.avatarUrl, size: 34, selected: selected),
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
      final size = IconTheme.of(context).size ?? 22;
      // the assistant always carries the accent, outlined until selected
      return SizedBox.square(
        dimension: size,
        child: Center(child: AiSparkleIcon(size: size - 2, filled: selected)),
      );
    }
    if (tab.isCart) {
      final count = ref.watch(cartCountProvider);
      return AppBadge(count: count, child: Icon(icon));
    }
    return Icon(icon);
  }
}
