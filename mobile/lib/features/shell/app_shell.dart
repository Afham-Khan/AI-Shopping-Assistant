import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/extensions.dart';
import '../../core/widgets/widgets.dart';
import '../cart/providers/cart_provider.dart';
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
  _Tab('Explore', Icons.explore_outlined, Icons.explore_rounded),
  _Tab(AppConfig.assistantName, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, isAi: true),
  _Tab('Cart', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded, isCart: true),
  _Tab('Profile', Icons.person_outline_rounded, Icons.person_rounded),
];

/// Tab scaffold. Zelora is a mobile app everywhere: the bottom bar is the
/// only navigation on every screen size (on tablet / desktop / web the whole
/// app sits in a phone-width column — see `AppFrame`). There is no top
/// navbar and no side rail. Each tab keeps its own stack/state.
///
/// Keyboard (hidden extra for web / desktop): `/` or Ctrl/⌘ K opens the
/// search palette from anywhere, Alt 1–5 switches tabs.
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

  /// The keyboard shortcut opens the command palette (on-screen search
  /// entry points push the search screen themselves).
  Future<void> _openPalette() async {
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
      _openPalette();
      return true;
    }
    // "/" is only a shortcut when nobody is typing
    if (event.logicalKey == LogicalKeyboardKey.slash && !_typing && !keys.isControlPressed && !keys.isAltPressed) {
      _openPalette();
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
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: ZeloraNavBar(index: widget.navigationShell.currentIndex, onSelect: _select),
    );
  }
}

/// The bottom bar: white, rounded top corners, a soft upward shadow. The
/// current tab gets a blue icon + label on a light-blue pill; the assistant sits in the
/// middle as a royal-blue circle with the spark.
class ZeloraNavBar extends StatelessWidget {
  const ZeloraNavBar({super.key = const Key('app-bottom-nav'), required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const double height = 70;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: context.isDark ? 0.4 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Row(
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  Expanded(
                    child: _tabs[i].isAi
                        ? _ZelItem(selected: index == i, onTap: () => onSelect(i), label: _tabs[i].label)
                        : _NavItem(tab: _tabs[i], selected: index == i, onTap: () => onSelect(i)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends ConsumerWidget {
  const _NavItem({required this.tab, required this.selected, required this.onTap});

  final _Tab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final t = context.textTheme;
    final ink = selected ? colors.primary : colors.muted;
    Widget icon = Icon(selected ? tab.selectedIcon : tab.icon, size: 24, color: ink);
    if (tab.isCart) icon = AppBadge(count: ref.watch(cartCountProvider), child: icon);

    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      child: Tooltip(
        message: tab.label,
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          highlightShape: BoxShape.circle,
          splashColor: colors.primary.withValues(alpha: 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: context.motion(AppDurations.normal),
                curve: AppCurves.standard,
                width: 54,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? colors.primarySoft : colors.primarySoft.withValues(alpha: 0),
                  borderRadius: AppRadii.pillAll,
                ),
                child: icon,
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: context.motion(AppDurations.fast),
                style: t.labelSmall!.copyWith(
                  fontSize: 11.5,
                  color: ink,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
                child: Text(
                  tab.label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  // the bar has a fixed height: labels grow a little, not 2x
                  textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The center tab: the assistant — a royal-blue circle holding the bag mascot
/// (happy eyes while its tab is open).
/// It rises slightly above the bar; selected swaps the white ring for a
/// light-blue one (a solid ring, not a glow).
class _ZelItem extends StatelessWidget {
  const _ZelItem({required this.selected, required this.onTap, required this.label});

  final bool selected;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Ask $label',
      excludeSemantics: true,
      child: Tooltip(
        message: 'Ask $label',
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          highlightShape: BoxShape.circle,
          splashColor: colors.primary.withValues(alpha: 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // the circle sits on the same 32 px slot as the other icons and
              // rises above it, so every label shares one baseline
              SizedBox(
                height: 32,
                child: OverflowBox(
                  maxHeight: 52,
                  alignment: Alignment.bottomCenter,
                  child: Pressable(
                    scale: 0.92,
                    child: AnimatedContainer(
                      duration: context.motion(AppDurations.normal),
                      curve: AppCurves.standard,
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: selected ? colors.primarySoft : colors.surface, width: 4),
                        boxShadow: [
                          BoxShadow(color: colors.shadow.withValues(alpha: 0.22), blurRadius: 14, offset: const Offset(0, 5)),
                        ],
                      ),
                      child: AiMascot(
                        size: 30,
                        color: colors.onPrimary,
                        eyeColor: colors.primary,
                        mood: selected ? AiMood.happy : AiMood.idle,
                        animate: false,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.25),
                style: t.labelSmall!.copyWith(
                  fontSize: 11.5,
                  color: selected ? colors.primary : colors.muted,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
