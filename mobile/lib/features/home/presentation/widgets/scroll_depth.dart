import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/utils/extensions.dart';

/// Moves [child] vertically against the page scroll for depth: [shift] px at
/// the edges of the viewport (positive = moves slower than the page, so it
/// reads as further away; negative = faster, nearer), 0 when centred.
///
/// Paint-only: a repaint-boundary proxy that listens to the page's
/// [ScrollPosition] and re-composites one transform per scroll frame (no
/// rebuild, the child's picture is reused). Static under reduced motion.
class ScrollDepth extends StatelessWidget {
  const ScrollDepth({super.key, required this.shift, required this.child});

  final double shift;
  final Widget child;

  @override
  Widget build(BuildContext context) => _ScrollDepthBox(shift: shift, child: RepaintBoundary(child: child));
}

class _ScrollDepthBox extends SingleChildRenderObjectWidget {
  const _ScrollDepthBox({required this.shift, required super.child});

  final double shift;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderScrollDepth(scrollable: _page(context), shift: shift);

  @override
  void updateRenderObject(BuildContext context, RenderScrollDepth renderObject) => renderObject
    ..scrollable = _page(context)
    ..shift = shift;

  ScrollableState? _page(BuildContext context) =>
      context.reduceMotion ? null : Scrollable.maybeOf(context, axis: Axis.vertical);
}

/// The top of Home (greeting + Ask bar) gently compresses as the page
/// scrolls: over the first [distance] px it lags behind the scroll by up to
/// [lag] px, shrinks 4 % and fades to 35 %. Opacity is applied only below 1
/// (no layer at rest). Static under reduced motion.
class ScrollCollapse extends StatelessWidget {
  const ScrollCollapse({super.key, required this.child, this.distance = 160, this.lag = 28});

  final Widget child;
  final double distance;
  final double lag;

  @override
  Widget build(BuildContext context) =>
      _ScrollCollapseBox(distance: distance, lag: lag, child: RepaintBoundary(child: child));
}

class _ScrollCollapseBox extends SingleChildRenderObjectWidget {
  const _ScrollCollapseBox({required this.distance, required this.lag, required super.child});

  final double distance;
  final double lag;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderScrollCollapse(scrollable: _page(context), distance: distance, lag: lag);

  @override
  void updateRenderObject(BuildContext context, RenderScrollCollapse renderObject) => renderObject
    ..scrollable = _page(context)
    ..distance = distance
    ..lag = lag;

  ScrollableState? _page(BuildContext context) =>
      context.reduceMotion ? null : Scrollable.maybeOf(context, axis: Axis.vertical);
}

/// How far [item] has travelled through [viewport] vertically: 0 entering at
/// the bottom, 0.5 centred, 1 leaving at the top.
double verticalProgress(RenderBox item, RenderBox viewport) {
  if (!item.attached || !item.hasSize || !viewport.hasSize) return 0.5;
  final top = item.localToGlobal(Offset.zero, ancestor: viewport).dy;
  final view = viewport.size.height;
  return ((view - top) / (view + item.size.height)).clamp(0.0, 1.0);
}

/// Shared plumbing: a repaint boundary that repaints (only itself) when the
/// scroll position moves, painting its child with [pose].
abstract class _RenderScrollPaint extends RenderProxyBox {
  _RenderScrollPaint(this._scrollable);

  ScrollableState? _scrollable;
  ScrollableState? get scrollable => _scrollable;
  set scrollable(ScrollableState? value) {
    if (value == _scrollable) return;
    if (attached) _scrollable?.position.removeListener(markNeedsPaint);
    _scrollable = value;
    if (attached) _scrollable?.position.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  final _transform = LayerHandle<TransformLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  /// Transform and opacity for the current scroll position.
  (Matrix4, double) pose();

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrollable?.position.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _scrollable?.position.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _transform.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  Matrix4 _last = Matrix4.identity();

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scrollable == null) {
      _transform.layer = null;
      _opacity.layer = null;
      _last = Matrix4.identity();
      context.paintChild(child, offset);
      return;
    }
    final (m, o) = pose();
    _last = m;
    void paintTransformed(PaintingContext ctx, Offset off) {
      _transform.layer = ctx.pushTransform(
        needsCompositing,
        off,
        m,
        (c, o2) => c.paintChild(child, o2),
        oldLayer: _transform.layer,
      );
    }

    if (o >= 0.999) {
      _opacity.layer = null;
      paintTransformed(context, offset);
    } else {
      _opacity.layer = context.pushOpacity(
        offset,
        Color.getAlphaFromOpacity(o.clamp(0.0, 1.0)),
        paintTransformed,
        oldLayer: _opacity.layer,
      );
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_last);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintTransform(
    transform: _last,
    position: position,
    hitTest: (result, position) => super.hitTestChildren(result, position: position),
  );
}

class RenderScrollDepth extends _RenderScrollPaint {
  RenderScrollDepth({required ScrollableState? scrollable, required this._shift}) : super(scrollable);

  double _shift;
  double get shift => _shift;
  set shift(double v) {
    if (v == _shift) return;
    _shift = v;
    markNeedsPaint();
  }

  @override
  (Matrix4, double) pose() {
    final viewport = scrollable?.context.findRenderObject();
    final p = viewport is RenderBox ? verticalProgress(this, viewport) : 0.5;
    return (Matrix4.translationValues(0, _shift * (p - 0.5) * 2, 0), 1);
  }
}

class RenderScrollCollapse extends _RenderScrollPaint {
  RenderScrollCollapse({required ScrollableState? scrollable, required this._distance, required this._lag})
    : super(scrollable);

  double _distance;
  set distance(double v) {
    if (v == _distance) return;
    _distance = v;
    markNeedsPaint();
  }

  double _lag;
  set lag(double v) {
    if (v == _lag) return;
    _lag = v;
    markNeedsPaint();
  }

  /// 0 at the top of the page … 1 once scrolled `distance` px.
  double get amount {
    final pos = scrollable?.position;
    if (pos == null || !pos.hasPixels) return 0;
    return (pos.pixels / _distance).clamp(0.0, 1.0);
  }

  @override
  (Matrix4, double) pose() {
    final t = amount;
    final s = 1 - 0.04 * t;
    final m = Matrix4.translationValues(size.width * (1 - s) / 2, _lag * t, 0)..scaleByDouble(s, s, 1, 1);
    return (m, 1 - 0.65 * t);
  }
}
