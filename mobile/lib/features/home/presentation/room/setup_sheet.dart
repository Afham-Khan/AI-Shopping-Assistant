import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/data/ai_repository.dart';
import '../../../ai/data/models/ai_models.dart';

/// "Build my setup": pick a goal and a budget, Zel picks the pieces
/// (`POST /ai/bundle`). Pops with the [BundleResult].
Future<BundleResult?> showSetupSheet(BuildContext context) => showAppBottomSheet<BundleResult>(
  context,
  builder: (_) => const _SetupSheet(),
);

class _SetupSheet extends ConsumerStatefulWidget {
  const _SetupSheet();

  static const goals = [
    'Gaming setup',
    'Home office',
    'Skincare routine',
    'Gym starter kit',
    'Kitchen basics',
    'Date night outfit',
    'Road trip ready',
  ];

  @override
  ConsumerState<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends ConsumerState<_SetupSheet> {
  final _custom = TextEditingController();
  String _goal = _SetupSheet.goals.first;
  double _budget = 150000;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  String get _effectiveGoal => _custom.text.trim().length >= 2 ? _custom.text.trim() : _goal;

  Future<void> _build() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref.read(aiRepositoryProvider).bundle(goal: _effectiveGoal, budget: _budget);
      if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return BottomSheetScaffold(
      title: 'Build my setup',
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
            'Pick a goal and a budget. Zel chooses the pieces and places them in the room.',
            style: t.bodyMedium!.copyWith(color: colors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Goal', style: t.titleSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final g in _SetupSheet.goals)
                ChoiceChip(
                  label: Text(g),
                  selected: _custom.text.trim().length < 2 && g == _goal,
                  onSelected: (_) => setState(() {
                    _goal = g;
                    _custom.clear();
                  }),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _custom,
            onChanged: (_) => setState(() {}),
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
                Formatters.price(_budget),
                style: t.titleSmall!.copyWith(color: colors.primary, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          Slider(
            value: _budget,
            min: 20000,
            max: 500000,
            divisions: 48,
            label: Formatters.priceCompact(_budget),
            onChanged: _busy ? null : (v) => setState(() => _budget = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(_error!, style: t.bodySmall!.copyWith(color: colors.sale)),
          ],
        ],
      ),
    );
  }
}
