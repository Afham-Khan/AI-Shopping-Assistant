import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/providers/auth_controller.dart';
import '../../auth/providers/require_auth.dart';
import '../../cart/providers/cart_controller.dart';
import '../../wishlist/providers/wishlist_provider.dart';
import '../data/discover_models.dart';
import '../providers/discover_providers.dart';
import 'reels_viewer.dart';
import 'shop_actions.dart';
import 'widgets/reels_row.dart';
import 'widgets/swipe_deck.dart';
import 'widgets/taste_panel.dart';

/// Discover: department stories on top, then a deck you answer one card at
/// a time — like (saved to the wishlist), pass, or bag (added to the cart).
/// Every answer updates the taste readout; likes pull similar products
/// into the deck ("Because you liked …"). Undo puts the last card back and
/// reverses what it did.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _deckKey = GlobalKey<SwipeDeckState>();
  final _seenReels = <String>{};

  /// What each swipe did outside the deck, so undo can reverse it.
  final _effects = <int, ({bool saved, bool carted})>{};

  DiscoverController get _controller => ref.read(discoverControllerProvider.notifier);

  void _onSwiped(SwipeAction action) {
    // guests can swipe (taste is learned locally) but bagging needs an account
    if (action == SwipeAction.bag && !requireAuth(context, ref, message: 'Sign in to bag items')) {
      _controller.swipe(action);
      return;
    }
    final result = _controller.swipe(action);
    if (result == null) return;
    final p = result.record.card.product;
    switch (action) {
      case SwipeAction.like:
        _saveQuietly(p);
      case SwipeAction.bag:
        result.server.then((outcome) => _afterBag(p, outcome));
      case SwipeAction.pass:
        break;
    }
  }

  /// `bag` puts one in the cart on the server; sync the badge, or fall back
  /// to a plain add when the swipe endpoint isn't there.
  Future<void> _afterBag(ProductSummary p, SwipeOutcome outcome) async {
    if (!mounted) return;
    var added = false;
    if (outcome.response != null) {
      added = true;
      await ref.read(cartProvider.notifier).refresh().catchError((_) {});
      if (mounted) {
        AppSnack.success(context, 'Added to cart', actionLabel: 'View cart', onAction: () => context.go(Routes.cart));
      }
    } else if (outcome.error != null) {
      AppSnack.error(context, outcome.error!);
    } else {
      added = await quickAddToCart(context, ref, p, source: 'discover');
    }
    if (added) _effects[p.id] = (saved: _effects[p.id]?.saved ?? false, carted: true);
  }

  /// Likes go to the wishlist for signed-in shoppers (no toast: the deck is the feedback).
  Future<void> _saveQuietly(ProductSummary p) async {
    if (!ref.read(isAuthenticatedProvider) || ref.read(wishlistIdsProvider).contains(p.id)) return;
    try {
      await toggleWishlist(ref, p.id);
      _effects[p.id] = (saved: true, carted: _effects[p.id]?.carted ?? false);
    } catch (_) {
      // the like still counts for taste
    }
  }

  Future<void> _takeOneFromCart(int productId) async {
    final cart = ref.read(cartProvider.notifier);
    final lines = ref.read(cartProvider).value?.items ?? const [];
    final line = lines.where((l) => l.productId == productId).firstOrNull;
    if (line == null) return;
    line.quantity > 1 ? await cart.setQuantity(productId, line.quantity - 1) : await cart.remove(productId);
  }

  void _swipeWith(SwipeAction action) => _deckKey.currentState?.fling(action);

  Future<void> _undo() async {
    final record = _controller.undo();
    if (record == null) return;
    HapticFeedback.selectionClick();
    final effect = _effects.remove(record.card.id);
    try {
      if (effect?.carted ?? false) await _takeOneFromCart(record.card.id);
      if ((effect?.saved ?? false) && ref.read(wishlistIdsProvider).contains(record.card.id)) {
        await toggleWishlist(ref, record.card.id);
      }
    } catch (_) {
      // the card is back either way
    }
    if (mounted) AppSnack.info(context, 'Brought back ${record.card.product.title}');
  }

  void _openReels(List<DiscoverReel> reels, int index) {
    setState(() => _seenReels.add(reels[index].slug));
    openReels(context, reels, index);
  }

  void _showTaste() {
    showAppBottomSheet<void>(
      context,
      builder: (_) => BottomSheetScaffold(
        title: 'Your taste',
        // live: rebuilds as the deck learns
        child: Consumer(
          builder: (context, ref, _) {
            final state = ref.watch(discoverControllerProvider).value;
            if (state == null) return const SizedBox(height: 120);
            return TastePanel(
              state: state,
              onShopTaste: () {
                final top = state.taste.categories.first;
                Navigator.of(context).pop();
                context.push(
                  Routes.productList(
                    category: top.slug,
                    q: top.slug == null ? top.name : null,
                    title: 'For your taste',
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deck = ref.watch(discoverControllerProvider);
    final reels = ref.watch(discoverReelsProvider);
    final state = deck.value;
    final canUndo = state?.canUndo ?? false;
    final hasCards = state != null && !state.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            tooltip: 'Undo last swipe',
            onPressed: canUndo ? _undo : null,
            icon: const Icon(Icons.undo_rounded),
          ),
          IconButton(
            tooltip: 'Your taste',
            onPressed: state == null ? null : _showTaste,
            icon: const Icon(Icons.insights_outlined),
          ),
          const SizedBox(width: AppSpacing.xxs),
        ],
      ),
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _swipeWith(SwipeAction.pass),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () => _swipeWith(SwipeAction.like),
          const SingleActivator(LogicalKeyboardKey.arrowUp): () => _swipeWith(SwipeAction.bag),
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(LogicalKeyboardKey.backspace): _undo,
        },
        child: Focus(
          autofocus: true,
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    switch (reels) {
                      AsyncValue(:final value?) when value.isNotEmpty => ReelsRow(
                        reels: value,
                        seen: _seenReels,
                        onOpen: (i) => _openReels(value, i),
                      ),
                      AsyncValue(:final value?) when value.isEmpty => const SizedBox.shrink(),
                      AsyncValue(hasError: true) => const SizedBox.shrink(),
                      _ => ReelsRow.loading(context),
                    },
                    if (state != null)
                      Padding(
                        padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.xxs, context.pagePadding, 0),
                        child: TasteStrip(state: state, onTap: _showTaste),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: context.pagePadding + AppSpacing.xxs),
                        child: switch (deck) {
                          AsyncValue(:final value?) when value.isEmpty => _EmptyDeck(
                            liked: value.count(SwipeAction.like) + value.count(SwipeAction.bag),
                            onReload: _controller.reload,
                            onTaste: _showTaste,
                          ),
                          AsyncValue(:final value?) => SwipeDeck(
                            key: _deckKey,
                            cards: value.queue,
                            onSwiped: _onSwiped,
                            onOpen: (p) => openProduct(context, p),
                          ),
                          AsyncValue(:final error?) => Center(
                            child: ErrorState(
                              error: error,
                              compact: true,
                              onRetry: () => ref.invalidate(discoverControllerProvider),
                            ),
                          ),
                          _ => const _DeckSkeleton(),
                        },
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ActionBar(
                      enabled: hasCards,
                      onPass: () => _swipeWith(SwipeAction.pass),
                      onBag: () => _swipeWith(SwipeAction.bag),
                      onLike: () => _swipeWith(SwipeAction.like),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.enabled, required this.onPass, required this.onBag, required this.onLike});

  final bool enabled;
  final VoidCallback onPass;
  final VoidCallback onBag;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundAction(label: 'Pass', icon: Icons.close_rounded, color: colors.sale, onTap: enabled ? onPass : null),
        const SizedBox(width: AppSpacing.xl),
        _RoundAction(
          label: 'Bag',
          icon: Icons.shopping_bag_rounded,
          color: colors.onPrimary,
          fill: colors.primary,
          size: 68,
          onTap: enabled ? onBag : null,
        ),
        const SizedBox(width: AppSpacing.xl),
        _RoundAction(label: 'Like', icon: Icons.favorite_rounded, color: colors.success, onTap: enabled ? onLike : null),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.fill,
    this.size = 56,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color? fill;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: AnimatedOpacity(
          opacity: enabled ? 1 : 0.45,
          duration: context.motion(AppDurations.fast),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Pressable(
                enabled: enabled,
                scale: 0.9,
                child: Material(
                  color: fill ?? colors.surface,
                  shape: CircleBorder(side: fill == null ? BorderSide(color: colors.border) : BorderSide.none),
                  elevation: 0,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onTap,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: colors.shadowSm),
                      child: Icon(icon, color: color, size: size * 0.44),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(label, style: context.textTheme.labelSmall!.copyWith(color: colors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyDeck extends StatelessWidget {
  const _EmptyDeck({required this.liked, required this.onReload, required this.onTaste});

  final int liked;
  final Future<void> Function() onReload;
  final VoidCallback onTaste;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              icon: Icons.style_outlined,
              title: "That's the whole deck",
              message: liked > 0
                  ? 'You kept $liked. Deal a fresh hand and Zel leans into your taste.'
                  : 'Deal a fresh hand to keep going.',
              actionLabel: 'Deal again',
              onAction: onReload,
              compact: true,
            ),
            if (liked > 0) TextButton(onPressed: onTaste, child: const Text('See your taste')),
          ],
        ),
      ),
    );
  }
}

class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Skeleton(borderRadius: AppRadii.sheetAll)),
        SizedBox(height: AppSpacing.sm),
        Align(alignment: Alignment.centerLeft, child: Skeleton(width: 120, height: 12)),
        SizedBox(height: AppSpacing.xs),
        Align(alignment: Alignment.centerLeft, child: Skeleton(width: 200, height: 18)),
      ],
    );
  }
}
