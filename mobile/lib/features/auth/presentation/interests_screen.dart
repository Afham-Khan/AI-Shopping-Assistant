import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/network/api_client.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/auth_controller.dart';

/// Lightweight department → categories shape for the picker only
/// (the catalog feature owns the full models).
class _Department {
  const _Department(this.name, this.slug, this.icon, this.categories);

  factory _Department.fromJson(Map<String, dynamic> json) => _Department(
    JsonX.asString(json['name']),
    JsonX.asString(json['slug']),
    JsonX.asStringOrNull(json['icon']),
    JsonX.asList(json['categories'], (c) => (JsonX.asString(c['name']), JsonX.asString(c['slug']))),
  );

  final String name;
  final String slug;
  final String? icon;
  final List<(String name, String slug)> categories;
}

final _departmentsProvider = FutureProvider.autoDispose<List<_Department>>((ref) {
  return ref.read(apiClientProvider).get(
    '/catalog/departments',
    decode: (d) => JsonX.asList(d, _Department.fromJson),
  );
});

/// After sign-up: pick interests, budget and gender preference
/// (PUT /users/me/preferences). Skippable.
class InterestsScreen extends ConsumerStatefulWidget {
  const InterestsScreen({super.key, this.from});

  final String? from;

  @override
  ConsumerState<InterestsScreen> createState() => _InterestsScreenState();
}

class _InterestsScreenState extends ConsumerState<InterestsScreen> {
  static const _budgetCap = 500000.0;

  late final Set<String> _selected;
  late RangeValues _budget;
  late String _gender;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(currentUserProvider)?.preferences;
    _selected = {...?prefs?.interests};
    _budget = RangeValues(
      (prefs?.budgetMin ?? 0).clamp(0, _budgetCap).toDouble(),
      (prefs?.budgetMax ?? 150000).clamp(0, _budgetCap).toDouble(),
    );
    _gender = prefs?.gender ?? 'any';
  }

  void _done() => context.go(Routes.returnTo(widget.from));

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(authControllerProvider.notifier).savePreferences(
        interests: _selected.toList(),
        budgetMin: _budget.start,
        budgetMax: _budget.end,
        gender: _gender,
      );
      if (mounted) _done();
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final departments = ref.watch(_departmentsProvider);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const AppLogo(size: 26),
        actions: [
          TextButton(
            onPressed: _saving ? null : _done,
            style: TextButton.styleFrom(foregroundColor: colors.muted),
            child: const Text('Skip'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverResponsiveCenter(
            maxWidth: 760,
            verticalPadding: const EdgeInsets.only(top: AppSpacing.md),
            sliver: SliverList.list(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Eyebrow('Teach Zel your taste', leading: AiSparkleIcon(size: 11)),
                ),
                AppSpacing.gapSm,
                Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'What are you '),
                        TextSpan(text: 'into?', style: TextStyle(color: colors.primary)),
                      ],
                    ),
                    style: t.displaySmall,
                  ),
                ),
                AppSpacing.gapXs,
                Text(
                  'Pick a few. Zel uses them to rank what you see first, and you can change them any time.',
                  style: t.bodyLarge!.copyWith(color: colors.muted, fontSize: 15),
                ),
                AppSpacing.gapXl,
              ],
            ),
          ),
          SliverResponsiveCenter(
            maxWidth: 760,
            sliver: departments.when(
              data: (list) => SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _DepartmentChips(
                  department: list[i],
                  selected: _selected,
                  onToggle: (slug) => setState(() => _selected.contains(slug) ? _selected.remove(slug) : _selected.add(slug)),
                ),
              ),
              loading: () => const SliverToBoxAdapter(child: _ChipsSkeleton()),
              error: (e, _) => SliverToBoxAdapter(
                child: ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(_departmentsProvider)),
              ),
            ),
          ),
          SliverResponsiveCenter(
            maxWidth: 760,
            verticalPadding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xxl),
            sliver: SliverList.list(
              children: [
                const Divider(),
                AppSpacing.gapXl,
                const Align(alignment: Alignment.centerLeft, child: Eyebrow('Typical budget', color: null)),
                AppSpacing.gapXs,
                Text(
                  '${Formatters.price(_budget.start)} – ${Formatters.price(_budget.end)}${_budget.end >= _budgetCap ? '+' : ''}',
                  style: t.titleLarge!.copyWith(fontSize: 22, letterSpacing: -0.5, fontFeatures: AppType.tabular),
                ),
                AppSpacing.gapXxs,
                RangeSlider(
                  values: _budget,
                  max: _budgetCap,
                  divisions: 100,
                  labels: RangeLabels(Formatters.priceCompact(_budget.start), Formatters.priceCompact(_budget.end)),
                  onChanged: _saving ? null : (v) => setState(() => _budget = v),
                ),
                AppSpacing.gapLg,
                const Align(alignment: Alignment.centerLeft, child: Eyebrow('Show me products for')),
                AppSpacing.gapSm,
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'men', label: Text('Men')),
                    ButtonSegment(value: 'women', label: Text('Women')),
                    ButtonSegment(value: 'any', label: Text('Everyone')),
                  ],
                  selected: {_gender},
                  onSelectionChanged: _saving ? null : (s) => setState(() => _gender = s.first),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        count: _selected.length,
        saving: _saving,
        onContinue: _selected.isEmpty ? null : _save,
      ),
    );
  }
}

class _DepartmentChips extends StatelessWidget {
  const _DepartmentChips({required this.department, required this.selected, required this.onToggle});

  final _Department department;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (department.categories.isEmpty) return const SizedBox.shrink();
    final picked = department.categories.where((c) => selected.contains(c.$2)).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: colors.departmentAccent(department.slug), shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                department.name.toUpperCase(),
                style: AppType.eyebrow(context, color: colors.muted).copyWith(letterSpacing: 1.1),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (picked > 0)
                Text('$picked picked', style: AppType.data(context, color: colors.primary, size: 11)),
            ],
          ),
          AppSpacing.gapSm,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (name, slug) in department.categories)
                FilterChip(
                  selected: selected.contains(slug),
                  onSelected: (_) => onToggle(slug),
                  avatar: Icon(
                    CategoryIcons.of(slug),
                    size: 18,
                    color: selected.contains(slug) ? colors.primary : colors.muted,
                  ),
                  label: Text(name),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChipsSkeleton extends StatelessWidget {
  const _ChipsSkeleton();

  @override
  Widget build(BuildContext context) {
    const widths = [96.0, 120.0, 84.0, 140.0, 104.0, 90.0, 128.0, 76.0, 112.0];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var section = 0; section < 2; section++) ...[
          const Skeleton(width: 110, height: 14),
          AppSpacing.gapSm,
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [for (final w in widths) Skeleton(width: w, height: 40)],
          ),
          AppSpacing.gapXl,
        ],
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.count, required this.saving, required this.onContinue});

  final int count;
  final bool saving;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: context.pagePadding, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      count == 0 ? 'Pick at least one to continue' : '${Formatters.plural(count, 'interest')} selected',
                      style: AppType.data(context, color: count == 0 ? colors.faint : colors.muted),
                    ),
                  ),
                  AppButton(label: 'Continue', onPressed: onContinue, loading: saving),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
