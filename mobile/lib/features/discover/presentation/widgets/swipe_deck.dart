import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/deck_model.dart';
import '../../data/discover_models.dart';

/// A physical card deck: drag the top card (it tilts with the drag and
/// where you grabbed it), fling or pass the threshold to commit, otherwise
/// it springs back. Up to three cards are stacked; the ones behind rise as
/// the top card leaves.
///
/// Performance: the drag lives in a [ValueNotifier]; only the transforms of
/// the three visible cards listen to it. Card contents sit in
/// RepaintBoundaries and are never rebuilt while dragging.
class SwipeDeck extends StatefulWidget {
  const SwipeDeck({super.key, required this.cards, required this.onSwiped, required this.onOpen});

  /// Top first.
  final List<DeckCard> cards;

  /// Called once the top card has flown off screen.
  final ValueChanged<SwipeAction> onSwiped;
  final ValueChanged<ProductSummary> onOpen;

  @override
  State<SwipeDeck> createState() => SwipeDeckState();
}

class SwipeDeckState extends State<SwipeDeck> with SingleTickerProviderStateMixin {
  final _drag = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _anim = AnimationController.unbounded(vsync: this)..addListener(_onTick);

  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  bool _grabbedBelow = false;
  bool _flying = false;
  SwipeAction? _armed;
  Size _size = Size.zero;

  void _onTick() => _drag.value = Offset.lerp(_from, _to, _anim.value)!;

  @override
  void dispose() {
    _anim.dispose();
    _drag.dispose();
    super.dispose();
  }

  /// Programmatic swipe (buttons, keyboard): the card flies the same way.
  void fling(SwipeAction action) {
    if (_flying || widget.cards.isEmpty) return;
    _flyOut(action, Offset.zero);
  }

  void _onPanStart(DragStartDetails d) {
    if (_flying) return;
    _anim.stop();
    _grabbedBelow = d.localPosition.dy > _size.height / 2;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (_flying) return;
    _drag.value += d.delta;
    // a tick when the card crosses into "will commit"
    final (action, strength) = DeckLogic.stamp(_drag.value, _size);
    final armed = strength >= 1 ? action : null;
    if (armed != _armed) {
      _armed = armed;
      if (armed != null) HapticFeedback.selectionClick();
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_flying) return;
    final v = d.velocity.pixelsPerSecond;
    final action = DeckLogic.decide(_drag.value, v, _size);
    _armed = null;
    action == null ? _springBack() : _flyOut(action, v);
  }

  void _springBack() {
    _from = _drag.value;
    _to = Offset.zero;
    if (context.reduceMotion) {
      _drag.value = Offset.zero;
      return;
    }
    _anim.value = 0;
    // slightly under-damped: the card overshoots a touch and settles
    _anim.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 420, damping: 26), 0, 1, 0));
  }

  void _flyOut(SwipeAction action, Offset velocity) {
    _flying = true;
    final w = _size.width;
    final h = _size.height;
    final start = _drag.value;
    _from = start;
    _to = switch (action) {
      SwipeAction.like => Offset(w * 1.6, start.dy + velocity.dy * 0.12),
      SwipeAction.pass => Offset(-w * 1.6, start.dy + velocity.dy * 0.12),
      SwipeAction.bag => Offset(start.dx + velocity.dx * 0.08, -h * 1.4),
    };
    if (context.reduceMotion) {
      _commit(action);
      return;
    }
    // faster flicks leave faster
    final speed = velocity.distance;
    final ms = (320 - math.min(160, speed / 20)).round();
    _anim.value = 0;
    _anim.animateTo(1, duration: Duration(milliseconds: ms), curve: Curves.easeOutCubic).whenCompleteOrCancel(() {
      if (mounted) _commit(action);
    });
  }

  void _commit(SwipeAction action) {
    HapticFeedback.lightImpact();
    widget.onSwiped(action);
    _flying = false;
    _drag.value = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.cards.take(3).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = cards.length - 1; i >= 0; i--)
              Positioned.fill(
                key: ValueKey(cards[i].id),
                child: i == 0 ? _topCard(cards[0]) : _behindCard(cards[i], i),
              ),
          ],
        );
      },
    );
  }

  Widget _topCard(DeckCard card) {
    final content = RepaintBoundary(child: DeckCardView(card: card));
    return GestureDetector(
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      onTap: () => widget.onOpen(card.product),
      child: ValueListenableBuilder<Offset>(
        valueListenable: _drag,
        child: content,
        builder: (context, drag, child) {
          final w = _size.width == 0 ? 1 : _size.width;
          final angle = (drag.dx / w) * 0.32 * (_grabbedBelow ? -1 : 1);
          final (action, strength) = DeckLogic.stamp(drag, _size);
          return Transform.translate(
            offset: drag,
            child: Transform.rotate(
              angle: angle,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  child!,
                  if (action != null && strength > 0.05) _Stamp(action: action, strength: strength),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _behindCard(DeckCard card, int depth) {
    final content = RepaintBoundary(child: DeckCardView(card: card));
    return IgnorePointer(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _drag,
        child: content,
        builder: (context, drag, child) {
          // rises toward the next slot as the top card travels away
          final progress = _size.width == 0 ? 0.0 : (drag.distance / (_size.width * 0.5)).clamp(0.0, 1.0);
          final slot = depth - progress;
          return Transform.translate(
            offset: Offset(0, 14 * slot),
            child: Transform.scale(scale: 1 - 0.05 * slot, alignment: Alignment.topCenter, child: child),
          );
        },
      ),
    );
  }
}

/// "LIKE" / "PASS" / "BAG" stamped on the card as it is dragged.
class _Stamp extends StatelessWidget {
  const _Stamp({required this.action, required this.strength});

  final SwipeAction action;
  final double strength;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = switch (action) {
      SwipeAction.like => colors.success,
      SwipeAction.pass => colors.sale,
      SwipeAction.bag => colors.primary,
    };
    final alignment = switch (action) {
      SwipeAction.like => const Alignment(-0.8, -0.82),
      SwipeAction.pass => const Alignment(0.8, -0.82),
      SwipeAction.bag => const Alignment(0, 0.35),
    };
    final angle = switch (action) {
      SwipeAction.like => -0.22,
      SwipeAction.pass => 0.22,
      SwipeAction.bag => -0.06,
    };
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Opacity(
          opacity: strength,
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: 0.9 + 0.1 * strength,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.85),
                  borderRadius: AppRadii.inputAll,
                  border: Border.all(color: color, width: 3),
                ),
                child: Text(
                  action.label.toUpperCase(),
                  style: context.textTheme.headlineSmall!.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The face of a deck card: big cut-out on the image well, category and
/// rating chips, "because you liked…" when injected, title and price.
class DeckCardView extends StatelessWidget {
  const DeckCardView({super.key, required this.card});

  final DeckCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final p = card.product;
    return Semantics(
      label: '${p.title}${p.brand == null ? '' : ' by ${p.brand}'}',
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: AppRadii.sheetAll,
          boxShadow: colors.shadowMd,
          border: Border.all(color: context.isDark ? colors.border : colors.border.withValues(alpha: 0.7)),
        ),
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: AppRadii.cardAll,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AppNetworkImage(
                        p.thumbnail,
                        fit: BoxFit.contain,
                        semanticLabel: p.title,
                        fallbackIcon: Icons.shopping_bag_outlined,
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.sm,
                      top: AppSpacing.sm,
                      right: 80,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _Chip(label: (p.category?.name ?? 'Pick').toUpperCase(), mono: true),
                      ),
                    ),
                    if (p.rating > 0)
                      Positioned(
                        right: AppSpacing.sm,
                        top: AppSpacing.sm,
                        child: _Chip(
                          label: p.rating.toStringAsFixed(1),
                          icon: Icons.star_rounded,
                          iconColor: colors.star,
                        ),
                      ),
                    if (card.reason != null)
                      Positioned(
                        left: AppSpacing.sm,
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.pillAll),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const AiSparkleIcon(size: 13),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    card.reason!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: t.labelMedium!.copyWith(color: colors.primary),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.brand != null)
                    Text(p.brand!, maxLines: 1, style: t.labelMedium!.copyWith(color: colors.muted)),
                  Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleLarge),
                  const SizedBox(height: AppSpacing.xxs),
                  PriceText(p.price, compareAt: p.compareAtPrice, showDiscount: true, singleLine: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.icon, this.iconColor, this.mono = false});

  final String label;
  final IconData? icon;
  final Color? iconColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: iconColor), const SizedBox(width: 3)],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (mono ? t.labelSmall : t.labelMedium)!.copyWith(
                color: colors.text,
                letterSpacing: mono ? 0.8 : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
