import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../ai/presentation/widgets/ai_ui.dart';
import '../../../ai/presentation/widgets/entity_chips.dart';
import '../../data/chat_models.dart';

/// "Show AI reasoning": a compact, data-like readout of how the reply was
/// produced — intent + confidence, extracted entities, engine and latency.
class ReasoningPanel extends StatelessWidget {
  const ReasoningPanel({super.key, required this.meta});

  final ChatMeta meta;

  static String sourceLabel(String? source) => switch (source) {
    'local' => 'local nlu',
    'gemini' => 'gemini llm',
    'groq' => 'groq llm',
    null => 'n/a',
    final s => s,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final chips = entityChips(meta.entities);
    final mono = t.labelMedium!.copyWith(
      fontFamily: 'monospace',
      fontFeatures: const [FontFeature.tabularFigures()],
      color: colors.text,
    );
    final key = mono.copyWith(color: colors.muted);

    Widget row(String k, Widget value) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 72, child: Text(k, style: key)),
          Expanded(child: value),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: 'AI reasoning',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.sm),
        decoration: BoxDecoration(
          color: colors.surfaceVariant.withValues(alpha: 0.6),
          borderRadius: AppRadii.inputAll,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('reasoning', style: key.copyWith(color: colors.ai, fontWeight: FontWeight.w700)),
            if (meta.intent != null)
              row(
                'intent',
                Row(
                  children: [
                    Flexible(child: Text(meta.intent!, style: mono, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (meta.confidence != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(child: AiConfidenceBar(value: meta.confidence!, semanticLabel: 'Intent confidence')),
                      const SizedBox(width: AppSpacing.xs),
                      Text(meta.confidence!.toStringAsFixed(2), style: mono),
                    ],
                  ],
                ),
              ),
            if (meta.normalized != null) row('read as', Text('"${meta.normalized}"', style: mono)),
            if (meta.corrections.isNotEmpty)
              row('fixed', Text(meta.corrections.map((c) => '${c.from} → ${c.to}').join(', '), style: mono)),
            row('engine', Text(ReasoningPanel.sourceLabel(meta.source), style: mono)),
            if (meta.fallback) row('search', Text('constraints relaxed', style: mono.copyWith(color: colors.warning))),
            if (meta.latencyMs != null) row('latency', Text('${meta.latencyMs} ms', style: mono)),
            if (meta.products.isNotEmpty) row('ranked', Text('${meta.products.length} products', style: mono)),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('entities', style: key),
              const SizedBox(height: 4),
              EntityChipWrap(chips: chips, dense: true),
            ],
          ],
        ),
      ),
    );
  }
}
