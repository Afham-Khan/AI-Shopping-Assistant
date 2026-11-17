import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../core/models/product.dart';
import '../../../core/utils/formatters.dart';
import 'discover_models.dart';

/// Pure deck logic (no Flutter widgets, fully unit-tested): the queue,
/// swipe history with undo, "because you liked…" injection, the gesture
/// decision and a local taste estimate used until the server answers.

/// A card in the deck; [reason] is set on injected cards.
@immutable
class DeckCard {
  const DeckCard(this.product, {this.reason});

  final ProductSummary product;
  final String? reason;

  int get id => product.id;
}

@immutable
class SwipeRecord {
  const SwipeRecord(this.card, this.action);

  final DeckCard card;
  final SwipeAction action;
}

@immutable
class DeckState {
  const DeckState({this.queue = const [], this.history = const [], this.serverTaste});

  factory DeckState.initial(Iterable<ProductSummary> products) {
    final seen = <int>{};
    return DeckState(
      queue: [
        for (final p in products)
          if (p.id != 0 && seen.add(p.id)) DeckCard(p),
      ],
    );
  }

  /// `queue.first` is the card on top.
  final List<DeckCard> queue;
  final List<SwipeRecord> history;

  /// Latest taste from the server (`GET /discover/taste` on open, then every
  /// `POST /discover/swipe`); null for guests or until it answers.
  final TasteProfile? serverTaste;

  DeckCard? get top => queue.isEmpty ? null : queue.first;
  bool get isEmpty => queue.isEmpty;
  bool get canUndo => history.isNotEmpty;

  int count(SwipeAction a) => history.where((r) => r.action == a).length;

  /// Server taste when available, else the local estimate.
  TasteProfile get taste => serverTaste ?? DeckLogic.localTaste(history);

  /// Replaces the server taste when [taste] is non-null.
  DeckState withTaste(TasteProfile? taste) => taste == null ? this : copyWith(serverTaste: () => taste);

  DeckState copyWith({List<DeckCard>? queue, List<SwipeRecord>? history, TasteProfile? Function()? serverTaste}) =>
      DeckState(
        queue: queue ?? this.queue,
        history: history ?? this.history,
        serverTaste: serverTaste == null ? this.serverTaste : serverTaste(),
      );
}

abstract final class DeckLogic {
  /// Fling speed (logical px/s) that commits a swipe regardless of distance.
  static const flingVelocity = 900.0;

  /// Fraction of the card width (horizontal) / height (up) that commits.
  static const horizontalThreshold = 0.3;
  static const verticalThreshold = 0.22;

  /// Removes the top card and records [action]. No-op on an empty deck.
  static DeckState swipe(DeckState s, SwipeAction action) {
    if (s.queue.isEmpty) return s;
    return s.copyWith(
      queue: s.queue.sublist(1),
      history: [...s.history, SwipeRecord(s.queue.first, action)],
    );
  }

  /// Puts the last swiped card back on top. The server taste is kept: the
  /// API has no "un-swipe", so its readout still includes that answer.
  static DeckState undo(DeckState s) {
    if (s.history.isEmpty) return s;
    final last = s.history.last;
    return DeckState(
      queue: [last.card, ...s.queue.where((c) => c.id != last.card.id)],
      history: s.history.sublist(0, s.history.length - 1),
      serverTaste: s.serverTaste,
    );
  }

  /// Inserts [products] right behind the top card ([at] = 1), tagged with
  /// [reason]. Skips anything already queued or already swiped.
  static DeckState inject(DeckState s, Iterable<ProductSummary> products, {required String reason, int at = 1}) {
    final known = {for (final c in s.queue) c.id, for (final r in s.history) r.card.id};
    final fresh = <DeckCard>[];
    for (final p in products) {
      if (p.id != 0 && known.add(p.id)) fresh.add(DeckCard(p, reason: reason));
    }
    if (fresh.isEmpty) return s;
    final i = at.clamp(0, s.queue.length);
    return s.copyWith(queue: [...s.queue.sublist(0, i), ...fresh, ...s.queue.sublist(i)]);
  }

  /// Adds [products] to the bottom of the deck (refill), skipping known ids.
  static DeckState append(DeckState s, Iterable<ProductSummary> products) {
    final known = {for (final c in s.queue) c.id, for (final r in s.history) r.card.id};
    return s.copyWith(
      queue: [
        ...s.queue,
        for (final p in products)
          if (p.id != 0 && known.add(p.id)) DeckCard(p),
      ],
    );
  }

  /// What a released drag means: a committed action, or null (spring back).
  /// Up wins only when the drag is mostly vertical.
  static SwipeAction? decide(Offset drag, Offset velocity, Size card) {
    final up = -drag.dy;
    final mostlyUp = up > drag.dx.abs();
    if ((mostlyUp && up > card.height * verticalThreshold) ||
        (velocity.dy < -flingVelocity && -velocity.dy > velocity.dx.abs() && drag.dy <= 0)) {
      return SwipeAction.bag;
    }
    if (drag.dx > card.width * horizontalThreshold || (velocity.dx > flingVelocity && drag.dx > 0)) {
      return SwipeAction.like;
    }
    if (drag.dx < -card.width * horizontalThreshold || (velocity.dx < -flingVelocity && drag.dx < 0)) {
      return SwipeAction.pass;
    }
    return null;
  }

  /// Which stamp the drag is heading toward and how strongly (0..1).
  static (SwipeAction?, double) stamp(Offset drag, Size card) {
    if (card.isEmpty) return (null, 0);
    final up = -drag.dy;
    if (up > drag.dx.abs() && up > 8) {
      return (SwipeAction.bag, (up / (card.height * verticalThreshold)).clamp(0.0, 1.0));
    }
    if (drag.dx.abs() < 8) return (null, 0);
    final strength = (drag.dx.abs() / (card.width * horizontalThreshold)).clamp(0.0, 1.0);
    return (drag.dx > 0 ? SwipeAction.like : SwipeAction.pass, strength);
  }

  /// Local estimate of the shopper's taste from the swipe history.
  static TasteProfile localTaste(List<SwipeRecord> history) {
    if (history.isEmpty) return TasteProfile.empty;
    final weights = <String, double>{};
    final prices = <double>[];
    final brands = <String, int>{};
    var positives = 0;
    for (final r in history) {
      if (!r.action.positive) continue;
      positives++;
      final w = r.action == SwipeAction.bag ? 1.6 : 1.0;
      final name = r.card.product.category?.name ?? 'Other';
      weights[name] = (weights[name] ?? 0) + w;
      if (r.card.product.price > 0) prices.add(r.card.product.price);
      final brand = r.card.product.brand;
      if (brand != null && brand.isNotEmpty) brands[brand] = (brands[brand] ?? 0) + 1;
    }
    final total = weights.values.fold(0.0, (a, b) => a + b);
    final shares = [
      for (final e in weights.entries) TasteShare(name: e.key, share: total == 0 ? 0 : e.value / total),
    ]..sort((a, b) => b.share.compareTo(a.share));

    final appetite = prices.isEmpty
        ? const PriceAppetite()
        : PriceAppetite(
            min: prices.reduce(math.min),
            max: prices.reduce(math.max),
            avg: prices.reduce((a, b) => a + b) / prices.length,
          );

    // more swipes → more confident; a deck of only passes teaches little
    final n = history.length;
    final confidence = (1 - math.exp(-n / 10)) * (positives == 0 ? 0.3 : 1.0);

    final signals = <String>[
      if (shares.isNotEmpty) 'Into ${shares.first.name.toLowerCase()}',
      if (prices.length >= 2) 'Keeps around ${Formatters.priceCompact(appetite.avg)}',
      for (final e in brands.entries)
        if (e.value >= 2) 'Comes back to ${e.key}',
      if (n >= 6 && positives / n < 0.25) 'Picky: passes most cards',
    ];

    return TasteProfile(
      categories: shares.take(5).toList(),
      priceAppetite: appetite,
      confidence: confidence.clamp(0.0, 1.0),
      topSignals: signals.take(4).toList(),
    );
  }

  /// "Because you liked …" copy for injected cards.
  static String reasonFor(SwipeAction action, ProductSummary source) {
    final name = source.title.length > 28 ? '${source.title.substring(0, 27).trimRight()}…' : source.title;
    return action == SwipeAction.bag ? 'Goes with $name' : 'Because you liked $name';
  }
}

/// Position in the reels viewer: which department story and which product.
@immutable
class ReelsCursor {
  const ReelsCursor(this.reel, this.item);

  final int reel;
  final int item;

  /// Next product, rolling into the next non-empty story; null at the very end.
  ReelsCursor? next(List<int> lengths) {
    if (reel < lengths.length && item + 1 < lengths[reel]) return ReelsCursor(reel, item + 1);
    for (var r = reel + 1; r < lengths.length; r++) {
      if (lengths[r] > 0) return ReelsCursor(r, 0);
    }
    return null;
  }

  /// Previous product; from a story's first product, the start of the
  /// previous non-empty story (or a restart of the first one).
  ReelsCursor previous(List<int> lengths) {
    if (item > 0) return ReelsCursor(reel, item - 1);
    for (var r = reel - 1; r >= 0; r--) {
      if (lengths[r] > 0) return ReelsCursor(r, 0);
    }
    return ReelsCursor(reel, 0);
  }

  @override
  bool operator ==(Object other) => other is ReelsCursor && other.reel == reel && other.item == item;

  @override
  int get hashCode => Object.hash(reel, item);

  @override
  String toString() => 'ReelsCursor($reel, $item)';
}
