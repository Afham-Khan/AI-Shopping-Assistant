import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/product.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../providers/onboarding_provider.dart';
import '../providers/storefront_provider.dart';

/// First-launch intro: three pages, each showing a real Zelora feature as a
/// small working vignette built from real products in the store:
///
/// 1. **Ask the assistant** — a plain-words request and its pick with reasons.
/// 2. **Snap & Find** — a photo search framing a product, with matches.
/// 3. **Discover + Bundle** — a swipe deck and a bundle that fits a budget.
///
/// Arrow keys page through it on web/desktop.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Intro {
  const _Intro(this.eyebrow, this.title, this.body);

  final String eyebrow;
  final String title;
  final String body;
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  final _focus = FocusNode(debugLabel: 'onboarding');
  int _page = 0;

  static const _pages = [
    _Intro(
      'Ask ${AppConfig.assistantName}',
      'Say what you need,\nin plain words',
      'Describe the thing, the budget and the deal-breakers. ${AppConfig.assistantName} reads the reviews and brings back picks with the reasons attached.',
    ),
    _Intro(
      'Snap & Find',
      'Seen it somewhere?\nSnap it, find it',
      'Take a photo of anything you like. ${AppConfig.assistantName} finds the closest matches in the store, and the better deals.',
    ),
    _Intro(
      'Discover & Bundle',
      'Swipe to discover,\nbundle under budget',
      'Swipe through picks to teach ${AppConfig.assistantName} your taste. Set a budget and get a complete set that fits it.',
    ),
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
    ProductSummary? at(int i) => products.elementAtOrNull(i);
    final snap = ref.watch(onboardingSnapProvider).value ?? const <ProductSummary>[];
    ProductSummary? snapAt(int i) => snap.elementAtOrNull(i) ?? at(i + 1);

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
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.sm, 0),
                  child: Row(
                    children: [
                      const Flexible(
                        child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: AppLogo(size: 30)),
                      ),
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
                      intro: _pages[i],
                      vignette: switch (i) {
                        0 => _AskVignette(product: at(0)),
                        1 => _SnapVignette(target: snapAt(0), matches: [snapAt(1), snapAt(2), snapAt(3)]),
                        _ => _DiscoverVignette(deck: [at(5), at(6), at(7)], bundle: [at(5), at(8), at(9)]),
                      },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.lg),
                  child: Column(
                    children: [
                      _Dots(count: _pages.length, index: _page),
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
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.intro, required this.vignette});

  final _Intro intro;
  final Widget vignette;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        // the vignette gives way first on short screens so the copy never clips
        final stage = (constraints.maxHeight * 0.56).clamp(170.0, 360.0);
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    height: stage,
                    width: double.infinity,
                    // scales down on short phones; the vignette is drawn at 320 wide
                    // decorative: it scales as a picture, so its text doesn't
                    // follow the text-size setting (the copy below does)
                    child: Center(
                      child: FittedBox(
                        child: MediaQuery.withNoTextScaling(child: SizedBox(width: 320, child: vignette)),
                      ),
                    ),
                  ),
                ),
                AppSpacing.gapLg,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: colors.surface, borderRadius: AppRadii.pillAll, boxShadow: colors.shadowSm),
                  child: Text(intro.eyebrow, style: t.labelMedium!.copyWith(color: colors.primary, fontWeight: FontWeight.w700)),
                ),
                AppSpacing.gapSm,
                Semantics(header: true, child: Text(intro.title, style: t.displaySmall!.copyWith(fontSize: 27))),
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

/// White card with the soft resting shadow, used to build the vignettes.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = const EdgeInsets.all(AppSpacing.sm), this.radius = AppRadii.card});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: colors.shadowMd,
      ),
      child: child,
    );
  }
}

/// Light product tile with a real photo (or a quiet placeholder).
class _Well extends StatelessWidget {
  const _Well({required this.product, required this.size, this.radius = AppRadii.input});

  final ProductSummary? product;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: colors.imageWell, borderRadius: BorderRadius.circular(radius)),
      child: product == null
          ? Icon(Icons.shopping_bag_outlined, size: size * 0.34, color: colors.onImageWell.withValues(alpha: 0.25))
          : Padding(
              padding: EdgeInsets.all(size * 0.1),
              child: AppNetworkImage(product!.thumbnail, fit: BoxFit.contain, backgroundColor: Colors.transparent),
            ),
    );
  }
}

/// 1 — a request in plain words, and the assistant's pick with a match score.
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
            constraints: const BoxConstraints(maxWidth: 240),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(6),
              ),
            ),
            child: Text(
              'Something well reviewed for everyday use, not too pricey',
              style: t.bodySmall!.copyWith(color: colors.onPrimary, fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        AppSpacing.gapSm,
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const AiMascot(size: 28, mood: AiMood.happy, animate: false),
                  const SizedBox(width: 8),
                  Text(AppConfig.assistantName, style: t.labelLarge!.copyWith(fontWeight: FontWeight.w800)),
                  const Spacer(),
                  const AiBadge(label: '94% match', solid: false),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Start here. Top rated, and buyers say it holds up.',
                style: t.bodySmall!.copyWith(color: colors.text, fontSize: 13, height: 1.4),
              ),
              AppSpacing.gapSm,
              Row(
                children: [
                  _Well(product: p, size: 60),
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
                          style: t.labelLarge!.copyWith(fontSize: 13.5),
                        ),
                        const SizedBox(height: 4),
                        RatingStars(p?.rating ?? 4.8, size: 12),
                        const SizedBox(height: 4),
                        PriceText(p?.price ?? 12999, size: PriceSize.small, singleLine: true),
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

/// 2 — a photo search: a product framed by camera brackets, then matches.
class _SnapVignette extends StatelessWidget {
  const _SnapVignette({required this.target, required this.matches});

  final ProductSummary? target;
  final List<ProductSummary?> matches;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Card(
          padding: const EdgeInsets.all(10),
          radius: 24,
          child: Stack(
            children: [
              _Well(product: target, size: 300, radius: 16),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: CustomPaint(painter: _BracketsPainter(colors.primary)),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: AppRadii.pillAll,
                      boxShadow: colors.shadowSm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera_rounded, size: 15, color: colors.primary),
                        const SizedBox(width: 6),
                        Text('3 matches found', style: t.labelMedium!.copyWith(color: colors.text, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        AppSpacing.gapSm,
        Row(
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _Card(
                  padding: const EdgeInsets.all(6),
                  radius: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(builder: (context, box) => _Well(product: matches[i], size: box.maxWidth, radius: 12)),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          Formatters.priceCompact(matches[i]?.price ?? (9999 + i * 2500)),
                          maxLines: 1,
                          style: t.labelMedium!.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Four rounded camera corners.
class _BracketsPainter extends CustomPainter {
  const _BracketsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final l = math.min(size.width, size.height) * 0.16;
    const r = 10.0;
    void corner(Offset o, double sx, double sy) {
      final path = Path()
        ..moveTo(o.dx, o.dy + sy * l)
        ..lineTo(o.dx, o.dy + sy * r)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + sx * r, o.dy)
        ..lineTo(o.dx + sx * l, o.dy);
      canvas.drawPath(path, paint);
    }

    corner(Offset.zero, 1, 1);
    corner(Offset(size.width, 0), -1, 1);
    corner(Offset(0, size.height), 1, -1);
    corner(Offset(size.width, size.height), -1, -1);
  }

  @override
  bool shouldRepaint(_BracketsPainter old) => old.color != color;
}

/// 3 — a swipe deck (Discover) over a bundle that fits a budget.
class _DiscoverVignette extends StatelessWidget {
  const _DiscoverVignette({required this.deck, required this.bundle});

  final List<ProductSummary?> deck;
  final List<ProductSummary?> bundle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final front = deck.first;
    final total = bundle.fold<num>(0, (sum, p) => sum + (p?.price ?? 15000));
    // a round budget just above the bundle, so the bar reads "fits"
    final budget = ((total * 1.08) / 5000).ceil() * 5000;

    Widget card(ProductSummary? p, double angle, double dx, double opacity) => Transform.translate(
      offset: Offset(dx, 0),
      child: Transform.rotate(
        angle: angle,
        child: Opacity(
          opacity: opacity,
          child: _Card(
            padding: const EdgeInsets.all(8),
            radius: 22,
            child: _Well(product: p, size: 168, radius: 16),
          ),
        ),
      ),
    );

    Widget action(IconData icon, Color ink, {bool filled = false}) => Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: filled ? colors.primary : colors.surface,
        shape: BoxShape.circle,
        boxShadow: colors.shadowMd,
      ),
      child: Icon(icon, size: 22, color: filled ? colors.onPrimary : ink),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 214,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              card(deck.elementAtOrNull(2), 0.10, 34, 0.55),
              card(deck.elementAtOrNull(1), -0.08, -30, 0.8),
              card(front, 0, 0, 1),
              Positioned(
                bottom: 0,
                left: 60,
                child: action(Icons.close_rounded, colors.muted),
              ),
              Positioned(
                bottom: 0,
                right: 60,
                child: action(Icons.favorite_rounded, colors.sale, filled: true),
              ),
            ],
          ),
        ),
        AppSpacing.gapMd,
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  for (var i = 0; i < bundle.length; i++)
                    Align(
                      widthFactor: 0.72,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                        child: ClipOval(child: _Well(product: bundle[i], size: 34, radius: 17)),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Bundle · ${bundle.length} items', style: t.labelLarge!.copyWith(fontWeight: FontWeight.w800)),
                        Text(
                          '${Formatters.price(total)} of ${Formatters.price(budget)}',
                          style: t.bodySmall!.copyWith(color: colors.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.check_circle_rounded, color: colors.success, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: AppRadii.pillAll,
                child: LinearProgressIndicator(value: (total / budget).clamp(0, 1).toDouble(), minHeight: 6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Page dots: the current page is a blue pill.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Page ${index + 1} of $count',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: context.motion(AppDurations.normal),
              curve: AppCurves.standard,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? colors.primary : colors.borderStrong,
                borderRadius: AppRadii.pillAll,
              ),
            ),
        ],
      ),
    );
  }
}
