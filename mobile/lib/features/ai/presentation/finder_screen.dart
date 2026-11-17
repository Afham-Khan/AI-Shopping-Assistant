import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/ai_repository.dart';
import '../data/models/ai_models.dart';
import '../providers/ai_providers.dart';
import 'widgets/ai_product_widgets.dart';
import 'widgets/ai_ui.dart';
import 'widgets/simple_markdown.dart';

/// Guided finder (GET/POST /ai/finder): pick a department, answer a few
/// questions step by step, get ranked results with a summary.
class FinderScreen extends ConsumerStatefulWidget {
  const FinderScreen({super.key});

  @override
  ConsumerState<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends ConsumerState<FinderScreen> {
  FinderFlow? _flow;
  int _step = 0;
  bool _forward = true;
  final Map<String, Object?> _answers = {};

  bool _loading = false;
  AiProductsResult? _result;
  ApiException? _error;

  void _pick(FinderFlow flow) => setState(() {
    _flow = flow;
    _step = 0;
    _forward = true;
    _answers.clear();
    _result = null;
    _error = null;
  });

  void _back() => setState(() {
    _forward = false;
    if (_result != null || _error != null) {
      _result = null;
      _error = null;
    } else if (_step > 0) {
      _step--;
    } else {
      _flow = null;
    }
  });

  void _next() {
    final flow = _flow!;
    if (_step < flow.questions.length - 1) {
      setState(() {
        _forward = true;
        _step++;
      });
    } else {
      _submit();
    }
  }

  Future<void> _submit() async {
    final flow = _flow!;
    setState(() {
      _forward = true;
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(aiRepositoryProvider).finderResults(flow.slug, Map.of(_answers));
      if (mounted) setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _restart() => setState(() {
    _flow = null;
    _answers.clear();
    _result = null;
    _error = null;
    _step = 0;
  });

  @override
  Widget build(BuildContext context) {
    final inFlow = _flow != null;
    return PopScope(
      canPop: !inFlow,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_flow?.title ?? 'Guided finder'),
          actions: [
            if (inFlow) TextButton(onPressed: _restart, child: const Text('Start over')),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        body: AnimatedSwitcher(
          duration: context.motion(AppDurations.normal),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(begin: Offset(_forward ? 0.04 : -0.04, 0), end: Offset.zero).animate(anim),
              child: child,
            ),
          ),
          child: KeyedSubtree(key: ValueKey(_viewKey), child: _body(context)),
        ),
      ),
    );
  }

  String get _viewKey {
    if (_flow == null) return 'pick';
    if (_loading) return 'loading';
    if (_result != null) return 'result';
    if (_error != null) return 'error';
    return 'q$_step';
  }

  Widget _body(BuildContext context) {
    final flow = _flow;
    if (flow == null) return _DepartmentPicker(onPick: _pick);
    if (_loading) {
      return Padding(
        padding: EdgeInsets.all(context.pagePadding),
        child: const AiThinking(messages: ['Matching your answers…', 'Scoring products…', 'Picking the best fits…'], lines: 4),
      );
    }
    if (_error != null) return ErrorState(error: _error, onRetry: _submit);
    if (_result != null) return _Results(result: _result!, onRestart: _restart, onAdjust: _back);
    if (flow.questions.isEmpty) {
      return EmptyState(title: 'No questions for this department', actionLabel: 'Show picks', onAction: _submit);
    }

    final q = flow.questions[_step];
    final total = flow.questions.length;
    final answered = _hasAnswer(q);
    return Column(
      children: [
        Expanded(
          child: ResponsiveCenter(
            maxWidth: 720,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: [
                Row(
                  children: [
                    Text('Step ${_step + 1} of $total', style: context.textTheme.labelLarge!.copyWith(color: context.colors.muted)),
                    const Spacer(),
                    if (!answered) Text('Optional', style: context.textTheme.bodySmall),
                  ],
                ),
                AppSpacing.gapXs,
                AiConfidenceBar(value: (_step + 1) / total, height: 6, semanticLabel: 'Progress'),
                AppSpacing.gapLg,
                Semantics(header: true, child: Text(q.title, style: context.textTheme.headlineSmall)),
                if (q.type == FinderQuestionType.multi) ...[
                  AppSpacing.gapXxs,
                  Text('Pick as many as you like', style: context.textTheme.bodySmall),
                ],
                AppSpacing.gapLg,
                _QuestionInput(
                  question: q,
                  value: _answers[q.id],
                  onChanged: (v) => setState(() => v == null ? _answers.remove(q.id) : _answers[q.id] = v),
                ),
              ],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: context.colors.border))),
          child: SafeArea(
            top: false,
            child: ResponsiveCenter(
              maxWidth: 720,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(child: AppButton.secondary(label: 'Back', icon: Icons.arrow_back_rounded, onPressed: _back)),
                    AppSpacing.gapSm,
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        label: _step == total - 1 ? 'Show my matches' : (answered ? 'Next' : 'Skip'),
                        trailingIcon: _step == total - 1 ? Icons.auto_awesome : Icons.arrow_forward_rounded,
                        onPressed: _next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool _hasAnswer(FinderQuestion q) {
    final v = _answers[q.id];
    if (v == null) return false;
    if (v is List) return v.isNotEmpty;
    return true;
  }
}

class _DepartmentPicker extends ConsumerWidget {
  const _DepartmentPicker({required this.onPick});

  final ValueChanged<FinderFlow> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(finderFlowsProvider);
    final t = context.textTheme;
    return async.when(
      loading: () => Padding(padding: EdgeInsets.all(context.pagePadding), child: const SkeletonList(count: 5)),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(finderFlowsProvider)),
      data: (flows) => flows.isEmpty
          ? const EmptyState(icon: Icons.quiz_outlined, title: 'Finder is not available yet')
          : ResponsiveCenter(
              maxWidth: 900,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                children: [
                  const AiHeader(title: 'Not sure what to buy?', caption: 'Answer a few quick questions and the AI shortlists the best fits.'),
                  AppSpacing.gapLg,
                  Text('What are you shopping for?', style: t.titleMedium),
                  AppSpacing.gapSm,
                  LayoutBuilder(
                    builder: (context, c) {
                      final cols = c.maxWidth >= 640 ? 3 : 2;
                      final w = (c.maxWidth - AppSpacing.sm * (cols - 1)) / cols;
                      return Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (var i = 0; i < flows.length; i++)
                            SizedBox(
                              width: w,
                              child: SlideFadeIn(
                                delay: Duration(milliseconds: 50 * i),
                                child: _DepartmentCard(flow: flows[i], onTap: () => onPick(flows[i])),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}

class _DepartmentCard extends StatelessWidget {
  const _DepartmentCard({required this.flow, required this.onTap});

  final FinderFlow flow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = AppColors.departmentAccent(flow.slug);
    return Semantics(
      button: true,
      label: flow.title,
      excludeSemantics: true,
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.border)),
        child: InkWell(
          borderRadius: AppRadii.cardAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: AppRadii.inputAll),
                  child: Icon(CategoryIcons.of(flow.slug), color: accent, size: 22),
                ),
                AppSpacing.gapSm,
                Text(flow.title, style: context.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text(Formatters.plural(flow.questions.length, 'question'), style: context.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestionInput extends StatelessWidget {
  const _QuestionInput({required this.question, required this.value, required this.onChanged});

  final FinderQuestion question;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  bool _same(Object? a, Object? b) => a.toString() == b.toString();

  @override
  Widget build(BuildContext context) {
    final q = question;
    if (q.type == FinderQuestionType.budget && q.options.isEmpty) {
      return _BudgetSlider(value: value, onChanged: onChanged);
    }
    if (q.type == FinderQuestionType.multi) {
      final selected = value is List ? List<Object?>.from(value! as List) : <Object?>[];
      return Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          for (final o in q.options)
            FilterChip(
              label: Text(o.label),
              selected: selected.any((s) => _same(s, o.value)),
              onSelected: (on) {
                final next = [...selected]..removeWhere((s) => _same(s, o.value));
                if (on) next.add(o.value);
                onChanged(next.isEmpty ? null : next);
              },
            ),
        ],
      );
    }
    return Column(
      children: [
        for (final o in q.options)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _OptionTile(
              label: o.label,
              selected: _same(value, o.value),
              onTap: () => onChanged(_same(value, o.value) ? null : o.value),
            ),
          ),
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? colors.primarySoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: selected ? colors.primary : colors.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: AppRadii.cardAll,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: context.textTheme.bodyLarge)),
                  AnimatedSwitcher(
                    duration: context.motion(AppDurations.fast),
                    child: Icon(
                      selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                      key: ValueKey(selected),
                      color: selected ? colors.primary : colors.muted,
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

class _BudgetSlider extends StatelessWidget {
  const _BudgetSlider({required this.value, required this.onChanged});

  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) {
    final max = value is Map ? (value! as Map)['max'] as num? : null;
    final v = (max ?? 50000).toDouble().clamp(1000.0, 500000.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Up to ${Formatters.price(v)}', style: context.textTheme.titleLarge),
        Slider(
          value: v,
          min: 1000,
          max: 500000,
          divisions: 499,
          label: Formatters.priceCompact(v),
          onChanged: (x) => onChanged({'min': 0, 'max': (x / 1000).round() * 1000}),
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.result, required this.onRestart, required this.onAdjust});

  final AiProductsResult result;
  final VoidCallback onRestart;
  final VoidCallback onAdjust;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverResponsiveCenter(
          verticalPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          sliver: SliverToBoxAdapter(
            child: AiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AiHeader(title: 'Your matches', caption: Formatters.plural(result.products.length, 'product')),
                  if (result.summary.isNotEmpty) ...[
                    AppSpacing.gapXs,
                    SimpleMarkdown(result.summary),
                  ],
                  AppSpacing.gapSm,
                  Wrap(
                    spacing: AppSpacing.xs,
                    children: [
                      AppButton.secondary(label: 'Adjust answers', size: AppButtonSize.small, onPressed: onAdjust),
                      AppButton.ghost(label: 'Start over', size: AppButtonSize.small, onPressed: onRestart),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (result.products.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'No exact matches',
              message: 'Try relaxing an answer, like the budget.',
              actionLabel: 'Adjust answers',
              onAction: onAdjust,
            ),
          )
        else
          SliverResponsiveCenter(
            verticalPadding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            sliver: SliverAiProductGrid(products: result.products, source: 'finder'),
          ),
      ],
    );
  }
}
