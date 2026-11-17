import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product.dart';
import '../../../core/models/product_preview_cache.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../data/deck_model.dart';
import '../data/discover_models.dart';
import 'shop_actions.dart';

/// Opens the full-screen department stories at [index].
Future<void> openReels(BuildContext context, List<DiscoverReel> reels, int index) {
  return Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: false,
      transitionDuration: context.motion(const Duration(milliseconds: 320)),
      reverseTransitionDuration: context.motion(const Duration(milliseconds: 220)),
      pageBuilder: (_, _, _) => ReelsViewer(reels: reels, initialReel: index),
      transitionsBuilder: (_, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween(begin: 0.94, end: 1.0).animate(curved), child: child),
        );
      },
    ),
  );
}

/// Story viewer: segmented progress per department, tap right / left to go
/// forward / back, hold to pause, swipe sideways between departments, drag
/// down to close. Each product has View and Add to cart.
class ReelsViewer extends ConsumerStatefulWidget {
  const ReelsViewer({super.key, required this.reels, this.initialReel = 0, this.segment = const Duration(seconds: 5)});

  final List<DiscoverReel> reels;
  final int initialReel;

  /// Time each product stays on screen.
  final Duration segment;

  @override
  ConsumerState<ReelsViewer> createState() => _ReelsViewerState();
}

class _ReelsViewerState extends ConsumerState<ReelsViewer> with TickerProviderStateMixin {
  late final PageController _pages = PageController(initialPage: widget.initialReel);
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.segment)
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  late final AnimationController _dismissBack = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  final _dismiss = ValueNotifier<double>(0);
  double _dismissFrom = 0;

  late ReelsCursor _cursor = ReelsCursor(widget.initialReel.clamp(0, widget.reels.length - 1), 0);
  bool _paused = false;
  bool _closing = false;

  /// Set while we move the PageView ourselves, so onPageChanged keeps the cursor.
  bool _programmatic = false;

  List<int> get _lengths => [for (final r in widget.reels) r.products.length];

  @override
  void initState() {
    super.initState();
    _dismissBack.addListener(
      () => _dismiss.value = _dismissFrom * (1 - Curves.easeOut.transform(_dismissBack.value)),
    );
    _progress.forward();
  }

  @override
  void dispose() {
    _pages.dispose();
    _progress.dispose();
    _dismissBack.dispose();
    _dismiss.dispose();
    super.dispose();
  }

  void _go(ReelsCursor next) {
    final reelChanged = next.reel != _cursor.reel;
    setState(() => _cursor = next);
    _progress.forward(from: 0);
    if (reelChanged && _pages.hasClients) {
      _programmatic = true;
      final animate = !context.reduceMotion;
      (animate
              ? _pages.animateToPage(next.reel, duration: const Duration(milliseconds: 360), curve: Curves.easeOutCubic)
              : Future(() => _pages.jumpToPage(next.reel)))
          .whenComplete(() => _programmatic = false);
    }
  }

  void _next() {
    final next = _cursor.next(_lengths);
    next == null ? _close() : _go(next);
  }

  void _previous() => _go(_cursor.previous(_lengths));

  void _close() {
    if (_closing) return;
    _closing = true;
    _progress.stop();
    Navigator.of(context).maybePop();
  }

  void _pause(bool paused) {
    if (_paused == paused) return;
    setState(() => _paused = paused);
    paused ? _progress.stop() : _progress.forward();
  }

  void _onTapUp(TapUpDetails d) {
    final w = context.size?.width ?? 1;
    d.localPosition.dx < w / 3 ? _previous() : _next();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dismiss.value = (_dismiss.value + d.delta.dy).clamp(0.0, double.infinity);
    if (!_paused) _pause(true);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dismiss.value > 120 || d.velocity.pixelsPerSecond.dy > 700) {
      HapticFeedback.lightImpact();
      _close();
      return;
    }
    _dismissFrom = _dismiss.value;
    _dismissBack.forward(from: 0);
    _pause(false);
  }

  void _openProduct(ProductSummary p) {
    _pause(true);
    _closing = true;
    final router = GoRouter.of(context);
    ProductPreviewCache.remember(p);
    Navigator.of(context).pop();
    router.push(Routes.product(p.id));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final current = widget.reels[_cursor.reel];
    final product = current.products.isEmpty ? null : current.products[_cursor.item.clamp(0, current.products.length - 1)];

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): _previous,
        const SingleActivator(LogicalKeyboardKey.space): () => _pause(!_paused),
      },
      child: Focus(
        autofocus: true,
        child: ValueListenableBuilder<double>(
          valueListenable: _dismiss,
          builder: (context, drag, child) {
            final t = (drag / 400).clamp(0.0, 1.0);
            return ColoredBox(
              color: colors.background.withValues(alpha: 1 - t * 0.6),
              child: Transform.translate(
                offset: Offset(0, drag),
                child: Transform.scale(scale: 1 - t * 0.12, child: child),
              ),
            );
          },
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: _onTapUp,
              onLongPressStart: (_) => _pause(true),
              onLongPressEnd: (_) => _pause(false),
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.reels.length,
                onPageChanged: (i) {
                  if (_programmatic) return;
                  setState(() => _cursor = ReelsCursor(i, 0));
                  _progress.forward(from: 0);
                },
                itemBuilder: (context, i) {
                  final reel = widget.reels[i];
                  final active = i == _cursor.reel;
                  return _ReelPage(
                    reel: reel,
                    item: active ? _cursor.item : 0,
                    active: active,
                    progress: _progress,
                    paused: _paused && active,
                    onClose: _close,
                    onView: product == null ? null : () => _openProduct(active ? product : reel.products.first),
                    onAdd: product == null
                        ? null
                        : () => quickAddToCart(context, ref, active ? product : reel.products.first, source: 'reels'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReelPage extends StatelessWidget {
  const _ReelPage({
    required this.reel,
    required this.item,
    required this.active,
    required this.progress,
    required this.paused,
    required this.onClose,
    required this.onView,
    required this.onAdd,
  });

  final DiscoverReel reel;
  final int item;
  final bool active;
  final Animation<double> progress;
  final bool paused;
  final VoidCallback onClose;
  final VoidCallback? onView;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final hue = colors.departmentAccent(reel.slug);
    final products = reel.products;
    if (products.isEmpty) return const SizedBox.shrink();
    final p = products[item.clamp(0, products.length - 1)];
    final still = context.reduceMotion;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color.lerp(colors.background, hue, 0.16)!, colors.background],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // progress segments
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, 0),
              child: Row(
                children: [
                  for (var i = 0; i < products.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i == products.length - 1 ? 0 : 4),
                        child: ClipRRect(
                          borderRadius: AppRadii.pillAll,
                          child: SizedBox(
                            height: 3,
                            child: i == item && active
                                ? AnimatedBuilder(
                                    animation: progress,
                                    builder: (_, _) => _Segment(fill: progress.value, color: colors.text),
                                  )
                                : _Segment(fill: i < item ? 1 : 0, color: colors.text),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xxs, 0),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: hue, shape: BoxShape.circle)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(header: true, child: Text(reel.department, maxLines: 1, style: t.titleMedium)),
                        Text(
                          reel.headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall!.copyWith(color: colors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (paused) Icon(Icons.pause_rounded, color: colors.muted, semanticLabel: 'Paused'),
                  IconButton(tooltip: 'Close', onPressed: onClose, icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            // the product, slowly drifting in (Ken Burns) while its segment runs
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: AnimatedSwitcher(
                  duration: context.motion(const Duration(milliseconds: 320)),
                  child: Center(
                    key: ValueKey(p.id),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: colors.imageWell, shape: BoxShape.circle),
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: RepaintBoundary(
                            child: active && !still
                                ? AnimatedBuilder(
                                    animation: progress,
                                    builder: (_, child) =>
                                        Transform.scale(scale: 1 + 0.06 * progress.value, child: child),
                                    child: _image(p),
                                  )
                                : _image(p),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // product card + CTAs
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadii.sheetAll,
                  boxShadow: colors.shadowMd,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (p.brand != null)
                      Text(p.brand!, maxLines: 1, style: t.labelMedium!.copyWith(color: colors.muted)),
                    Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleMedium),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Expanded(child: PriceText(p.price, compareAt: p.compareAtPrice, showDiscount: true, singleLine: true)),
                        if (p.rating > 0) RatingStars(p.rating, count: p.ratingCount),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: AppButton.secondary(label: 'View', expand: true, onPressed: onView)),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: AppButton(
                            label: 'Add to cart',
                            icon: Icons.shopping_bag_outlined,
                            expand: true,
                            onPressed: onAdd,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _image(ProductSummary p) => AppNetworkImage(
    p.thumbnail,
    fit: BoxFit.contain,
    backgroundColor: Colors.transparent,
    semanticLabel: p.title,
  );
}

class _Segment extends StatelessWidget {
  const _Segment({required this.fill, required this.color});

  final double fill;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: color.withValues(alpha: 0.18)),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fill.clamp(0.0, 1.0),
          child: ColoredBox(color: color),
        ),
      ],
    );
  }
}
