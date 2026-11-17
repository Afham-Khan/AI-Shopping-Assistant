import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/category_icons.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/search_repository.dart';

/// Search with live suggestions, recent history, trending chips and a
/// "Smart AI search" mode that understands natural language.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _controller = TextEditingController(text: widget.initialQuery ?? '');
  final _debouncer = Debouncer(duration: const Duration(milliseconds: 250));
  late String _q = (widget.initialQuery ?? '').trim();
  bool _smart = false;

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {}); // clear button
    _debouncer.run(() {
      if (mounted) setState(() => _q = value.trim());
    });
  }

  void _submit([String? value]) {
    final q = (value ?? _controller.text).trim();
    if (q.isEmpty) return;
    _debouncer.cancel();
    if (ref.read(isAuthenticatedProvider)) {
      // fire and forget; history is a convenience
      unawaited(
        ref.read(searchRepositoryProvider).saveHistory(q).then((_) {
          if (mounted) ref.invalidate(searchHistoryProvider);
        }, onError: (_) {}),
      );
    }
    if (_smart) {
      context.push(Routes.smartSearchOf(q));
    } else {
      context.push(Routes.productList(q: q));
    }
  }

  void _fill(String q) {
    _controller.value = TextEditingValue(text: q, selection: TextSelection.collapsed(offset: q.length));
    _submit(q);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: _submit,
            style: context.textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: _smart ? 'Describe what you want…' : 'Search products, brands…',
              prefixIcon: _smart
                  ? const Padding(padding: EdgeInsets.all(12), child: AiSparkleIcon(size: 20))
                  : const Icon(Icons.search_rounded, size: 20),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () {
                        _controller.clear();
                        _debouncer.cancel();
                        setState(() => _q = '');
                      },
                    ),
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        maxWidth: 760,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(top: AppSpacing.xs, bottom: AppSpacing.xxl),
          children: [
            _SmartToggle(
              enabled: _smart,
              onChanged: (v) => setState(() => _smart = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_q.isEmpty) ...[
              const _History(),
              _Trending(onTap: _fill),
            ] else ...[
              if (!_smart)
                _SuggestionTile(
                  leading: const AiSparkleIcon(size: 20),
                  title: 'Smart AI search for "$_q"',
                  subtitle: 'Understands budgets, colours and use cases',
                  onTap: () => context.push(Routes.smartSearchOf(_q)),
                  tint: colors.aiSoft,
                ),
              _Suggestions(query: _q, onQuery: _fill),
            ],
          ],
        ),
      ),
    );
  }
}

class _SmartToggle extends StatelessWidget {
  const _SmartToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final content = Row(
      children: [
        const AiSparkleIcon(size: 22),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Smart AI search', style: t.titleSmall),
              Text(
                'Try "red running shoes for women under 15k"',
                style: t.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        Switch(value: enabled, onChanged: onChanged),
      ],
    );
    return Semantics(
      toggled: enabled,
      child: InkWell(
        borderRadius: AppRadii.cardAll,
        onTap: () => onChanged(!enabled),
        child: AnimatedContainer(
          duration: context.motion(AppDurations.normal),
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
          decoration: BoxDecoration(
            color: enabled ? colors.aiSoft : colors.surface,
            borderRadius: AppRadii.cardAll,
            border: Border.all(color: enabled ? colors.ai.withValues(alpha: 0.4) : colors.border),
          ),
          child: content,
        ),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History();

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(searchRepositoryProvider).clearHistory();
      ref.invalidate(searchHistoryProvider);
    } catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(searchHistoryProvider).value ?? const [];
    if (history.isEmpty) return const SizedBox.shrink();
    final state = context.findAncestorStateOfType<_SearchScreenState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Recent searches', style: context.textTheme.titleMedium)),
              TextButton(
                onPressed: () => _clear(context, ref),
                style: TextButton.styleFrom(foregroundColor: context.colors.secondary),
                child: const Text('Clear'),
              ),
            ],
          ),
          for (final q in history)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.north_west_rounded, size: 18),
              onTap: () => state?._fill(q),
            ),
        ],
      ),
    );
  }
}

class _Trending extends ConsumerWidget {
  const _Trending({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trending = ref.watch(trendingSearchesProvider);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.trending_up_rounded, color: colors.primary, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Text('Trending searches', style: context.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        switch (trending) {
          AsyncValue(:final value?) => Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final q in value)
                ActionChip(
                  avatar: Icon(Icons.north_east_rounded, size: 14, color: colors.primary),
                  label: Text(q),
                  onPressed: () => onTap(q),
                ),
            ],
          ),
          AsyncValue(:final error?) => ErrorState(
            error: error,
            compact: true,
            onRetry: () => ref.invalidate(trendingSearchesProvider),
          ),
          _ => const Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Skeleton(width: 90, height: 36),
              Skeleton(width: 70, height: 36),
              Skeleton(width: 110, height: 36),
              Skeleton(width: 80, height: 36),
            ],
          ),
        },
      ],
    );
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.query, required this.onQuery});

  final String query;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(searchSuggestionsProvider(query));
    final t = context.textTheme;
    final s = async.value;
    if (s == null) {
      if (async.hasError) {
        return ErrorState(error: async.error, compact: true, onRetry: () => ref.invalidate(searchSuggestionsProvider(query)));
      }
      return const SkeletonList(count: 4);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SuggestionTile(
          leading: const Icon(Icons.search_rounded),
          title: 'Search for "$query"',
          onTap: () => onQuery(query),
        ),
        for (final q in s.queries)
          if (q.toLowerCase() != query.toLowerCase())
            _SuggestionTile(leading: const Icon(Icons.search_rounded), title: q, onTap: () => onQuery(q)),
        for (final c in s.categories)
          _SuggestionTile(
            leading: Icon(CategoryIcons.of(c.slug)),
            title: c.name,
            subtitle: 'Category',
            onTap: () => context.push(Routes.productList(category: c.slug, title: c.name)),
          ),
        if (s.products.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xs),
            child: Text('Products', style: t.titleSmall),
          ),
          for (final p in s.products)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: AppNetworkImage(p.thumbnail, width: 48, height: 48, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
              title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(Formatters.price(p.price), style: t.labelLarge!.copyWith(color: context.colors.primary)),
              onTap: () => context.push(Routes.product(p.id)),
            ),
        ],
        if (s.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Text('No quick matches — press search to see all results.', style: t.bodySmall),
          ),
      ],
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({required this.leading, required this.title, required this.onTap, this.subtitle, this.tint});

  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: ListTile(
        tileColor: tint,
        contentPadding: EdgeInsets.symmetric(horizontal: tint == null ? 0 : AppSpacing.md),
        leading: leading,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: const Icon(Icons.north_west_rounded, size: 18),
        onTap: onTap,
      ),
    );
  }
}
