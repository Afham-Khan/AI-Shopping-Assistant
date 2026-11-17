import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/json_utils.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/ai_repository.dart';
import '../data/models/ai_models.dart';
import '../providers/ai_providers.dart';
import 'widgets/ai_ui.dart';
import 'widgets/entity_chips.dart';

/// AI Lab — a developer console for demos: model cards (GET /ai/insights)
/// and an NLU playground (POST /ai/nlu).
class AiLabScreen extends ConsumerWidget {
  const AiLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Lab'),
        actions: [
          IconButton(
            tooltip: 'Refresh model info',
            onPressed: () => ref.invalidate(aiInsightsProvider),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          final wide = c.maxWidth >= 1000;
          const models = _ModelCards();
          const playground = _Playground();
          if (wide) {
            return ResponsiveCenter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      children: const [_LabIntro(), AppSpacing.gapMd, models],
                    ),
                  ),
                  AppSpacing.gapXl,
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      children: const [playground],
                    ),
                  ),
                ],
              ),
            );
          }
          return ResponsiveCenter(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              children: const [_LabIntro(), AppSpacing.gapMd, playground, AppSpacing.gapXl, models],
            ),
          );
        },
      ),
    );
  }
}

class _LabIntro extends StatelessWidget {
  const _LabIntro();

  @override
  Widget build(BuildContext context) {
    return AiHeader(
      title: 'Under the hood of ${AppConfig.appName} AI',
      caption: 'Live model stats and a playground to test language understanding.',
    );
  }
}

TextStyle _mono(BuildContext context, {Color? color, FontWeight? weight}) => context.textTheme.labelMedium!.copyWith(
  fontFamily: 'monospace',
  fontFeatures: const [FontFeature.tabularFigures()],
  color: color ?? context.colors.text,
  fontWeight: weight,
);

/// A console-style card with a title row and key/value lines.
class _ConsoleCard extends StatelessWidget {
  const _ConsoleCard({required this.icon, required this.title, required this.children, this.status});

  final IconData icon;
  final String title;
  final List<Widget> children;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: colors.ai),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Semantics(header: true, child: Text(title, style: context.textTheme.titleSmall))),
              ?status,
            ],
          ),
          AppSpacing.gapSm,
          ...children,
        ],
      ),
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv(this.k, this.v);

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 128, child: Text(k, style: _mono(context, color: context.colors.muted))),
          Expanded(child: Text(v.isEmpty ? '—' : v, style: _mono(context))),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.on, required this.label});

  final bool on;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = on ? context.colors.success : context.colors.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: _mono(context, color: color, weight: FontWeight.w700)),
      ],
    );
  }
}

String _fmt(Object? v) {
  if (v == null) return '';
  if (v is num) return v is int || v == v.roundToDouble() ? Formatters.number(v) : v.toStringAsFixed(3);
  if (v is List) return v.join(', ');
  if (v is Map) return v.entries.map((e) => '${e.key}: ${_fmt(e.value)}').join(' · ');
  final d = DateTime.tryParse(v.toString());
  if (d != null && v.toString().contains('T')) return Formatters.dateTime(d);
  return v.toString();
}

/// Key/value lines for whatever extra keys the backend sends.
List<Widget> _extras(Map<String, dynamic> m, Set<String> shown) => [
  for (final e in m.entries)
    if (!shown.contains(e.key) && e.value != null && e.value is! Map && e.value is! List) _Kv(e.key, _fmt(e.value)),
];

class _ModelCards extends ConsumerWidget {
  const _ModelCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(aiInsightsProvider);
    return async.when(
      skipLoadingOnRefresh: false,
      loading: () => Column(
        children: [for (var i = 0; i < 4; i++) ...[const Skeleton(height: 140, borderRadius: AppRadii.cardAll), AppSpacing.gapSm]],
      ),
      error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(aiInsightsProvider)),
      data: (i) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _cards(context, i)),
    );
  }

  List<Widget> _cards(BuildContext context, AiInsights i) {
    final im = i.intentModel;
    final classes = JsonX.asStringList(im['classes']);
    final acc = JsonX.asDoubleOrNull(im['testAccuracy']);
    final accRatio = acc == null ? null : (acc > 1 ? acc / 100 : acc);
    final emb = i.embeddings;
    final llm = i.llm;
    final llmOn = JsonX.asBool(llm['enabled']);
    final signals = JsonX.asStringList(i.recommender['signals']);
    final stats = i.stats;
    final pos = JsonX.asDoubleOrNull(stats['positiveFeedbackRate']);
    final visual = i.visual;
    final catalog = i.catalog;

    return [
      _ConsoleCard(
        icon: Icons.account_tree_outlined,
        title: 'Intent classifier',
        status: _StatusDot(on: im.isNotEmpty, label: im.isNotEmpty ? 'trained' : 'n/a'),
        children: [
          _Kv('algorithm', _fmt(im['algorithm'])),
          _Kv('classes', '${classes.length}'),
          _Kv('train samples', _fmt(im['trainingSamples'])),
          if (im['trainedAt'] != null) _Kv('trained', _fmt(im['trainedAt'])),
          ..._extras(im, {'algorithm', 'classes', 'trainingSamples', 'testAccuracy', 'trainedAt'}),
          if (accRatio != null) ...[
            AppSpacing.gapXs,
            ScoreRow(label: 'test accuracy', value: accRatio, highlight: true),
          ],
          if (classes.isNotEmpty) ...[
            AppSpacing.gapSm,
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final c in classes) _Pill(c)],
            ),
          ],
        ],
      ),
      _ConsoleCard(
        icon: Icons.scatter_plot_outlined,
        title: 'Embeddings',
        status: _StatusDot(on: emb['mode'] == 'neural', label: _fmt(emb['mode']).isEmpty ? 'n/a' : _fmt(emb['mode'])),
        children: [
          _Kv('model', _fmt(emb['model'])),
          _Kv('dimensions', _fmt(emb['dims'])),
          _Kv('indexed', '${_fmt(emb['indexedProducts'])} products'),
          ..._extras(emb, {'mode', 'model', 'dims', 'indexedProducts'}),
        ],
      ),
      if (visual.isNotEmpty)
        _ConsoleCard(
          icon: Icons.image_search_rounded,
          title: 'Vision model (Snap & Find)',
          status: _StatusDot(on: JsonX.asBool(visual['enabled']), label: _fmt(visual['status']).isEmpty ? 'n/a' : _fmt(visual['status'])),
          children: [
            _Kv('model', _fmt(visual['model'])),
            _Kv('dimensions', _fmt(visual['dims'])),
            _Kv('indexed', '${_fmt(visual['indexedImages'])} images'),
            ..._extras(visual, {'enabled', 'status', 'model', 'dims', 'indexedImages', 'error'}),
            if (JsonX.asStringOrNull(visual['error']) != null) _Kv('error', _fmt(visual['error'])),
          ],
        ),
      _ConsoleCard(
        icon: Icons.forum_outlined,
        title: 'Language model',
        status: _StatusDot(on: llmOn, label: llmOn ? 'online' : 'local only'),
        children: [
          _Kv('provider', _fmt(llm['provider'])),
          _Kv('model', _fmt(llm['model'])),
          ..._extras(llm, {'provider', 'model', 'enabled'}),
          if (!llmOn)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Replies come from the local NLU + ranking engine.', style: context.textTheme.bodySmall),
            ),
        ],
      ),
      _ConsoleCard(
        icon: Icons.hub_outlined,
        title: 'Recommender',
        children: [
          Text('Signals', style: _mono(context, color: context.colors.muted)),
          AppSpacing.gapXs,
          if (signals.isEmpty) Text('—', style: _mono(context)) else Wrap(spacing: 6, runSpacing: 6, children: [for (final s in signals) _Pill(s)]),
          ..._extras(i.recommender, {'signals'}),
        ],
      ),
      _ConsoleCard(
        icon: Icons.insights_outlined,
        title: 'Usage',
        children: [
          _Kv('conversations', _fmt(stats['conversations'])),
          _Kv('messages', _fmt(stats['messages'])),
          ..._extras(stats, {'conversations', 'messages', 'positiveFeedbackRate'}),
          for (final e in catalog.entries)
            if (e.value != null && e.value is! Map && e.value is! List) _Kv('catalog ${e.key}', _fmt(e.value)),
          if (pos != null) ...[
            AppSpacing.gapXs,
            ScoreRow(label: 'positive feedback', value: pos > 1 ? pos / 100 : pos, highlight: true),
          ],
        ],
      ),
    ];
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: colors.surfaceVariant, borderRadius: AppRadii.inputAll),
      child: Text(text, style: _mono(context).copyWith(fontSize: 12)),
    );
  }
}

class _Playground extends ConsumerStatefulWidget {
  const _Playground();

  static const examples = [
    'gaming laptop under 2 lakh',
    'sasta mobile chahiye 30k tak',
    'samsng phnoe with gud camra',
    'red running shoes for women under 15k',
    'compare the first two',
    'gift for my sister, budget 5000',
    'where is my order?',
    'mujhe ammi ke liye kuch chahiye',
  ];

  @override
  ConsumerState<_Playground> createState() => _PlaygroundState();
}

class _PlaygroundState extends ConsumerState<_Playground> {
  final _text = TextEditingController();
  bool _busy = false;
  NluResult? _result;
  ApiException? _error;
  int? _roundTrip;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _analyze([String? value]) async {
    final text = (value ?? _text.text).trim();
    if (text.isEmpty || _busy) return;
    if (value != null) _text.text = value;
    setState(() {
      _busy = true;
      _error = null;
    });
    final watch = Stopwatch()..start();
    try {
      final r = await ref.read(aiRepositoryProvider).nlu(text);
      if (mounted) {
        setState(() {
          _result = r;
          _roundTrip = watch.elapsedMilliseconds;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final r = _result;
    return _ConsoleCard(
      icon: Icons.terminal_rounded,
      title: 'NLU playground',
      children: [
        Text('Type any shopping sentence: English, Roman Urdu, typos, budgets.', style: t.bodySmall),
        AppSpacing.gapSm,
        TextField(
          controller: _text,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _analyze(),
          style: _mono(context).copyWith(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'e.g. sasta mobile chahiye 30k tak',
            prefixIcon: const Icon(Icons.chevron_right_rounded),
            suffixIcon: Padding(
              padding: const EdgeInsets.all(4),
              child: AppButton(label: 'Analyze', size: AppButtonSize.small, loading: _busy, onPressed: () => _analyze()),
            ),
            suffixIconConstraints: const BoxConstraints(minHeight: 44),
          ),
        ),
        AppSpacing.gapSm,
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final e in _Playground.examples)
              ActionChip(
                label: Text(e, style: _mono(context).copyWith(fontSize: 12)),
                onPressed: () => _analyze(e),
              ),
          ],
        ),
        AppSpacing.gapMd,
        if (_error != null)
          AiInlineError(error: _error!, title: 'Analysis failed', onRetry: _analyze)
        else if (_busy && r == null)
          const SkeletonText(lines: 4)
        else if (r != null)
          AnimatedOpacity(
            opacity: _busy ? 0.5 : 1,
            duration: context.motion(AppDurations.fast),
            child: _NluOutput(result: r, roundTrip: _roundTrip),
          )
        else
          Text('Results appear here.', style: t.bodySmall),
      ],
    );
  }
}

class _NluOutput extends StatelessWidget {
  const _NluOutput({required this.result, this.roundTrip});

  final NluResult result;
  final int? roundTrip;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final label = _mono(context, color: colors.muted);
    final chips = entityChips(result.entities);
    final ranked = result.ranked.take(5).toList();
    return SlideFadeIn(
      key: ValueKey(result),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('intent  ', style: label),
              Flexible(child: Text(result.intent, style: _mono(context, color: colors.ai, weight: FontWeight.w700).copyWith(fontSize: 15))),
              const Spacer(),
              if (result.latencyMs != null) Text('${result.latencyMs!.toStringAsFixed(result.latencyMs! < 10 ? 2 : 0)} ms', style: label),
              if (roundTrip != null) Text('  ·  rtt $roundTrip ms', style: label),
            ],
          ),
          if (result.normalized != null) ...[
            AppSpacing.gapXs,
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'read as  ', style: label),
                  TextSpan(text: '"${result.normalized}"', style: _mono(context)),
                ],
              ),
            ),
          ],
          if (result.corrections.isNotEmpty) ...[
            AppSpacing.gapXs,
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('fixed', style: label),
                for (final c in result.corrections) _Pill('${c.from} → ${c.to}'),
              ],
            ),
          ],
          AppSpacing.gapSm,
          for (var i = 0; i < ranked.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ScoreRow(label: ranked[i].intent, value: ranked[i].confidence, highlight: i == 0),
            ),
          AppSpacing.gapSm,
          Text('entities', style: label),
          AppSpacing.gapXs,
          if (chips.isEmpty) Text('none detected', style: _mono(context)) else EntityChipWrap(chips: chips),
          if (result.tokens.isNotEmpty) ...[
            AppSpacing.gapSm,
            Text('tokens (${result.tokens.length})', style: label),
            AppSpacing.gapXs,
            Wrap(spacing: 4, runSpacing: 4, children: [for (final tok in result.tokens) _Pill(tok)]),
          ],
        ],
      ),
    );
  }
}
