import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/data/ai_repository.dart';
import '../../../ai/data/models/ai_models.dart';
import '../../../ai/presentation/widgets/budget_advice_notice.dart';
import '../../../ai/providers/ai_providers.dart';
import '../../providers/room_providers.dart';

/// "Furnish a room with AI" (opened by "Build my setup"): pick a goal and a
/// budget, Zel picks the best combination that fits (`POST /ai/bundle`).
/// Pops with the [BundleResult].
///
/// Each goal starts at the server's suggested budget. When the budget can't
/// cover a goal's essentials the sheet says so, with a one-tap retry at the
/// suggested budget, instead of furnishing a half-empty room silently.
Future<BundleResult?> showSetupSheet(BuildContext context) => showAppBottomSheet<BundleResult>(
  context,
  builder: (_) => const _SetupSheet(),
);

class _SetupSheet extends ConsumerStatefulWidget {
  const _SetupSheet();

  static const minBudget = 5000.0;
  static const step = 5000.0;
  static const baseMax = 500000.0;

  @override
  ConsumerState<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<_SetupSheet> {
  final _custom = TextEditingController();
  SetupGoal _goal = kSetupGoals.first;

  /// A budget the shopper chose (slider or "Use Rs X"); null follows the goal's suggestion.
  double? _picked;
  bool _busy = false;
  String? _error;

  /// A built set that left the essentials out, kept so it can still be used.
  BundleResult? _short;
  final _noticeKey = GlobalKey();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  bool get _isCustom => _custom.text.trim().length >= 2;
  String get _effectiveGoal => _isCustom ? _custom.text.trim() : _goal.label;

  /// The goal's suggested budget once the server has answered, else the old default.
  double get _budget =>
      _picked ??
      (_isCustom ? null : ref.read(bundleTemplatesProvider).value?.suggestedFor(_goal.templateId)) ??
      kSetupFallbackBudget;

  double _maxFor(double budget) => math.max(_SetupSheet.baseMax, (budget / 100000).ceil() * 100000.0);

  void _chooseGoal(SetupGoal g) => setState(() {
    _goal = g;
    _custom.clear();
    _picked = null; // back to the new goal's own suggestion
    _short = null;
    _error = null;
  });

  Future<void> _build({double? budget}) async {
    setState(() {
      if (budget != null) _picked = budget;
      _busy = true;
      _error = null;
      _short = null;
    });
    final used = _budget;
    try {
      final result = await ref.read(aiRepositoryProvider).bundle(goal: _effectiveGoal, budget: used);
      if (!mounted) return;
      if (result.budgetAdvice.missesEssentials) {
        setState(() {
          _busy = false;
          _short = result;
        });
        _showNotice();
        return;
      }
      if (result.items.isEmpty) {
        setState(() {
          _busy = false;
          _error = 'Nothing fits that budget yet. Try a little more room.';
        });
        return;
      }
      Navigator.of(context).pop(result);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  /// The notice sits below the fold on small phones: bring it into view.
  void _showNotice() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _noticeKey.currentContext;
      if (ctx != null && mounted) {
        Scrollable.ensureVisible(ctx, duration: context.motion(AppDurations.normal), curve: AppCurves.standard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    // watched so the budget follows the server's suggestion once it loads
    ref.watch(bundleTemplatesProvider);
    final budget = _budget;
    final max = _maxFor(budget);
    final short = _short;
    return BottomSheetScaffold(
      title: 'Furnish a room with AI',
      footer: AppButton(
        label: 'Furnish the room',
        icon: Icons.chair_outlined,
        expand: true,
        loading: _busy,
        onPressed: _build,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pick a goal and a budget. Zel picks the best combination that fits (budget optimisation) '
            'and places each piece where it belongs.',
            style: t.bodyMedium!.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Goal', style: t.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final g in kSetupGoals)
                ChoiceChip(
                  label: Text(g.label),
                  selected: !_isCustom && g.templateId == _goal.templateId,
                  onSelected: (_) => _chooseGoal(g),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _custom,
            onChanged: (_) => setState(() {
              _picked ??= budget; // a typed goal keeps the budget on screen
              _short = null;
            }),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _build(),
            decoration: const InputDecoration(
              hintText: 'Or describe it: "a cosy reading corner"',
              prefixIcon: Icon(Icons.edit_outlined, size: 20),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(child: Text('Budget', style: t.titleSmall)),
              Text(
                Formatters.price(budget),
                style: t.titleSmall!.copyWith(color: colors.primary, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          Slider(
            value: budget.clamp(_SetupSheet.minBudget, max),
            min: _SetupSheet.minBudget,
            max: max,
            divisions: ((max - _SetupSheet.minBudget) / _SetupSheet.step).round(),
            label: Formatters.priceCompact(budget),
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _picked = v;
                    _short = null;
                  }),
          ),
          if (short != null) ...[
            const SizedBox(height: AppSpacing.xs),
            BudgetAdviceNotice(
              key: _noticeKey,
              advice: short.budgetAdvice,
              budget: short.budget,
              busy: _busy,
              onUseSuggested: (v) => _build(budget: v),
              secondary: short.items.isEmpty
                  ? null
                  : AppButton.ghost(
                      label: 'Keep ${Formatters.plural(short.items.length, 'piece')} that fit',
                      expand: true,
                      onPressed: () => Navigator.of(context).pop(short),
                    ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(_error!, style: t.bodySmall!.copyWith(color: colors.sale)),
          ],
        ],
      ),
    );
  }
}
