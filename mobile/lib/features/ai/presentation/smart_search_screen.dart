import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/models/ai_models.dart';
import '../providers/ai_providers.dart';
import 'widgets/ai_product_widgets.dart';
import 'widgets/ai_ui.dart';
import 'widgets/entity_chips.dart';

final _pricePhrase = RegExp(
  r'\b(?:under|below|less than|upto|up to|within|max|over|above|more than|between|from)?\s*(?:rs\.?|pkr)?\s*\d[\d,.]*\s*k?\b(?:\s*(?:-|to|and)\s*(?:rs\.?|pkr)?\s*\d[\d,.]*\s*k?)?(?:\s*(?:tak|se kam|ke andar))?',
  caseSensitive: false,
);

/// Removes a constraint from a natural-language query so it can be re-run
/// without it. Budget chips strip price phrases ("under 15k", "30k tak");
/// other chips strip their label/value words.
String removeFromQuery(String query, {required String type, required String label, String? value}) {
  var q = query;
  if (type == 'budget' || type == 'price') {
    q = q.replaceAll(_pricePhrase, ' ');
  } else {
    final candidates = <String>{
      ?value,
      label,
      label.replaceAll('"', ''),
      label.replaceFirst(RegExp(r'^no\s+', caseSensitive: false), ''),
    }.where((c) => c.trim().isNotEmpty);
    for (final c in candidates) {
      final pattern = RegExp(r'\b' + RegExp.escape(c.trim()) + r's?\b', caseSensitive: false);
      if (pattern.hasMatch(q)) {
        q = q.replaceAll(pattern, ' ');
        break;
      }
      // multi-word labels: drop each word ("Running Shoes")
      final words = c.trim().split(RegExp(r'\s+'));
      if (words.length > 1 && words.every((w) => RegExp(r'\b' + RegExp.escape(w) + r'\b', caseSensitive: false).hasMatch(q))) {
        for (final w in words) {
          q = q.replaceAll(RegExp(r'\b' + RegExp.escape(w) + r'\b', caseSensitive: false), ' ');
        }
        break;
      }
    }
  }
  // tidy dangling connectors left behind ("shoes for  under" → "shoes")
  q = q.replaceAll(RegExp(r'\s+'), ' ').trim();
  q = q.replaceAll(RegExp(r'\b(for|with|in|by|and|under|tak)$', caseSensitive: false), '').trim();
  return q;
}

/// Natural-language search (GET /ai/search): what the AI understood, the
/// extracted constraints as removable chips, and results with match reasons.
class SmartSearchScreen extends ConsumerStatefulWidget {
  const SmartSearchScreen({super.key, required this.query});

  final String query;

  @override
  ConsumerState<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends ConsumerState<SmartSearchScreen> {
  late String _query = widget.query.trim();
  late final _field = TextEditingController(text: _query);

  @override
  void didUpdateWidget(SmartSearchScreen old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) _run(widget.query);
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _run(String q) {
    final next = q.trim();
    _field.text = next;
    setState(() => _query = next);
  }

  void _removeChip(EntityChipData chip, {String? value}) {
    final next = removeFromQuery(_query, type: chip.type, label: chip.label, value: value);
    if (next == _query || next.isEmpty) {
      AppSnack.info(context, next.isEmpty ? 'That was the whole search. Try a new one.' : "Couldn't drop that filter from the search text.");
      return;
    }
    _run(next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _field,
          textInputAction: TextInputAction.search,
          onSubmitted: _run,
          decoration: InputDecoration(
            hintText: 'Describe what you want…',
            isDense: true,
            prefixIcon: const AiMark(size: 18),
            prefixIconConstraints: const BoxConstraints(minWidth: 40),
            suffixIcon: IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search_rounded),
              onPressed: () => _run(_field.text),
            ),
          ),
        ),
        actions: const [SizedBox(width: AppSpacing.sm)],
      ),
      body: _query.isEmpty ? _intro(context) : _results(context),
    );
  }

  Widget _intro(BuildContext context) {
    const examples = ['red running shoes for women under 15k', 'sasta mobile 30k tak', 'gaming laptop with rtx under 300k', 'gift for dad under 5000'];
    return EmptyState(
      iconWidget: const AiMark(size: 30),
      title: 'Search the way you talk',
      message: 'Try: ${examples.join(' · ')}',
      actionLabel: 'Try an example',
      onAction: () => _run(examples.first),
    );
  }

  Widget _results(BuildContext context) {
    final async = ref.watch(smartSearchProvider(_query));
    return async.when(
      skipLoadingOnRefresh: true,
      loading: () => CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverResponsiveCenter(
            verticalPadding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            sliver: const SliverToBoxAdapter(
              child: AiThinking(messages: ['Understanding your request…', 'Extracting budget, brand and category…', 'Ranking results…']),
            ),
          ),
          const SliverResponsiveCenter(sliver: SliverProductGrid.loading(count: 6)),
        ],
      ),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(smartSearchProvider(_query))),
      data: (r) => CustomScrollView(
        slivers: [
          SliverResponsiveCenter(
            verticalPadding: const EdgeInsets.only(top: AppSpacing.md),
            sliver: SliverToBoxAdapter(child: _Interpretation(result: r, onRemove: _removeChip)),
          ),
          if (r.fallback)
            SliverResponsiveCenter(
              verticalPadding: const EdgeInsets.only(top: AppSpacing.sm),
              sliver: SliverToBoxAdapter(child: _FallbackNotice(query: _query)),
            ),
          SliverResponsiveCenter(
            verticalPadding: const EdgeInsets.fromLTRB(0, AppSpacing.md, 0, AppSpacing.sm),
            sliver: SliverToBoxAdapter(
              child: Text(
                r.products.isEmpty ? 'No matches' : '${Formatters.plural(r.total, 'result')} · ranked by AI match',
                style: context.textTheme.labelLarge!.copyWith(color: context.colors.muted),
              ),
            ),
          ),
          if (r.products.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'Nothing matched',
                message: 'Remove a filter above, or describe it differently.',
                actionLabel: 'Ask the assistant',
                onAction: () => context.go(Routes.assistantWith(prompt: _query)),
              ),
            )
          else
            SliverResponsiveCenter(
              verticalPadding: const EdgeInsets.only(bottom: AppSpacing.xxl),
              sliver: SliverAiProductGrid(products: r.products, source: 'smart_search'),
            ),
        ],
      ),
    );
  }
}

class _Interpretation extends StatelessWidget {
  const _Interpretation({required this.result, required this.onRemove});

  final SmartSearchResult result;
  final void Function(EntityChipData chip, {String? value}) onRemove;

  @override
  Widget build(BuildContext context) {
    final r = result;
    // prefer the server's chips; fall back to chips derived from entities
    final fromServer = [for (final c in r.chips) (EntityChipData(c.type, c.label, slug: c.value), c.value)];
    final chips = fromServer.isNotEmpty ? fromServer : [for (final c in entityChips(r.entities)) (c, c.slug)];
    return AiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AiHeader(title: 'Here is what I understood'),
          if (r.interpretation.isNotEmpty) ...[
            AppSpacing.gapXs,
            Text(r.interpretation, style: context.textTheme.bodyMedium!.copyWith(height: 1.45)),
          ],
          if (chips.isNotEmpty) ...[
            AppSpacing.gapSm,
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: 0,
              children: [
                for (final (chip, value) in chips) EntityChip(chip: chip, onRemove: () => onRemove(chip, value: value)),
              ],
            ),
            Text('Remove a chip to search again without it.', style: context.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.1),
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: colors.warning.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tune_rounded, size: 18, color: colors.warning),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'No exact matches, so I relaxed some constraints. These are the closest options.',
              style: context.textTheme.bodySmall!.copyWith(color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}
