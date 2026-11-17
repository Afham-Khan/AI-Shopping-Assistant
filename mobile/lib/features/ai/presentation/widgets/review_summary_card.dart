import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/ai_models.dart';
import '../../providers/ai_providers.dart';
import 'ai_ui.dart';
import 'simple_markdown.dart';

/// AI summary of a product's reviews (GET /ai/review-summary/:productId):
/// sentiment gauge, pros/cons with mention counts, summary and quotes.
/// Hidden when the product has no reviews.
class ReviewSummaryCard extends ConsumerWidget {
  const ReviewSummaryCard({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reviewSummaryProvider(productId));
    return async.when(
      skipLoadingOnRefresh: true,
      data: (s) => s.reviewCount == 0 ? const SizedBox.shrink() : _SummaryBody(summary: s),
      loading: () => const _SummarySkeleton(),
      error: (e, _) => AiInlineError(
        error: e,
        title: "Couldn't summarize reviews",
        onRetry: () => ref.invalidate(reviewSummaryProvider(productId)),
      ),
    );
  }
}

Color sentimentColor(AppPalette colors, double score) {
  if (score >= 0.35) return colors.success;
  if (score >= 0.05) return colors.primary;
  if (score > -0.2) return colors.warning;
  return colors.error;
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({required this.summary});

  final ReviewSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final s = summary;
    final gauge = _SentimentGauge(score: s.sentimentScore, label: s.sentimentLabel);

    return Semantics(
      container: true,
      label: 'AI review summary: ${s.sentimentLabel}',
      child: AiCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AiHeader(title: 'What buyers say', caption: 'AI summary of verified reviews'),
            AppSpacing.gapMd,
            LayoutBuilder(
              builder: (context, c) {
                final text = SimpleMarkdown(s.summary);
                if (c.maxWidth < 420) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Center(child: gauge), AppSpacing.gapMd, text],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [gauge, AppSpacing.gapLg, Expanded(child: text)],
                );
              },
            ),
            if (s.pros.isNotEmpty) ...[
              AppSpacing.gapMd,
              _AspectGroup(title: 'Loved', icon: Icons.thumb_up_alt_outlined, items: s.pros, color: colors.success),
            ],
            if (s.cons.isNotEmpty) ...[
              AppSpacing.gapSm,
              _AspectGroup(title: 'Watch out', icon: Icons.thumb_down_alt_outlined, items: s.cons, color: colors.sale),
            ],
            if (s.highlights.isNotEmpty) ...[
              AppSpacing.gapMd,
              for (final h in s.highlights.take(3)) _Quote(text: h),
            ],
            AppSpacing.gapSm,
            Row(
              children: [
                AiSparkleIcon(size: 14, color: colors.muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'AI generated from ${Formatters.plural(s.reviewCount, 'review')}. May not reflect every opinion.',
                    style: t.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SentimentGauge extends StatelessWidget {
  const _SentimentGauge({required this.score, required this.label});

  final double score;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = sentimentColor(colors, score);
    return Semantics(
      label: 'Sentiment $label',
      excludeSemantics: true,
      child: SizedBox(
        width: 132,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: (score + 1) / 2),
              duration: context.motion(const Duration(milliseconds: 900)),
              curve: AppCurves.standard,
              builder: (context, v, _) => CustomPaint(
                size: const Size(132, 72),
                painter: _GaugePainter(
                  value: v,
                  track: colors.surfaceVariant,
                  colors: [colors.error, colors.warning, colors.primary, colors.success],
                  needle: colors.text,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: context.textTheme.titleSmall!.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.track, required this.colors, required this.needle});

  /// 0..1 (0 = very negative, 1 = very positive)
  final double value;
  final Color track;
  final List<Color> colors;
  final Color needle;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 12.0;
    final radius = math.min(size.width / 2, size.height) - stroke / 2;
    final center = Offset(size.width / 2, size.height - 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = track
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    final sweep = Paint()
      ..shader = SweepGradient(
        startAngle: math.pi,
        endAngle: 2 * math.pi,
        colors: colors,
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi * value.clamp(0.0, 1.0), false, sweep);

    final angle = math.pi + math.pi * value.clamp(0.0, 1.0);
    final tip = center + Offset(math.cos(angle), math.sin(angle)) * (radius - stroke);
    canvas.drawLine(
      center,
      tip,
      Paint()
        ..color = needle
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(center, 4, Paint()..color = needle);
  }

  @override
  bool shouldRepaint(_GaugePainter old) => old.value != value || old.track != track || old.needle != needle;
}

class _AspectGroup extends StatelessWidget {
  const _AspectGroup({required this.title, required this.icon, required this.items, required this.color});

  final String title;
  final IconData icon;
  final List<AspectCount> items;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(title, style: t.labelLarge!.copyWith(color: color)),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final a in items)
              Semantics(
                label: '${a.aspect}, mentioned ${Formatters.plural(a.mentions, 'time')}',
                excludeSemantics: true,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(color.withValues(alpha: context.isDark ? 0.18 : 0.1), colors.surface),
                    borderRadius: AppRadii.pillAll,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          a.aspect.capitalized,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelMedium!.copyWith(color: colors.text, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (a.mentions > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${a.mentions}',
                          style: t.labelSmall!.copyWith(color: color, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.inputAll,
        border: Border(left: BorderSide(color: colors.ai, width: 3)),
      ),
      child: Text(
        '“$text”',
        style: context.textTheme.bodySmall!.copyWith(color: colors.text, fontStyle: FontStyle.italic, height: 1.45),
      ),
    );
  }
}

class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return AiCard(
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AiThinking(messages: ['Reading reviews…', 'Finding common themes…'], lines: 0),
          AppSpacing.gapMd,
          Row(
            children: [
              Skeleton(width: 96, height: 56),
              AppSpacing.gapMd,
              Expanded(child: SkeletonText(lines: 3)),
            ],
          ),
        ],
      ),
    );
  }
}
