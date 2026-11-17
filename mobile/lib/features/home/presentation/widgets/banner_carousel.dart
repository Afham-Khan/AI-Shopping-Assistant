import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../catalog/data/models/catalog_models.dart';
import '../../../catalog/presentation/widgets/accent.dart';
import '../../../catalog/presentation/widgets/open_target.dart';

/// Auto-advancing promo banners with a page indicator. Pauses while the
/// user drags or hovers; shows 2 banners side by side on wide screens.
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key, required this.banners});

  final List<HomeBanner> banners;

  /// Height for the current text scale (text never overflows).
  static double heightOf(BuildContext context) =>
      96 + MediaQuery.textScalerOf(context).scale(context.isWide ? 108 : 84);

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  PageController? _controller;
  double _fraction = 1;
  Timer? _timer;
  int _page = 0;
  bool _paused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fraction = context.screenWidth >= 1000 ? 0.5 : 1.0;
    if (_controller == null || fraction != _fraction) {
      _fraction = fraction;
      _controller?.dispose();
      _controller = PageController(viewportFraction: fraction, initialPage: _page);
    }
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.banners.length < 2 || context.reduceMotion) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      final c = _controller;
      if (_paused || c == null || !c.hasClients || !mounted) return;
      final visible = _fraction < 1 ? 2 : 1;
      final last = math.max(0, widget.banners.length - visible);
      final next = _page >= last ? 0 : _page + 1;
      c.animateToPage(next, duration: AppDurations.slow * 1.5, curve: AppCurves.emphasized);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final banners = widget.banners;
    final colors = context.colors;
    final visible = _fraction < 1 ? 2 : 1;
    final dots = math.max(1, banners.length - visible + 1);

    return MouseRegion(
      onEnter: (_) => _paused = true,
      onExit: (_) => _paused = false,
      child: Column(
        children: [
          SizedBox(
            height: BannerCarousel.heightOf(context),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification && n.dragDetails != null) _paused = true;
                if (n is ScrollEndNotification) _paused = false;
                return false;
              },
              child: PageView.builder(
                controller: _controller,
                padEnds: false,
                itemCount: banners.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => Padding(
                  padding: EdgeInsets.only(right: _fraction < 1 ? AppSpacing.sm : 0),
                  child: _BannerCard(banner: banners[i]),
                ),
              ),
            ),
          ),
          if (dots > 1) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              label: 'Banner ${math.min(_page, dots - 1) + 1} of $dots',
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < dots; i++)
                    AnimatedContainer(
                      duration: context.motion(AppDurations.normal),
                      curve: AppCurves.standard,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == math.min(_page, dots - 1) ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == math.min(_page, dots - 1) ? colors.primary : colors.border,
                        borderRadius: AppRadii.pillAll,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BannerCard extends StatefulWidget {
  const _BannerCard({required this.banner});

  final HomeBanner banner;

  @override
  State<_BannerCard> createState() => _BannerCardState();
}

class _BannerCardState extends State<_BannerCard> {
  bool _hovered = false;

  void _open() {
    final target = widget.banner.target;
    if (target == null) return;
    final isScope = target.type == 'department' || target.type == 'category';
    openTarget(context, type: target.type, value: target.value, title: isScope ? widget.banner.title : null);
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.banner;
    final t = context.textTheme;
    final colors = context.colors;
    final tint = AccentTint.of(context, bannerAccent(context, b.theme));
    final isAi = b.target?.type == 'assistant';
    final bigText = MediaQuery.textScalerOf(context).scale(1) > 1.5;
    final imageWidth = context.isWide ? 200.0 : 128.0;

    return Semantics(
      button: true,
      label: '${b.title}. ${b.subtitle ?? ''}',
      excludeSemantics: true,
      child: Material(
        color: tint.background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.sheetAll,
          side: BorderSide(color: _hovered ? tint.foreground.withValues(alpha: 0.4) : Colors.transparent),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          onHover: (v) => setState(() => _hovered = v),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.sm, AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isAi) ...[
                        const AiBadge(label: 'AI', solid: false),
                        const SizedBox(height: AppSpacing.xs),
                      ],
                      Text(
                        b.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: (context.isWide ? t.headlineSmall : t.titleLarge)!.copyWith(color: colors.text),
                      ),
                      if (b.subtitle != null && !bigText) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          b.subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall!.copyWith(color: colors.muted),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              b.ctaLabel ?? 'Shop now',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelLarge!.copyWith(color: tint.foreground),
                            ),
                          ),
                          const SizedBox(width: 4),
                          AnimatedSlide(
                            offset: _hovered && !context.reduceMotion ? const Offset(0.25, 0) : Offset.zero,
                            duration: AppDurations.fast,
                            child: Icon(Icons.arrow_forward_rounded, size: 16, color: tint.foreground),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: imageWidth,
                height: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: AppNetworkImage(b.imageUrl, fit: BoxFit.contain, backgroundColor: Colors.transparent),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder with the carousel's footprint.
class BannerCarouselSkeleton extends StatelessWidget {
  const BannerCarouselSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Skeleton(height: BannerCarousel.heightOf(context), borderRadius: AppRadii.sheetAll),
        const SizedBox(height: AppSpacing.sm + 6),
      ],
    );
  }
}
