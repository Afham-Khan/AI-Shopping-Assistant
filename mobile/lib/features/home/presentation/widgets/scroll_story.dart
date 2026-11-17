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
/// turns, lifts and settles as the card travels through the screen
/// ("scroll storytelling"). Motion is applied in a [Flow] delegate that
/// repaints on scroll — the card is never rebuilt while scrolling.
class ScrollStory extends StatelessWidget {
  const ScrollStory({super.key, required this.product, this.eyebrow = 'Pick of the week'});

  final ProductSummary product;
  final String eyebrow;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final scrollable = Scrollable.maybeOf(context);
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
                    delegate: _StoryFlowDelegate(scrollable: still ? null : scrollable, itemContext: context),
                    clipBehavior: Clip.none,
                    children: [disc, image],
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

class _StoryFlowDelegate extends FlowDelegate {
  _StoryFlowDelegate({required this.scrollable, required this.itemContext}) : super(repaint: scrollable?.position);

  final ScrollableState? scrollable;
  final BuildContext itemContext;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) => constraints.loosen();

  @override
  void paintChildren(FlowPaintingContext context) {
    final p = scrollable == null ? 0.5 : viewportProgress(itemContext, scrollable!);
    final c = p - 0.5; // -0.5 entering … 0.5 leaving
    final swell = math.sin(p * math.pi); // 0 → 1 → 0
    final box = context.size;

    // disc: grows in and drifts slower than the page (depth)
    final discSize = context.getChildSize(0)!;
    final discScale = 0.78 + 0.3 * swell;
    final discCentre = Offset(box.width / 2, box.height / 2 + 10 - c * 26);
    context.paintChild(
      0,
      transform: _around(discCentre, discSize, scale: discScale, rotation: 0),
      opacity: (0.4 + swell).clamp(0.0, 1.0),
    );

    // product: turns from -16° to +9°, lifts, then settles
    final imgSize = context.getChildSize(1)!;
    final rotation = -0.28 + 0.44 * p;
    final scale = 0.82 + 0.24 * swell;
    final centre = Offset(box.width / 2 - c * 34, box.height / 2 - c * 70 - 6);
    context.paintChild(1, transform: _around(centre, imgSize, scale: scale, rotation: rotation));
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
  bool shouldRepaint(_StoryFlowDelegate old) => old.scrollable != scrollable || old.itemContext != itemContext;
}

/// Paint-time parallax for an image inside a horizontal rail tile: the
/// image drifts against the rail's scroll and, gently, the page's.
class ParallaxImage extends StatelessWidget {
  const ParallaxImage({super.key, required this.child, this.travel = 12});

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
        delegate: _ParallaxDelegate(rail: rail, page: page, itemContext: context, travel: travel),
        children: [child],
      ),
    );
  }
}

class _ParallaxDelegate extends FlowDelegate {
  _ParallaxDelegate({required this.rail, required this.page, required this.itemContext, required this.travel})
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
      transform: Matrix4.translationValues(-travel - x * travel, -travel - y * travel * 0.6, 0),
    );
  }

  @override
  bool shouldRepaint(_ParallaxDelegate old) => old.rail != rail || old.page != page || old.travel != travel;
}
