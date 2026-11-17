import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../discover/presentation/shop_actions.dart';

/// How far a widget has travelled through the viewport of its nearest
/// [Scrollable] along [axis]: 0 as it enters at the far edge, 0.5 centred,
/// 1 as it leaves at the near edge. Pure geometry, used by paint-time
/// delegates (no rebuilds while scrolling).
double viewportProgress(BuildContext itemContext, ScrollableState scrollable, {Axis axis = Axis.vertical}) {
  final item = itemContext.findRenderObject();
  final viewport = scrollable.context.findRenderObject();
  if (item is! RenderBox || viewport is! RenderBox || !item.attached || !item.hasSize || !viewport.hasSize) {
    return 0.5;
  }
  final offset = item.localToGlobal(Offset.zero, ancestor: viewport);
  final vertical = axis == Axis.vertical;
  final start = vertical ? offset.dy : offset.dx;
  final extent = vertical ? item.size.height : item.size.width;
  final view = vertical ? viewport.size.height : viewport.size.width;
  return ((view - start) / (view + extent)).clamp(0.0, 1.0);
}

/// The signature scroll moment on Home: a featured product cut-out that
/// lands on its disc when Home opens (from off-card, turned -30 degrees,
/// scale 0.8 -> 1.1 -> 1.0), then follows the scroll: it spins in from the
/// edge as the card enters, stands upright while centred, then tips over and
/// drops toward the next section as the card leaves ("scroll storytelling").
///
/// Performance: one [Flow] whose delegate repaints from the page's
/// [ScrollPosition] (and the one-shot intro); the three moving parts are
/// [RepaintBoundary]s, so a frame only re-composites three transforms (no
/// rebuilds, no opacity or blur layers). Reduced motion: no intro, and the
/// cut-out rests in its settled pose.
class ScrollStory extends StatefulWidget {
  const ScrollStory({super.key, required this.product, this.eyebrow = 'Pick of the week'});

  final ProductSummary product;
  final String eyebrow;

  @override
  State<ScrollStory> createState() => _ScrollStoryState();
}

class _ScrollStoryState extends State<ScrollStory> with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _introStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_introStarted) return;
    _introStarted = true;
    if (context.reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final eyebrow = widget.eyebrow;
    final colors = context.colors;
    final t = context.textTheme;
    final scrollable = Scrollable.maybeOf(context, axis: Axis.vertical);
    final still = context.reduceMotion || scrollable == null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // the product takes ~half the card and breaks out of its top edge
        final stage = (constraints.maxWidth * 0.46).clamp(130.0, 230.0);
        final image = RepaintBoundary(
          child: AppNetworkImage(
            product.thumbnail,
            width: stage * 0.92,
            height: stage * 0.92,
            fit: BoxFit.contain,
            backgroundColor: Colors.transparent,
            semanticLabel: product.title,
          ),
        );
        final disc = RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(color: colors.primarySoft, shape: BoxShape.circle),
            child: SizedBox(width: stage * 0.86, height: stage * 0.86),
          ),
        );
        // contact shadow: a flat ellipse, no blur
        final shadow = RepaintBoundary(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.shadow.withValues(alpha: context.isDark ? 0.4 : 0.14),
              borderRadius: const BorderRadius.all(Radius.elliptical(100, 20)),
            ),
            child: SizedBox(width: stage * 0.6, height: 12),
          ),
        );

        return Semantics(
          container: true,
          label: '$eyebrow: ${product.title}',
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // the card + copy (sizes the whole section, grows with text scale)
              Container(
                margin: const EdgeInsets.only(top: 40),
                constraints: BoxConstraints(minHeight: stage + 20),
                padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xl, stage - 6, AppSpacing.lg),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: AppRadii.sheetAll,
                  boxShadow: colors.shadowSm,
                  border: Border.all(color: context.isDark ? colors.border : colors.border.withValues(alpha: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      eyebrow.toUpperCase(),
                      style: t.labelSmall!.copyWith(color: colors.primary, letterSpacing: 1.1, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(product.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.titleLarge),
                    if (product.brand != null) ...[
                      const SizedBox(height: 2),
                      Text(product.brand!, maxLines: 1, style: t.bodySmall!.copyWith(color: colors.muted)),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    if (product.rating > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: RatingStars(product.rating, count: product.ratingCount),
                      ),
                    PriceText(product.price, compareAt: product.compareAtPrice, singleLine: true),
                    const SizedBox(height: AppSpacing.sm),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: AppButton(
                        label: 'Take a look',
                        size: AppButtonSize.small,
                        trailingIcon: Icons.arrow_forward_rounded,
                        semanticLabel: 'Open ${product.title}, ${Formatters.price(product.price)}',
                        onPressed: () => openProduct(context, product),
                      ),
                    ),
                  ],
                ),
              ),
              // the moving product
              Positioned(
                right: 0,
                top: 0,
                width: stage,
                height: stage + 20,
                child: IgnorePointer(
                  child: Flow(
                    key: const ValueKey('scroll-story-flow'),
                    delegate: StoryFlowDelegate(
                      scrollable: still ? null : scrollable,
                      itemContext: context,
                      stage: stage,
                      intro: _intro,
                    ),
                    clipBehavior: Clip.none,
                    children: [shadow, disc, image],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The cut-out's pose at scroll progress `p` (0 entering at the bottom of the
/// screen, 1 leaving at the top). A pure function of `p` and the stage size:
/// cheap to evaluate every frame and easy to test.
@immutable
class StoryPose {
  const StoryPose({
    required this.dx,
    required this.dy,
    required this.rotation,
    required this.scale,
    required this.discScale,
    required this.discDy,
    required this.lift,
  });

  /// Upright, full size, on its disc (also the reduced-motion pose).
  static const settled = StoryPose(dx: 0, dy: 0, rotation: 0, scale: 1.08, discScale: 1.05, discDy: 0, lift: 0);

  factory StoryPose.at(double p, double stage) {
    // no resting plateau: something visibly changes on every scroll step,
    // and the pose passes through "settled" exactly when the card is centred
    final away = (1 - p * 2).clamp(0.0, 1.0); // 1 entering ... 0 centred
    final leave = (p * 2 - 1).clamp(0.0, 1.0); // 0 centred ... 1 leaving
    return StoryPose(
      // in from the right edge; out toward the left and down into the next section
      dx: away * away * stage * 0.9 - leave * math.sqrt(leave) * stage * 0.5,
      dy: away * 80 + leave * leave * 190,
      // spins in from -52 degrees, upright when centred, tips the other way (+43)
      rotation: -away * 0.9 + leave * 0.75,
      // 0.8 entering, 1.08 centred, 0.95 leaving
      scale: 1.08 - 0.28 * away * math.sqrt(away) - 0.13 * leave,
      // the disc swells under it and lags behind (depth)
      discScale: 1.05 - 0.7 * away - 0.3 * leave,
      discDy: away * 24 + leave * 60,
      lift: math.max(away, leave),
    );
  }

  /// Adds the landing that plays once when Home opens: [t] 0 -> 1. The piece
  /// starts off-card to the right, turned -30 degrees, at 0.8x, overshoots to
  /// 1.1x as it lands and settles at 1.0x.
  StoryPose withIntro(double t, double stage) {
    if (t >= 1) return this;
    final e = Curves.easeOutCubic.transform(t);
    final away = 1 - e;
    final pop = t < 0.55
        ? 0.8 + 0.3 * Curves.easeOut.transform(t / 0.55)
        : 1.1 - 0.1 * Curves.easeInOut.transform((t - 0.55) / 0.45);
    return StoryPose(
      dx: dx + away * stage * 1.1,
      dy: dy - away * 36,
      rotation: rotation - away * 0.52,
      scale: scale * pop,
      discScale: discScale * (0.6 + 0.4 * e),
      discDy: discDy,
      lift: math.max(lift, away),
    );
  }

  final double dx;
  final double dy;
  final double rotation;
  final double scale;
  final double discScale;
  final double discDy;

  /// 0 resting on the disc … 1 in the air (the contact shadow shrinks).
  final double lift;

}

/// Paints [ScrollStory]'s shadow, disc and cut-out from the scroll position.
class StoryFlowDelegate extends FlowDelegate {
  StoryFlowDelegate({required this.scrollable, required this.itemContext, required this.stage, this.intro})
    : super(repaint: Listenable.merge([?scrollable?.position, ?intro]));

  final ScrollableState? scrollable;
  final BuildContext itemContext;
  final double stage;

  /// The one-shot landing (0 -> 1); null or complete = no intro offset.
  final Animation<double>? intro;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) => constraints.loosen();

  @override
  void paintChildren(FlowPaintingContext context) {
    final s = scrollable;
    final base = s == null ? StoryPose.settled : StoryPose.at(viewportProgress(itemContext, s), stage);
    final pose = intro == null ? base : base.withIntro(intro!.value, stage);
    final box = context.size;
    final rest = Offset(box.width / 2, box.height / 2 - 4);

    // 0: contact shadow under the resting spot, smaller while the product is airborne
    final shadowSize = context.getChildSize(0)!;
    context.paintChild(
      0,
      transform: _around(
        Offset(box.width / 2, box.height - 10 + pose.discDy * 0.6),
        shadowSize,
        // grows as the product comes down onto the disc, shrinks as it lifts
        scale: (1.2 - 0.85 * pose.lift.clamp(0.0, 1.0)) * pose.discScale.clamp(0.4, 1.1),
        rotation: 0,
      ),
    );

    // 1: disc, moving slower than the product
    final discSize = context.getChildSize(1)!;
    context.paintChild(
      1,
      transform: _around(rest + Offset(0, 10 + pose.discDy), discSize, scale: pose.discScale, rotation: 0),
    );

    // 2: the product
    final imgSize = context.getChildSize(2)!;
    context.paintChild(
      2,
      transform: _around(rest + Offset(pose.dx, pose.dy), imgSize, scale: pose.scale, rotation: pose.rotation),
    );
  }

  /// Places a child of [size] centred on [centre], scaled and rotated about its centre.
  static Matrix4 _around(Offset centre, Size size, {required double scale, required double rotation}) {
    final cos = math.cos(rotation) * scale;
    final sin = math.sin(rotation) * scale;
    final hx = size.width / 2;
    final hy = size.height / 2;
    // column-major [R·S | t] where t moves the child's centre to `centre`
    return Matrix4(
      cos, sin, 0, 0, //
      -sin, cos, 0, 0, //
      0, 0, 1, 0, //
      centre.dx - (cos * hx - sin * hy), centre.dy - (sin * hx + cos * hy), 0, 1,
    );
  }

  @override
  bool shouldRepaint(StoryFlowDelegate old) =>
      old.scrollable != scrollable || old.itemContext != itemContext || old.stage != stage || old.intro != intro;
}

/// Paint-time parallax for an image inside a horizontal rail tile: the image
/// drifts against the rail's scroll and, a little less, the page's. The child
/// is a [RepaintBoundary], so a scroll frame only moves a layer.
class ParallaxImage extends StatelessWidget {
  const ParallaxImage({super.key, required this.child, this.travel = 18});

  final Widget child;

  /// Max drift in logical pixels each way.
  final double travel;

  @override
  Widget build(BuildContext context) {
    if (context.reduceMotion) return child;
    final rail = Scrollable.maybeOf(context, axis: Axis.horizontal);
    final page = Scrollable.maybeOf(context, axis: Axis.vertical);
    if (rail == null && page == null) return child;
    return ClipRect(
      child: Flow(
        delegate: ParallaxDelegate(rail: rail, page: page, itemContext: context, travel: travel),
        children: [RepaintBoundary(child: child)],
      ),
    );
  }
}

/// Moves [ParallaxImage]'s child against the rail and page scroll.
class ParallaxDelegate extends FlowDelegate {
  ParallaxDelegate({required this.rail, required this.page, required this.itemContext, required this.travel})
    : super(repaint: Listenable.merge([?rail?.position, ?page?.position]));

  final ScrollableState? rail;
  final ScrollableState? page;
  final BuildContext itemContext;
  final double travel;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      BoxConstraints.tight(Size(constraints.maxWidth + travel * 2, constraints.maxHeight + travel * 2));

  @override
  void paintChildren(FlowPaintingContext context) {
    final x = rail == null ? 0.0 : (viewportProgress(itemContext, rail!, axis: Axis.horizontal) - 0.5) * 2;
    final y = page == null ? 0.0 : (viewportProgress(itemContext, page!) - 0.5) * 2;
    context.paintChild(
      0,
      transform: Matrix4.translationValues(-travel - x * travel, -travel - y * travel * 0.85, 0),
    );
  }

  @override
  bool shouldRepaint(ParallaxDelegate old) => old.rail != rail || old.page != page || old.travel != travel;
}
