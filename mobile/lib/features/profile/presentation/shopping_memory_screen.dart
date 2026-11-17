import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/memory_models.dart';
import '../providers/memory_providers.dart';

/// "What Zelora remembers": the consent switch, what Zel has learned in plain
/// words, and a way to forget everything.
class ShoppingMemoryScreen extends ConsumerWidget {
  const ShoppingMemoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(shoppingMemoryProvider);

    Future<void> reload() async {
      ref.invalidate(shoppingMemoryProvider);
      try {
        await ref.read(shoppingMemoryProvider.future);
      } catch (_) {}
    }

    return Scaffold(
      appBar: AppBar(title: const Text('What Zelora remembers')),
      body: RefreshIndicator(
        onRefresh: reload,
        child: switch (async) {
          AsyncValue(:final value?) => _Content(memory: value),
          AsyncValue(:final error?) => LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(height: c.maxHeight, child: ErrorState(error: error, onRetry: reload)),
            ),
          ),
          _ => const ResponsiveCenter(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: AppSpacing.md),
                Skeleton(height: 92, borderRadius: AppRadii.cardAll),
                SizedBox(height: AppSpacing.sm),
                Skeleton(height: 72, borderRadius: AppRadii.cardAll),
                SizedBox(height: AppSpacing.sm),
                Skeleton(height: 160, borderRadius: AppRadii.cardAll),
              ],
            ),
          ),
        },
      ),
    );
  }
}

class _Content extends ConsumerStatefulWidget {
  const _Content({required this.memory});

  final ShoppingMemory memory;

  @override
  ConsumerState<_Content> createState() => _ContentState();
}

class _ContentState extends ConsumerState<_Content> {
  bool _toggling = false;

  Future<void> _toggle(bool value) async {
    setState(() => _toggling = true);
    try {
      final message = await ref.read(shoppingMemoryProvider.notifier).setEnabled(value);
      if (mounted) AppSnack.info(context, message ?? (value ? 'Shopping memory is on' : 'Shopping memory is off'));
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  Future<void> _forget() async {
    String? message;
    final done = await ConfirmDialog.show(
      context,
      title: 'Forget everything?',
      message:
          'Zel will delete what it learned from your browsing, searches and chats. '
          'Your orders and wishlist stay. This action cannot be undone.',
      confirmLabel: 'Forget everything',
      icon: Icons.delete_sweep_outlined,
      onConfirm: () async => message = await ref.read(shoppingMemoryProvider.notifier).forgetAll(),
    );
    if (done && mounted) AppSnack.success(context, message ?? 'Shopping memory cleared');
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.memory;
    final colors = context.colors;
    final t = context.textTheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.sm, context.pagePadding, AppSpacing.xxl),
      children: [
        ResponsiveCenter(
          maxWidth: 640,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppCard(
                color: colors.primarySoft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 2), child: AiSparkleIcon(size: 20)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Zel uses what you browse, search and chat about to tune its picks to you. '
                        'You decide whether it remembers, and you can wipe it any time.',
                        style: t.bodyMedium!.copyWith(height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Remember my shopping', style: t.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            m.enabled
                                ? 'On. Zel keeps learning from what you do.'
                                : "Paused. Zel isn't saving or using your browsing.",
                            style: t.bodySmall!.copyWith(color: colors.muted, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                    Semantics(
                      label: 'Remember my shopping',
                      toggled: m.enabled,
                      child: Switch(value: m.enabled, onChanged: _toggling ? null : _toggle),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(header: true, child: Text('What Zel remembers', style: t.titleMedium)),
              const SizedBox(height: AppSpacing.xs),
              if (m.hasNothing)
                AppCard(
                  child: EmptyState(
                    compact: true,
                    icon: Icons.psychology_alt_outlined,
                    title: m.enabled ? 'Nothing remembered yet' : 'Nothing saved',
                    message: m.enabled
                        ? 'Browse, search or chat and Zel starts learning your taste.'
                        : 'Memory is paused, so Zel is not learning from your activity.',
                  ),
                )
              else
                _Learned(memory: m),
              const SizedBox(height: AppSpacing.xl),
              AppButton.secondary(
                label: 'Forget everything',
                icon: Icons.delete_sweep_outlined,
                expand: true,
                onPressed: m.hasNothing ? null : _forget,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Deletes what Zel learned. Your orders, addresses and wishlist are not touched.',
                textAlign: TextAlign.center,
                style: t.bodySmall!.copyWith(color: colors.faint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Learned extends StatelessWidget {
  const _Learned({required this.memory});

  final ShoppingMemory memory;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final m = memory;
    // the on/off state is already shown by the switch above
    final lines = [for (final l in m.summary) if (!l.toLowerCase().contains('memory is off')) l];

    Widget group(String title, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.labelMedium!.copyWith(color: colors.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: chips),
        ],
      ),
    );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle_outline_rounded, size: 16, color: colors.primary),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(line, style: t.bodyMedium!.copyWith(height: 1.45))),
                ],
              ),
            ),
          if (m.topCategories.isNotEmpty)
            group('Categories', [for (final c in m.topCategories) _FactChip(label: c.name, share: c.share)]),
          if (m.topBrands.isNotEmpty) group('Brands', [for (final b in m.topBrands) _FactChip(label: b.name, share: b.share)]),
          if (m.budgetLabel != null)
            group('Usual price range', [_FactChip(label: m.budgetLabel!, icon: Icons.sell_outlined)]),
          if (m.recentSearches.isNotEmpty)
            group('Recent searches', [for (final s in m.recentSearches) _FactChip(label: s, icon: Icons.search_rounded)]),
          if (m.interactions + m.searches + m.chats > 0) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              [
                if (m.interactions > 0) Formatters.plural(m.interactions, 'activity', 'activities'),
                if (m.searches > 0) Formatters.plural(m.searches, 'search', 'searches'),
                if (m.chats > 0) Formatters.plural(m.chats, 'chat'),
                if (m.lastActivityAt != null) 'last active ${Formatters.date(m.lastActivityAt)}',
              ].join(' · '),
              style: t.bodySmall!.copyWith(color: colors.faint),
            ),
          ],
        ],
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({required this.label, this.share, this.icon});

  final String label;
  final double? share;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final pct = share == null ? null : (share! * 100).round();
    return Semantics(
      label: pct == null ? label : '$label, $pct percent of your activity',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          borderRadius: AppRadii.pillAll,
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: colors.muted), const SizedBox(width: 4)],
            Flexible(
              child: Text(label, style: t.labelMedium!.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (pct != null && pct > 0) ...[
              const SizedBox(width: 6),
              Text('$pct%', style: t.labelSmall!.copyWith(color: colors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}
