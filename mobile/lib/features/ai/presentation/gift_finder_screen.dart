import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/product.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/models/shopping_models.dart';
import '../providers/gift_finder_controller.dart';
import 'ai_actions.dart';
import 'widgets/ai_ui.dart';

/// Gift Finder: who → occasion → budget → interests, with smart defaults,
/// then a curated collection with a reason for every pick. "Ask Zel instead"
/// hands the same brief to the assistant.
class GiftFinderScreen extends ConsumerWidget {
  const GiftFinderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(giftFinderProvider);
    final c = ref.read(giftFinderProvider.notifier);

    // Back steps back through the questions before it leaves the screen
    return PopScope(
      canPop: !s.showingResults && s.step == GiftStep.who,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gift finder'),
          actions: [
            if (s.showingResults || s.step != GiftStep.who) TextButton(onPressed: c.restart, child: const Text('Start over')),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        bottomNavigationBar: s.showingResults ? null : _Footer(state: s),
        body: s.showingResults ? _Results(state: s) : _Steps(state: s),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// steps

class _Steps extends ConsumerWidget {
  const _Steps({required this.state});

  final GiftFinderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.textTheme;
    final colors = context.colors;
    final (title, subtitle) = switch (state.step) {
      GiftStep.who => ('Who is it for?', 'Pick one, or type someone else.'),
      GiftStep.occasion => ('What is the occasion?', 'Zel starts with birthdays. Change it if it is something else.'),
      GiftStep.budget => ('How much would you like to spend?', 'The most you want to pay for one gift.'),
      GiftStep.interests => ('What are they into?', 'Pick up to $kGiftMaxInterests. Not sure? Skip it and Zel will mix it up.'),
    };

    final Widget content = switch (state.step) {
      GiftStep.who => _WhoStep(state: state),
      GiftStep.occasion => _OccasionStep(state: state),
      GiftStep.budget => _BudgetStep(state: state),
      GiftStep.interests => _InterestsStep(state: state),
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.sm, context.pagePadding, AppSpacing.xl),
      children: [
        ResponsiveCenter(
          maxWidth: 560,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Progress(step: state.step),
              const SizedBox(height: AppSpacing.lg),
              AnimatedSwitcher(
                duration: context.motion(AppDurations.normal),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: Column(
                  key: ValueKey(state.step),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(header: true, child: Text(title, style: t.headlineSmall)),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(subtitle, style: t.bodyMedium!.copyWith(color: colors.muted, height: 1.4)),
                    const SizedBox(height: AppSpacing.lg),
                    content,
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.step});

  final GiftStep step;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final n = step.index + 1;
    return Semantics(
      label: 'Step $n of ${GiftStep.values.length}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 0; i < GiftStep.values.length; i++)
                Expanded(
                  child: AnimatedContainer(
                    duration: context.motion(AppDurations.normal),
                    height: 5,
                    margin: EdgeInsets.only(right: i == GiftStep.values.length - 1 ? 0 : 6),
                    decoration: BoxDecoration(
                      color: i < n ? colors.primary : colors.surfaceRaised,
                      borderRadius: AppRadii.pillAll,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Step $n of ${GiftStep.values.length}', style: context.textTheme.labelMedium!.copyWith(color: colors.muted)),
        ],
      ),
    );
  }
}

class _WhoStep extends ConsumerStatefulWidget {
  const _WhoStep({required this.state});

  final GiftFinderState state;

  @override
  ConsumerState<_WhoStep> createState() => _WhoStepState();
}

class _WhoStepState extends ConsumerState<_WhoStep> {
  late final _other = TextEditingController(
    text: widget.state.recipient != null && !kGiftRecipients.contains(widget.state.recipient) ? widget.state.recipient : '',
  );

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.read(giftFinderProvider.notifier);
    final selected = widget.state.recipient;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final r in kGiftRecipients)
              ChoiceChip(
                label: Text(r),
                selected: selected == r,
                onSelected: (_) {
                  _other.clear();
                  c.setRecipient(r);
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppTextField(
          controller: _other,
          label: 'Someone else?',
          hint: 'e.g. neighbour, teacher, cousin',
          prefixIcon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
          maxLength: 40,
          onChanged: (v) => c.setRecipient(v),
          onSubmitted: (_) => c.next(),
        ),
      ],
    );
  }
}

class _OccasionStep extends ConsumerWidget {
  const _OccasionStep({required this.state});

  final GiftFinderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(giftFinderProvider.notifier);
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final o in kGiftOccasions)
          ChoiceChip(label: Text(o), selected: state.occasion == o, onSelected: (_) => c.setOccasion(o)),
      ],
    );
  }
}

class _BudgetStep extends ConsumerWidget {
  const _BudgetStep({required this.state});

  final GiftFinderState state;

  static int _nearest(int budget) {
    var best = 0;
    for (var i = 0; i < kGiftBudgets.length; i++) {
      if ((kGiftBudgets[i] - budget).abs() < (kGiftBudgets[best] - budget).abs()) best = i;
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(giftFinderProvider.notifier);
    final t = context.textTheme;
    final colors = context.colors;
    final index = _nearest(state.budget);
    const quick = [2000, 5000, 10000, 20000, 50000];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Semantics(
            liveRegion: true,
            child: Text(
              'Up to ${Formatters.price(kGiftBudgets[index])}',
              style: t.headlineMedium!.copyWith(color: colors.primary, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        Slider(
          value: index.toDouble(),
          min: 0,
          max: (kGiftBudgets.length - 1).toDouble(),
          divisions: kGiftBudgets.length - 1,
          label: Formatters.price(kGiftBudgets[index]),
          semanticFormatterCallback: (v) => 'Up to ${Formatters.price(kGiftBudgets[v.round()])}',
          onChanged: (v) => c.setBudget(kGiftBudgets[v.round()]),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Formatters.priceCompact(kGiftBudgets.first), style: t.labelSmall!.copyWith(color: colors.faint)),
            Text(Formatters.priceCompact(kGiftBudgets.last), style: t.labelSmall!.copyWith(color: colors.faint)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final q in quick)
              ChoiceChip(
                label: Text(Formatters.priceCompact(q)),
                selected: kGiftBudgets[index] == q,
                onSelected: (_) => c.setBudget(q),
              ),
          ],
        ),
      ],
    );
  }
}

class _InterestsStep extends ConsumerWidget {
  const _InterestsStep({required this.state});

  final GiftFinderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(giftFinderProvider.notifier);
    final t = context.textTheme;
    final colors = context.colors;
    final plan = giftInterestsFor(state.recipient);
    final full = state.interests.length >= kGiftMaxInterests;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (plan.suggested > 0) ...[
          Row(
            children: [
              const AiSparkleIcon(size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Popular picks for your ${state.recipient?.toLowerCase()} come first.',
                  style: t.bodySmall!.copyWith(color: colors.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            ChoiceChip(label: const Text('Surprise me'), selected: state.interests.isEmpty, onSelected: (_) => c.clearInterests()),
            for (final i in plan.ordered)
              FilterChip(
                label: Text(i),
                selected: state.interests.contains(i),
                onSelected: !state.interests.contains(i) && full ? null : (_) => c.toggleInterest(i),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        _BriefSummary(state: state),
      ],
    );
  }
}

/// The brief so far, with a way back to change any part.
class _BriefSummary extends ConsumerWidget {
  const _BriefSummary({required this.state});

  final GiftFinderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(giftFinderProvider.notifier);
    final colors = context.colors;
    final t = context.textTheme;
    Widget row(String label, String value, GiftStep step) => InkWell(
      onTap: () => c.goTo(step),
      borderRadius: AppRadii.inputAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(width: 82, child: Text(label, style: t.labelMedium!.copyWith(color: colors.muted))),
            Expanded(child: Text(value, style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Icon(Icons.edit_outlined, size: 16, color: colors.faint),
          ],
        ),
      ),
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Column(
        children: [
          row('For', state.recipient ?? '-', GiftStep.who),
          row('Occasion', state.occasion, GiftStep.occasion),
          row('Budget', 'Up to ${Formatters.price(state.budget)}', GiftStep.budget),
        ],
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state});

  final GiftFinderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(giftFinderProvider.notifier);
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.sm, context.pagePadding, AppSpacing.sm),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Row(
                children: [
                  if (state.step != GiftStep.who) ...[
                    AppButton.secondary(label: 'Back', icon: Icons.arrow_back_rounded, onPressed: c.back),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(
                    child: AppButton(
                      label: state.isLastStep ? 'Find gifts' : 'Next',
                      icon: state.isLastStep ? Icons.card_giftcard_outlined : null,
                      trailingIcon: state.isLastStep ? null : Icons.arrow_forward_rounded,
                      expand: true,
                      onPressed: state.canContinue ? c.next : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// results

class _Results extends ConsumerWidget {
  const _Results({required this.state});

  final GiftFinderState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(giftFinderProvider.notifier);
    final result = state.result!;

    void askZel() => context.go(Routes.assistantWith(prompt: c.promptForZel));

    return ListView(
      padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.sm, context.pagePadding, AppSpacing.xxl),
      children: [
        ResponsiveCenter(
          maxWidth: 640,
          padding: EdgeInsets.zero,
          child: switch (result) {
            AsyncValue(:final value?) => _Collection(state: state, result: value, onAskZel: askZel),
            AsyncValue(:final error?) => Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xl),
              child: Column(
                children: [
                  ErrorState(error: error, onRetry: c.submit),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton.secondary(label: 'Ask ${AppConfig.assistantName} instead', icon: Icons.chat_bubble_outline_rounded, onPressed: askZel),
                ],
              ),
            ),
            _ => const _Loading(),
          },
        ),
      ],
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AiThinking(
            messages: ['Thinking about who it is for…', 'Looking within your budget…', 'Picking a thoughtful mix…'],
            lines: 0,
          ),
          SizedBox(height: AppSpacing.lg),
          Skeleton(height: 124, borderRadius: AppRadii.cardAll),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 124, borderRadius: AppRadii.cardAll),
          SizedBox(height: AppSpacing.sm),
          Skeleton(height: 124, borderRadius: AppRadii.cardAll),
        ],
      ),
    );
  }
}

class _Collection extends ConsumerWidget {
  const _Collection({required this.state, required this.result, required this.onAskZel});

  final GiftFinderState state;
  final GiftResult result;
  final VoidCallback onAskZel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.read(giftFinderProvider.notifier);
    final t = context.textTheme;
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(padding: EdgeInsets.only(top: 2), child: AiSparkleIcon(size: 18)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Semantics(header: true, child: Text(result.title, style: t.titleMedium))),
                ],
              ),
              if (result.note.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(result.note, style: t.bodyMedium!.copyWith(height: 1.5)),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusBadge(state.recipient ?? 'Someone', icon: Icons.person_outline_rounded),
                  StatusBadge(state.occasion, icon: Icons.cake_outlined),
                  StatusBadge('Up to ${Formatters.priceCompact(state.budget)}', icon: Icons.sell_outlined),
                  for (final i in state.interests) StatusBadge(i),
                  TextButton(
                    onPressed: () => c.goTo(GiftStep.who),
                    style: TextButton.styleFrom(minimumSize: const Size(44, 36)),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (result.isEmpty)
          EmptyState(
            icon: Icons.card_giftcard_rounded,
            title: 'No gifts for that mix',
            message: 'Try a higher budget or a different interest, or let Zel have a go.',
            actionLabel: 'Change the brief',
            onAction: () => c.goTo(GiftStep.budget),
          )
        else ...[
          Text(
            '${Formatters.plural(result.products.length, 'idea')} picked for you',
            style: t.labelLarge!.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final p in result.products)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: GiftCard(product: p),
            ),
        ],
        const SizedBox(height: AppSpacing.sm),
        AppButton.secondary(label: 'Ask ${AppConfig.assistantName} instead', icon: Icons.chat_bubble_outline_rounded, expand: true, onPressed: onAskZel),
        const SizedBox(height: AppSpacing.xs),
        AppButton.ghost(label: 'Change the brief', expand: true, onPressed: c.back),
      ],
    );
  }
}

/// One gift idea: photo, price, why it fits, and a quick add.
class GiftCard extends ConsumerStatefulWidget {
  const GiftCard({super.key, required this.product});

  final ProductSummary product;

  @override
  ConsumerState<GiftCard> createState() => _GiftCardState();
}

class _GiftCardState extends ConsumerState<GiftCard> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    try {
      await quickAddToCart(context, ref, widget.product, source: 'gift_finder');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final colors = context.colors;
    final t = context.textTheme;
    final reasons = (p.match?.reasons ?? const <String>[]).take(3).toList();

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      semanticLabel: '${p.title}, ${Formatters.price(p.price)}',
      onTap: () => openAiProduct(context, ref, p.id, source: 'gift_finder'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppNetworkImage(
            p.thumbnail,
            width: 92,
            height: 92,
            fit: BoxFit.contain,
            borderRadius: AppRadii.inputAll,
            semanticLabel: p.title,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                PriceText(p.price, compareAt: p.compareAtPrice, size: PriceSize.small, showDiscount: true),
                for (final r in reasons)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(Icons.check_rounded, size: 14, color: colors.primary),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: Text(r, style: t.bodySmall!.copyWith(color: colors.muted, height: 1.35))),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xs),
                AppButton.secondary(
                  label: p.inStock ? 'Add to cart' : 'Out of stock',
                  icon: p.inStock ? Icons.add_shopping_cart_rounded : null,
                  size: AppButtonSize.small,
                  loading: _adding,
                  semanticLabel: 'Add ${p.title} to cart',
                  onPressed: p.inStock ? _add : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
