import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../data/models/ai_models.dart';
import '../providers/ai_providers.dart';
import 'widgets/ai_ui.dart';

/// "My Shopping DNA" (GET /ai/profile): what the recommender has learned —
/// persona, trait radar + bars, top categories/brands, price band, signals,
/// and how the learning works.
class ShoppingDnaScreen extends ConsumerWidget {
  const ShoppingDnaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(shoppingProfileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Shopping DNA')),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const _DnaSkeleton(),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(shoppingProfileProvider)),
        data: (p) => RefreshIndicator(
          onRefresh: () => ref.refresh(shoppingProfileProvider.future),
          child: p.isEmpty ? _Empty(profile: p) : _DnaBody(profile: p),
        ),
      ),
    );
  }
}

class _DnaBody extends StatelessWidget {
  const _DnaBody({required this.profile});

  final ShoppingProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final sections = <Widget>[
      if (p.traits.isNotEmpty) _Section(title: 'Your traits', child: _Traits(traits: p.traits)),
      if (p.topCategories.isNotEmpty)
        _Section(
          title: 'Top categories',
          child: _Shares(items: p.topCategories, colorFor: (name) => AppColors.departmentAccent(name.toLowerCase().replaceAll(' ', '-'))),
        ),
      if (p.topBrands.isNotEmpty) _Section(title: 'Top brands', child: _Shares(items: p.topBrands, colorFor: (_) => context.colors.secondary)),
      if (p.priceMax != null && p.priceMax! > 0) _Section(title: 'Your price band', child: _PriceBand(profile: p)),
      if (p.signals.isNotEmpty) _Section(title: 'What I learned from', child: _Signals(signals: p.signals)),
      _Section(title: 'How ${AppConfig.appName} learns', child: _HowItLearns(serverNotes: p.howWeUseIt)),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 900;
        return ListView(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: math.max(context.pagePadding, (c.maxWidth - Breakpoints.maxContent) / 2)),
          children: [
            _PersonaCard(profile: p),
            AppSpacing.gapLg,
            if (twoCol)
              Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.lg,
                children: [
                  for (final s in sections)
                    SizedBox(width: (math.min(c.maxWidth, Breakpoints.maxContent) - context.pagePadding * 2 - AppSpacing.lg) / 2, child: s),
                ],
              )
            else
              for (final s in sections) ...[s, AppSpacing.gapLg],
          ],
        );
      },
    );
  }
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({required this.profile});

  final ShoppingProfile profile;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    return AiCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AiMark(size: 18),
              const SizedBox(width: AppSpacing.xs),
              Text('Your shopper persona', style: t.labelLarge!.copyWith(color: context.colors.muted)),
            ],
          ),
          AppSpacing.gapXs,
          Semantics(header: true, child: Text(profile.personaTitle, style: t.headlineSmall!.copyWith(fontWeight: FontWeight.w700))),
          if (profile.personaDescription.isNotEmpty) ...[
            AppSpacing.gapXs,
            Text(profile.personaDescription, style: t.bodyMedium!.copyWith(height: 1.5)),
          ],
          if (profile.lastUpdated != null) ...[
            AppSpacing.gapSm,
            Text('Updated ${Formatters.relative(profile.lastUpdated)}', style: t.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: colors.surface, borderRadius: AppRadii.cardAll, border: Border.all(color: colors.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: context.textTheme.titleMedium)),
          AppSpacing.gapMd,
          child,
        ],
      ),
    );
  }
}

class _Traits extends StatelessWidget {
  const _Traits({required this.traits});

  final List<ProfileTrait> traits;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (traits.length >= 3)
          Center(
            child: ExcludeSemantics(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: context.motion(const Duration(milliseconds: 800)),
                curve: AppCurves.standard,
                builder: (context, v, _) => CustomPaint(
                  size: const Size.square(220),
                  painter: TraitRadarPainter(
                    values: [for (final tr in traits) tr.value * v],
                    labels: [for (final tr in traits) tr.label],
                    grid: colors.border,
                    fill: colors.primary.withValues(alpha: 0.18),
                    stroke: colors.primary,
                    labelStyle: t.labelSmall!.copyWith(color: colors.muted),
                  ),
                ),
              ),
            ),
          ),
        AppSpacing.gapMd,
        for (final tr in traits)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ScoreRow(label: tr.label, value: tr.value, highlight: true, labelWidth: 140),
                if (tr.description.isNotEmpty) Text(tr.description, style: t.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

/// Radar chart for 3+ traits (values 0..1).
class TraitRadarPainter extends CustomPainter {
  TraitRadarPainter({
    required this.values,
    required this.labels,
    required this.grid,
    required this.fill,
    required this.stroke,
    required this.labelStyle,
  });

  final List<double> values;
  final List<String> labels;
  final Color grid;
  final Color fill;
  final Color stroke;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 3) return;
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 28;
    Offset point(int i, double r) {
      final a = -math.pi / 2 + 2 * math.pi * i / n;
      return center + Offset(math.cos(a), math.sin(a)) * r;
    }

    final gridPaint = Paint()
      ..color = grid
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final f in [0.25, 0.5, 0.75, 1.0]) {
      final path = Path()..moveTo(point(0, radius * f).dx, point(0, radius * f).dy);
      for (var i = 1; i < n; i++) {
        path.lineTo(point(i, radius * f).dx, point(i, radius * f).dy);
      }
      canvas.drawPath(path..close(), gridPaint);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(center, point(i, radius), gridPaint);
    }

    final shape = Path();
    for (var i = 0; i < n; i++) {
      final p = point(i, radius * values[i].clamp(0.0, 1.0));
      i == 0 ? shape.moveTo(p.dx, p.dy) : shape.lineTo(p.dx, p.dy);
    }
    shape.close();
    canvas.drawPath(shape, Paint()..color = fill);
    canvas.drawPath(
      shape,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    for (var i = 0; i < n; i++) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 80);
      final p = point(i, radius + 16);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(TraitRadarPainter old) => old.values != values || old.stroke != stroke || old.grid != grid;
}

class _Shares extends StatelessWidget {
  const _Shares({required this.items, required this.colorFor});

  final List<ShareItem> items;
  final Color Function(String name) colorFor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final s in items.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(s.name.titleCase, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textTheme.labelLarge),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: AiConfidenceBar(value: s.share, height: 8, color: colorFor(s.name), semanticLabel: s.name)),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 40,
                  child: Text(Formatters.percentFromRatio(s.share), textAlign: TextAlign.end, style: context.textTheme.labelMedium),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PriceBand extends StatelessWidget {
  const _PriceBand({required this.profile});

  final ShoppingProfile profile;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final min = profile.priceMin ?? 0;
    final max = profile.priceMax!;
    final avg = profile.priceAvg;
    final pos = avg == null || max <= min ? null : ((avg - min) / (max - min)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (avg != null) ...[
          Text('You usually spend around', style: t.bodySmall),
          Text(Formatters.price(avg), style: t.headlineSmall),
          AppSpacing.gapSm,
        ],
        LayoutBuilder(
          builder: (context, c) => SizedBox(
            height: 24,
            child: Stack(
              children: [
                Positioned.fill(
                  top: 8,
                  bottom: 8,
                  child: DecoratedBox(decoration: BoxDecoration(color: colors.warning.withValues(alpha: 0.35), borderRadius: AppRadii.pillAll)),
                ),
                if (pos != null)
                  Positioned(
                    left: (c.maxWidth - 4) * pos,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 4, decoration: BoxDecoration(color: colors.warning, borderRadius: AppRadii.pillAll)),
                  ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Formatters.price(min), style: t.labelMedium),
            Text(Formatters.price(max), style: t.labelMedium),
          ],
        ),
      ],
    );
  }
}

class _Signals extends StatelessWidget {
  const _Signals({required this.signals});

  final Map<String, int> signals;

  static IconData icon(String k) => switch (k) {
    'views' => Icons.visibility_outlined,
    'wishlist' => Icons.favorite_border_rounded,
    'cart' => Icons.shopping_cart_outlined,
    'purchases' => Icons.shopping_bag_outlined,
    'chats' => Icons.forum_outlined,
    'clicks' => Icons.ads_click_rounded,
    'searches' => Icons.search_rounded,
    _ => Icons.bolt_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final e in signals.entries)
          Container(
            constraints: const BoxConstraints(minWidth: 96),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: colors.surfaceVariant.withValues(alpha: 0.6), borderRadius: AppRadii.cardAll),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon(e.key), size: 18, color: colors.secondary),
                AppSpacing.gapXxs,
                Text(Formatters.compact(e.value), style: t.titleLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                Text(e.key.capitalized, style: t.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}

class _HowItLearns extends StatelessWidget {
  const _HowItLearns({this.serverNotes = const []});

  /// `howWeUseIt` from the API, shown under the generic steps.
  final List<String> serverNotes;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    const steps = [
      (Icons.touch_app_outlined, 'Signals', 'Views, wishlist saves, cart adds, purchases and chats are weighted (a purchase counts more than a view) and fade over time.'),
      (Icons.hub_outlined, 'Profile', 'Signals become affinities for categories, brands and a typical price band, plus traits like deal-seeking or brand loyalty.'),
      (Icons.leaderboard_outlined, 'Ranking', 'Every recommendation blends relevance, quality, popularity and your affinities, and shows the reasons behind it.'),
      (Icons.lock_outline_rounded, 'Privacy', 'Your profile is used only to personalize your own results. Clear your activity any time to reset it.'),
    ];
    return Column(
      children: [
        for (final (icon, title, body) in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: context.colors.ai),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text(title, style: t.titleSmall), Text(body, style: t.bodySmall)],
                  ),
                ),
              ],
            ),
          ),
        if (serverNotes.isNotEmpty) ...[
          const Divider(height: AppSpacing.lg),
          for (final note in serverNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check_rounded, size: 16, color: context.colors.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(note, style: t.bodySmall!.copyWith(color: context.colors.text))),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.profile});

  final ShoppingProfile profile;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: AppSpacing.xxl),
        EmptyState(
          iconWidget: const AiMark(size: 30),
          title: 'Your DNA is still forming',
          message: 'Browse, save and chat a little. ${AppConfig.assistantName} learns your taste from what you do and builds your profile here.',
          actionLabel: 'Start exploring',
          onAction: () => context.go(Routes.explore),
        ),
        Padding(padding: EdgeInsets.all(context.pagePadding), child: const _Section(title: 'How ${AppConfig.appName} learns', child: _HowItLearns())),
      ],
    );
  }
}

class _DnaSkeleton extends StatelessWidget {
  const _DnaSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(context.pagePadding),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Skeleton(height: 140, borderRadius: AppRadii.cardAll),
        AppSpacing.gapLg,
        Skeleton(height: 260, borderRadius: AppRadii.cardAll),
        AppSpacing.gapLg,
        Skeleton(height: 160, borderRadius: AppRadii.cardAll),
      ],
    );
  }
}
