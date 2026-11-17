import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/product.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/deck_model.dart';
import '../data/discover_models.dart';
import '../data/discover_repository.dart';

/// The swipe deck. Swipes apply instantly (optimistic); the server's taste
/// and "next" picks are merged in when `POST /discover/swipe` answers.
final discoverControllerProvider = AsyncNotifierProvider.autoDispose<DiscoverController, DeckState>(
  DiscoverController.new,
);

/// Department stories for the reels row.
final discoverReelsProvider = FutureProvider.autoDispose<List<DiscoverReel>>(
  (ref) => ref.watch(discoverRepositoryProvider).reels(),
);

/// What the server did with a swipe: its answer, an error (e.g. 409 out of
/// stock on `bag`), or neither when the endpoint is missing / guest.
typedef SwipeOutcome = ({SwipeResponse? response, ApiException? error});

class DiscoverController extends AsyncNotifier<DeckState> {
  DiscoverRepository get _repo => ref.read(discoverRepositoryProvider);
  bool _refilling = false;

  @override
  Future<DeckState> build() async {
    final signedIn = ref.watch(isAuthenticatedProvider);
    final repo = ref.watch(discoverRepositoryProvider);
    // what the server already knows shows from the first card
    final taste = signedIn ? repo.taste() : Future<TasteProfile?>.value();
    final products = await repo.deck();
    return DeckState.initial(products).withTaste(await taste);
  }

  /// Swipes the top card at once (optimistic) and syncs in the background.
  /// Returns the record and the server's outcome, or null on an empty deck.
  ({SwipeRecord record, Future<SwipeOutcome> server})? swipe(SwipeAction action) {
    final s = state.value;
    if (s == null || s.isEmpty) return null;
    final next = DeckLogic.swipe(s, action);
    state = AsyncData(next);
    final record = next.history.last;
    final server = _sync(record);
    _maybeRefill();
    return (record: record, server: server);
  }

  /// Puts the last card back. Returns what was undone, or null.
  SwipeRecord? undo() {
    final s = state.value;
    if (s == null || !s.canUndo) return null;
    final record = s.history.last;
    state = AsyncData(DeckLogic.undo(s));
    return record;
  }

  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  Future<SwipeOutcome> _sync(SwipeRecord record) async {
    final product = record.card.product;
    SwipeResponse? res;
    ApiException? error;
    try {
      res = await _repo.swipe(product.id, record.action);
    } on ApiException catch (e) {
      error = e;
    } catch (_) {
      // learning continues locally; the swipe already happened on screen
    }
    var picks = res?.next ?? const <ProductSummary>[];
    // the server answers [] after a pass; only fall back when it didn't answer
    if (record.action.positive && res == null && error == null) picks = await _repo.similar(product.id);
    if (!ref.mounted) return (response: res, error: error);
    final s = state.value;
    // ignore answers for a swipe that has since been undone
    if (s != null && s.history.any((r) => r.card.id == product.id)) {
      var updated = s;
      if (res?.taste != null) updated = updated.withTaste(res!.taste);
      if (record.action.positive && picks.isNotEmpty) {
        updated = DeckLogic.inject(updated, picks.take(3), reason: DeckLogic.reasonFor(record.action, product));
      }
      if (!identical(updated, s)) state = AsyncData(updated);
    }
    return (response: res, error: error);
  }

  Future<void> _maybeRefill() async {
    final s = state.value;
    if (_refilling || s == null || s.queue.length > 4) return;
    _refilling = true;
    try {
      final more = await _repo.deck();
      if (!ref.mounted) return;
      final current = state.value;
      if (current != null) state = AsyncData(DeckLogic.append(current, more));
    } catch (_) {
      // the empty-deck state offers a manual reload
    } finally {
      _refilling = false;
    }
  }
}
