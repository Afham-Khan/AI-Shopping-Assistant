import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../data/ai_repository.dart';
import '../data/models/shopping_models.dart';

enum GiftStep { who, occasion, budget, interests }

/// Who the gift is for (shown as chips). The API gets the lower-case word.
const kGiftRecipients = [
  'Mom',
  'Dad',
  'Wife',
  'Husband',
  'Sister',
  'Brother',
  'Girlfriend',
  'Boyfriend',
  'Friend',
  'Kid',
  'Colleague',
  'Boss',
];

const kGiftOccasions = [
  'Birthday',
  'Anniversary',
  'Eid',
  'Wedding',
  'Graduation',
  'Housewarming',
  'Thank you',
  'Just because',
];

/// Slider stops (PKR): fine steps where most gifts sit, wider ones above.
const kGiftBudgets = [1000, 2000, 3000, 5000, 7500, 10000, 15000, 20000, 30000, 50000, 75000, 100000];

const kGiftInterests = [
  'Fashion',
  'Jewellery',
  'Perfumes',
  'Watches',
  'Tech & gadgets',
  'Gaming',
  'Makeup',
  'Skincare',
  'Sports & fitness',
  'Home decor',
  'Cooking',
  'Travel',
];

const kGiftMaxInterests = 4;

const _women = {'mom', 'wife', 'sister', 'girlfriend', 'aunt', 'grandma', 'daughter'};
const _men = {'dad', 'husband', 'brother', 'boyfriend', 'uncle', 'grandpa', 'son'};

/// Interests ordered for who the gift is for (best fits first), plus how many
/// of them are genuine suggestions.
({List<String> ordered, int suggested}) giftInterestsFor(String? recipient) {
  final r = (recipient ?? '').trim().toLowerCase();
  final lead = switch (r) {
    _ when _women.contains(r) => ['Jewellery', 'Perfumes', 'Makeup', 'Skincare', 'Fashion', 'Home decor'],
    _ when _men.contains(r) => ['Watches', 'Perfumes', 'Tech & gadgets', 'Gaming', 'Sports & fitness', 'Fashion'],
    'kid' => ['Gaming', 'Sports & fitness', 'Tech & gadgets'],
    'boss' || 'colleague' => ['Watches', 'Perfumes', 'Tech & gadgets', 'Cooking'],
    _ => const <String>[],
  };
  return (ordered: [...lead, ...kGiftInterests.where((i) => !lead.contains(i))], suggested: lead.length);
}

/// A sensible starting budget for who it's for.
int giftDefaultBudget(String? recipient) {
  final r = (recipient ?? '').trim().toLowerCase();
  return switch (r) {
    'kid' || 'colleague' || 'boss' => 5000,
    'wife' || 'husband' || 'girlfriend' || 'boyfriend' => 20000,
    _ => 10000,
  };
}

/// "Gift for my mom for birthday under Rs 10,000, they like jewellery and perfumes"
/// (what "Ask Zel instead" sends to the assistant).
String giftPrompt({required String? recipient, required String occasion, required int budget, Iterable<String> interests = const []}) {
  final who = (recipient ?? '').trim().isEmpty ? 'someone' : 'my ${recipient!.trim().toLowerCase()}';
  final occ = occasion.trim().isEmpty ? '' : ' for ${occasion.trim().toLowerCase()}';
  final likes = interests.map((i) => i.toLowerCase()).toList();
  final tail = likes.isEmpty
      ? ''
      : ', they like ${likes.length == 1 ? likes.first : '${likes.sublist(0, likes.length - 1).join(', ')} and ${likes.last}'}';
  return 'Gift for $who$occ under ${Formatters.price(budget)}$tail';
}

@immutable
class GiftFinderState {
  const GiftFinderState({
    this.step = GiftStep.who,
    this.recipient,
    this.occasion = 'Birthday',
    this.budget = 10000,
    this.interests = const {},
    this.budgetTouched = false,
    this.result,
  });

  final GiftStep step;
  final String? recipient;
  final String occasion;
  final int budget;
  final Set<String> interests;

  /// Once the shopper moves the slider, "who" changes stop resetting it.
  final bool budgetTouched;

  /// Null until they ask for ideas.
  final AsyncValue<GiftResult>? result;

  bool get showingResults => result != null;
  bool get isLastStep => step == GiftStep.interests;

  /// Only "who" is required; the rest have defaults.
  bool get canContinue => step != GiftStep.who || (recipient?.trim().length ?? 0) >= 2;

  GiftFinderState copyWith({
    GiftStep? step,
    String? recipient,
    bool clearRecipient = false,
    String? occasion,
    int? budget,
    Set<String>? interests,
    bool? budgetTouched,
    AsyncValue<GiftResult>? result,
    bool clearResult = false,
  }) => GiftFinderState(
    step: step ?? this.step,
    recipient: clearRecipient ? null : (recipient ?? this.recipient),
    occasion: occasion ?? this.occasion,
    budget: budget ?? this.budget,
    interests: interests ?? this.interests,
    budgetTouched: budgetTouched ?? this.budgetTouched,
    result: clearResult ? null : (result ?? this.result),
  );
}

/// Step flow state for the Gift Finder (who → occasion → budget → interests →
/// results). autoDispose: leaving the screen starts over.
final giftFinderProvider = NotifierProvider.autoDispose<GiftFinderController, GiftFinderState>(GiftFinderController.new);

class GiftFinderController extends Notifier<GiftFinderState> {
  int _epoch = 0;

  @override
  GiftFinderState build() => const GiftFinderState();

  void setRecipient(String? value) {
    final clean = value?.trim();
    if (clean == null || clean.isEmpty) {
      state = state.copyWith(clearRecipient: true);
      return;
    }
    state = state.copyWith(
      recipient: clean,
      // smart default: a spouse gift usually costs more than a colleague's
      budget: state.budgetTouched ? null : giftDefaultBudget(clean),
      // interests picked for someone else rarely carry over
      interests: <String>{},
    );
  }

  void setOccasion(String value) => state = state.copyWith(occasion: value);

  void setBudget(int value) => state = state.copyWith(budget: value, budgetTouched: true);

  void toggleInterest(String value) {
    final next = {...state.interests};
    if (!next.remove(value)) {
      if (next.length >= kGiftMaxInterests) return;
      next.add(value);
    }
    state = state.copyWith(interests: next);
  }

  void clearInterests() => state = state.copyWith(interests: <String>{});

  /// Next step, or ask for ideas on the last one.
  Future<void> next() async {
    if (!state.canContinue) return;
    if (state.isLastStep) return submit();
    state = state.copyWith(step: GiftStep.values[state.step.index + 1]);
  }

  /// Back one step; from the results back to the last question.
  void back() {
    if (state.showingResults) {
      _epoch++;
      state = state.copyWith(clearResult: true, step: GiftStep.interests);
    } else if (state.step.index > 0) {
      state = state.copyWith(step: GiftStep.values[state.step.index - 1]);
    }
  }

  void goTo(GiftStep step) {
    _epoch++;
    state = state.copyWith(step: step, clearResult: true);
  }

  void restart() {
    _epoch++;
    state = const GiftFinderState();
  }

  Future<void> submit() async {
    final recipient = state.recipient;
    if (recipient == null) return;
    final epoch = ++_epoch;
    state = state.copyWith(result: const AsyncLoading());
    try {
      final result = await ref
          .read(aiRepositoryProvider)
          .gift(
            recipient: recipient.toLowerCase(),
            occasion: state.occasion.toLowerCase(),
            budget: state.budget,
            interests: [for (final i in state.interests) i.toLowerCase()],
          );
      if (!ref.mounted || epoch != _epoch) return;
      state = state.copyWith(result: AsyncData(result));
    } on ApiException catch (e, st) {
      if (!ref.mounted || epoch != _epoch) return;
      state = state.copyWith(result: AsyncError(e, st));
    }
  }

  /// The prompt "Ask Zel instead" opens the assistant with.
  String get promptForZel => giftPrompt(
    recipient: state.recipient,
    occasion: state.occasion,
    budget: state.budget,
    interests: state.interests,
  );
}
