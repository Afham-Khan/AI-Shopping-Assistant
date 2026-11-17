import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/ai_repository.dart';
import '../data/models/ai_models.dart';
import 'widgets/ai_ui.dart';
import 'widgets/bundle_view.dart';

class _Preset {
  const _Preset(this.title, this.goal, this.icon, this.budget);

  final String title;
  final String goal;
  final IconData icon;
  final double budget;
}

/// Bundle Builder (POST /ai/bundle): pick a goal and budget, the AI assembles
/// a complete set by role, with swaps, budget tracking and "Add all".
class BundleBuilderScreen extends ConsumerStatefulWidget {
  const BundleBuilderScreen({super.key});

  static const minBudget = 5000.0;
  static const maxBudget = 500000.0;

  @override
  ConsumerState<BundleBuilderScreen> createState() => _BundleBuilderScreenState();
}

class _BundleBuilderScreenState extends ConsumerState<BundleBuilderScreen> {
  static const _presets = [
    _Preset('Home office', 'home office setup', Icons.desk_outlined, 150000),
    _Preset('Gaming setup', 'gaming setup', Icons.sports_esports_outlined, 300000),
    _Preset('University starter', 'university starter kit', Icons.school_outlined, 120000),
    _Preset('Gym starter', 'gym starter kit', Icons.fitness_center_rounded, 25000),
    _Preset('Skincare routine', 'skincare routine', Icons.spa_outlined, 15000),
    _Preset('Eid gift set', 'eid gift set', Icons.card_giftcard_rounded, 20000),
  ];

  final _goal = TextEditingController();
  final _budgetField = TextEditingController();
  final _resultKey = GlobalKey();
  int? _preset;
  double _budget = 50000;

  bool _loading = false;
  BundleResult? _bundle;
  ApiException? _error;
  int _buildSeq = 0;

  @override
  void initState() {
    super.initState();
    _budgetField.text = _budget.round().toString();
  }

  @override
  void dispose() {
    _goal.dispose();
    _budgetField.dispose();
    super.dispose();
  }

  void _selectPreset(int i) {
    final p = _presets[i];
    setState(() {
      _preset = i;
      _goal.text = p.goal;
      _setBudget(p.budget);
    });
  }

  void _setBudget(double v) {
    _budget = v.clamp(BundleBuilderScreen.minBudget, BundleBuilderScreen.maxBudget);
    _budgetField.text = _budget.round().toString();
  }

  String get _goalText => _goal.text.trim();

  Future<void> _build() async {
    if (_goalText.isEmpty) {
      AppSnack.info(context, 'Pick a preset or describe your goal first.');
      return;
    }
    context.unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _buildSeq++;
    });
    _scrollToResult();
    try {
      final b = await ref.read(aiRepositoryProvider).bundle(goal: _goalText, budget: _budget);
      if (mounted) setState(() => _bundle = b);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _resultKey.currentContext;
      if (ctx != null && !context.isDesktop) {
        Scrollable.ensureVisible(ctx, duration: context.motion(AppDurations.slow), curve: AppCurves.standard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bundle Builder')),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 960;
          final form = _form(context);
          final result = KeyedSubtree(key: _resultKey, child: _result(context));
          if (wide) {
            return ResponsiveCenter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 420,
                    child: ListView(padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg), children: [form]),
                  ),
                  AppSpacing.gapXl,
                  Expanded(
                    child: ListView(padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg), children: [result]),
                  ),
                ],
              ),
            );
          }
          return ResponsiveCenter(
            maxWidth: 720,
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: [form, AppSpacing.gapXl, result],
            ),
          );
        },
      ),
    );
  }

  Widget _form(BuildContext context) {
    final t = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AiHeader(title: 'Build a complete set', caption: 'Choose a goal and a budget. The AI picks one item per role and keeps you on budget.'),
        AppSpacing.gapLg,
        Text('Goal', style: t.labelLarge),
        AppSpacing.gapXs,
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 520 ? 3 : 2;
            final w = (c.maxWidth - AppSpacing.xs * (cols - 1)) / cols;
            return Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (var i = 0; i < _presets.length; i++)
                  SizedBox(
                    width: w,
                    child: _PresetCard(preset: _presets[i], selected: _preset == i, onTap: () => _selectPreset(i)),
                  ),
              ],
            );
          },
        ),
        AppSpacing.gapMd,
        AppTextField(
          label: 'Or describe your own goal',
          controller: _goal,
          prefixIcon: Icons.edit_outlined,
          onChanged: (_) {
            if (_preset != null && _goalText != _presets[_preset!].goal) setState(() => _preset = null);
          },
          onSubmitted: (_) => _build(),
        ),
        AppSpacing.gapLg,
        Row(
          children: [
            Expanded(child: Text('Budget', style: t.labelLarge)),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _budgetField,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.end,
                decoration: const InputDecoration(prefixText: 'Rs ', isDense: true),
                onSubmitted: (v) => setState(() => _setBudget(double.tryParse(v) ?? _budget)),
                onTapOutside: (_) => setState(() => _setBudget(double.tryParse(_budgetField.text) ?? _budget)),
              ),
            ),
          ],
        ),
        Slider(
          value: _budget,
          min: BundleBuilderScreen.minBudget,
          max: BundleBuilderScreen.maxBudget,
          divisions: ((BundleBuilderScreen.maxBudget - BundleBuilderScreen.minBudget) / 1000).round(),
          label: Formatters.priceCompact(_budget),
          semanticFormatterCallback: Formatters.price,
          onChanged: (v) => setState(() => _setBudget((v / 1000).round() * 1000)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Formatters.priceCompact(BundleBuilderScreen.minBudget), style: t.bodySmall),
            Text(Formatters.priceCompact(BundleBuilderScreen.maxBudget), style: t.bodySmall),
          ],
        ),
        AppSpacing.gapLg,
        AppButton(
          label: _bundle == null ? 'Build my bundle' : 'Rebuild bundle',
          icon: Icons.auto_awesome,
          expand: true,
          size: AppButtonSize.large,
          loading: _loading,
          onPressed: _build,
        ),
      ],
    );
  }

  Widget _result(BuildContext context) {
    if (_loading) {
      return const AiCard(
        child: AiThinking(
          messages: ['Understanding your goal…', 'Choosing an item for each role…', 'Balancing the budget…'],
          lines: 6,
        ),
      );
    }
    if (_error != null) {
      return AiCard(child: ErrorState(error: _error, compact: true, onRetry: _build));
    }
    final b = _bundle;
    if (b == null) {
      return const AiCard(
        child: EmptyState(
          compact: true,
          iconWidget: AiMark(size: 28),
          title: 'Your bundle appears here',
          message: 'Each item comes with alternatives you can swap in one tap.',
        ),
      );
    }
    if (b.items.isEmpty) {
      return AiCard(
        child: EmptyState(
          compact: true,
          icon: Icons.inventory_2_outlined,
          title: "Couldn't fit a full set",
          message: b.explanation.isNotEmpty ? b.explanation : 'Try a higher budget or a different goal.',
        ),
      );
    }
    return AiCard(child: BundleView(key: ValueKey(_buildSeq), bundle: b));
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({required this.preset, required this.selected, required this.onTap});

  final _Preset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.title}, suggested budget ${Formatters.price(preset.budget)}',
      excludeSemantics: true,
      child: Material(
        color: selected ? colors.primarySoft : colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: selected ? colors.primary : colors.border, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: AppRadii.cardAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(preset.icon, color: selected ? colors.primary : colors.muted),
                AppSpacing.gapXs,
                Text(preset.title, style: context.textTheme.labelLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('~${Formatters.priceCompact(preset.budget)}', style: context.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
