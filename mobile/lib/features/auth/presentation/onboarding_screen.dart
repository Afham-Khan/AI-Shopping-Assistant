import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/models/product.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/onboarding_provider.dart';
import '../providers/storefront_provider.dart';

/// First-launch intro: three short pages, each demonstrated with a small
/// working vignette built from real products in the store (not stock art).
/// Arrow keys page through it on web/desktop.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Intro {
  const _Intro(this.eyebrow, this.lead, this.accent, this.body);

  final String eyebrow;
  final String lead;
  final String accent;
  final String body;
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _focus = FocusNode(debugLabel: 'onboarding');
  int _page = 0;

  static const _pages = [
    _Intro('Ask', 'Say what you need,', 'in plain words.', 'No filters to learn. Describe the thing, the budget and the deal-breakers. Zel finds what fits.'),
    _Intro('Picks', 'Picks with', 'the reasons attached.', 'Every recommendation shows why it made the cut, so you can agree or push back.'),
    _Intro('Compare', 'Two options.', 'One clear answer.', 'Side-by-side specs and a straight verdict from the reviews. You make the call.'),
  ];

  bool get _isLast => _page == _pages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(onboardingDoneProvider.notifier).complete();
    if (mounted) context.go(Routes.login);
  }

  void _go(int page) {
    if (page < 0 || page >= _pages.length) return;
    if (context.reduceMotion) {
      _controller.jumpToPage(page);
    } else {
      _controller.animateToPage(page, duration: AppDurations.slow, curve: AppCurves.standard);
    }
  }

  void _next() => _isLast ? _finish() : _go(_page + 1);

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final products = ref.watch(onboardingProductsProvider).value ?? const <ProductSummary>[];

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _go(_page - 1),
        },
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.xs, 0),
                      child: Row(
                        children: [
                          const AppLogo(size: 26),
                          const Spacer(),
                          AnimatedOpacity(
                            opacity: _isLast ? 0 : 1,
                            duration: context.motion(AppDurations.fast),
                            child: TextButton(
                              onPressed: _isLast ? null : _finish,
                              style: TextButton.styleFrom(foregroundColor: colors.muted),
                              child: const Text('Skip'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: _pages.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (_, i) => _IntroPage(
                          index: i,
                          intro: _pages[i],
                          vignette: switch (i) {
                            0 => _AskVignette(product: products.elementAtOrNull(0)),
                            1 => _PickVignette(product: products.elementAtOrNull(1)),
                            _ => _CompareVignette(a: products.elementAtOrNull(2), b: products.elementAtOrNull(3)),
                          },
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xs, AppSpacing.xl, AppSpacing.xl),
                      child: Column(
                        children: [
                          _Progress(count: _pages.length, index: _page),
                          AppSpacing.gapLg,
                          AppButton(
                            label: _isLast ? 'Get started' : 'Continue',
                            trailingIcon: Icons.arrow_forward_rounded,
                            onPressed: _next,
                            expand: true,
                            size: AppButtonSize.large,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.index, required this.intro, required this.vignette});

  final int index;
  final _Intro intro;
  final Widget vignette;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // the vignette gives way first on short screens so the copy never clips
        final stage = (constraints.maxHeight * 0.50).clamp(150.0, 320.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Container(
                    height: stage,
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                      border: Border.all(color: colors.border),
                    ),
                    child: DotGridBackground(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: SizedBox(width: 300, child: vignette),
                        ),
                      ),
                    ),
                  ),
                ),
                AppSpacing.gapXl,
                Eyebrow(intro.eyebrow, index: index + 1),
                AppSpacing.gapSm,
                Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${intro.lead}\n'),
                        TextSpan(text: intro.accent, style: TextStyle(color: colors.primary)),
                      ],
                    ),
                    style: t.displaySmall,
                  ),
                ),
                AppSpacing.gapSm,
                Text(intro.body, style: t.bodyLarge!.copyWith(color: colors.muted, fontSize: 15, height: 1.55)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Square studio well with a real product photo (or a quiet placeholder).
class _Well extends StatelessWidget {
  const _Well({required this.product, required this.size, this.fallback = Icons.shopping_bag_outlined});

  final ProductSummary? product;
  final double size;
  final IconData fallback;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.imageWell, borderRadius: AppRadii.inputAll),
      child: product == null
          ? Icon(fallback, size: size * 0.36, color: colors.onImageWell.withValues(alpha: 0.28))
          : Padding(
              padding: EdgeInsets.all(size * 0.1),
              child: AppNetworkImage(product!.thumbnail, fit: BoxFit.contain, backgroundColor: Colors.transparent),
            ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(AppSpacing.sm), this.accent = false});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: accent ? colors.primary.withValues(alpha: 0.45) : colors.border),
      ),
      child: child,
    );
  }
}

/// 01 — a question in plain words, and Zel's answer with a real product.
class _AskVignette extends StatelessWidget {
  const _AskVignette({required this.product});

  final ProductSummary? product;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final p = product;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 230),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 9),
            decoration: BoxDecoration(
              color: colors.surfaceRaised,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(3),
              ),
            ),
            child: Text(
              'Something well reviewed for everyday wear, not too pricey',
              style: t.bodySmall!.copyWith(color: colors.text, fontSize: 12.5, height: 1.4),
            ),
          ),
        ),
        AppSpacing.gapSm,
        _Panel(
          accent: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const AiSparkleIcon(size: 12),
                  const SizedBox(width: 6),
                  Text('ZEL', style: AppType.eyebrow(context).copyWith(fontSize: 10)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Start here. Top rated, and buyers mention it holds up.',
                style: t.bodySmall!.copyWith(color: colors.text, fontSize: 12.5, height: 1.4),
              ),
              AppSpacing.gapSm,
              Row(
                children: [
                  _Well(product: p, size: 52),
                  AppSpacing.gapSm,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          p?.title ?? 'Everyday sneakers',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.labelLarge!.copyWith(fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            RatingStars(p?.rating ?? 4.8, size: 12),
                            const SizedBox(width: AppSpacing.xs),
                            Flexible(child: PriceText(p?.price ?? 12999, size: PriceSize.small, singleLine: true)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 02 — a pick with its match score and the reasons behind it.
class _PickVignette extends StatelessWidget {
  const _PickVignette({required this.product});

  final ProductSummary? product;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final p = product;

    Widget reason(String text) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.check_rounded, size: 14, color: colors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall!.copyWith(color: colors.text, fontSize: 12.5)),
          ),
        ],
      ),
    );

    return _Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              _Well(product: p, size: 108),
              const Positioned(left: 6, bottom: 6, child: AiBadge(label: '94% match')),
            ],
          ),
          AppSpacing.gapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  p?.title ?? 'Your next favourite',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge!.copyWith(fontSize: 13, height: 1.3),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('WHY THIS ONE', style: AppType.eyebrow(context, color: colors.faint).copyWith(fontSize: 9.5)),
                reason('Inside your budget'),
                reason('Rated ${Formatters.rating(p?.rating ?? 4.7)} by buyers'),
                reason('Close to what you browse'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 03 — two real products side by side, the better value marked.
class _CompareVignette extends StatelessWidget {
  const _CompareVignette({required this.a, required this.b});

  final ProductSummary? a;
  final ProductSummary? b;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final ratingA = a?.rating ?? 4.8;
    final ratingB = b?.rating ?? 4.5;
    final priceA = a?.price ?? 18999;
    final priceB = b?.price ?? 24999;
    // rating per rupee decides, so the line is true for whatever products load
    final firstWins = ratingA / priceA >= ratingB / priceB;

    Widget cell(String value, bool best) => Expanded(
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: AppType.data(context, color: best ? colors.primary : colors.muted, size: 11.5, weight: best ? FontWeight.w700 : FontWeight.w500),
      ),
    );

    Widget row(String label, String left, String right, bool leftBest) => Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Row(
        children: [
          SizedBox(width: 52, child: Text(label.toUpperCase(), style: AppType.eyebrow(context, color: colors.faint).copyWith(fontSize: 9.5))),
          cell(left, leftBest),
          cell(right, !leftBest),
        ],
      ),
    );

    Widget column(ProductSummary? p, String fallback) => Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Well(product: p, size: 72),
          const SizedBox(height: 6),
          Text(
            p?.title ?? fallback,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: t.labelMedium!.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );

    return _Panel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const SizedBox(width: 52), column(a, 'Option A'), column(b, 'Option B')],
          ),
          const SizedBox(height: 4),
          row('Rating', Formatters.rating(ratingA), Formatters.rating(ratingB), ratingA >= ratingB),
          row('Price', Formatters.priceCompact(priceA), Formatters.priceCompact(priceB), priceA <= priceB),
          AppSpacing.gapSm,
          Container(height: 1, color: colors.border),
          AppSpacing.gapXs,
          Row(
            children: [
              const AiSparkleIcon(size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Verdict: the ${firstWins ? 'first' : 'second'} is the better value.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall!.copyWith(color: colors.text, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Segmented progress with a mono page counter ("01 / 03").
class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Page ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: context.motion(AppDurations.normal),
              curve: AppCurves.standard,
              margin: const EdgeInsets.only(right: 6),
              width: i == index ? 28 : 12,
              height: 3,
              decoration: BoxDecoration(
                color: i == index ? colors.primary : colors.surfaceRaised,
                borderRadius: AppRadii.pillAll,
              ),
            ),
          const Spacer(),
          if (context.isWide) ...[
            const KbdChip('←'),
            const SizedBox(width: 4),
            const KbdChip('→'),
            const SizedBox(width: AppSpacing.sm),
          ],
          Text(
            '${(index + 1).toString().padLeft(2, '0')} / ${count.toString().padLeft(2, '0')}',
            style: AppType.data(context, color: colors.faint, size: 11),
          ),
        ],
      ),
    );
  }
}
