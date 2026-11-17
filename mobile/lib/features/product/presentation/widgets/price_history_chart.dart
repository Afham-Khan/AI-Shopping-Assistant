import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../data/models/price_history.dart';

/// Step-line chart of recorded prices (a price holds until the next change).
/// Drag or tap to read a value. Needs at least two points; the card decides
/// when that's true.
class PriceHistoryChart extends StatefulWidget {
  const PriceHistoryChart({super.key, required this.points, this.height = 128, this.semanticLabel});

  /// Oldest first, already extended to today (see `PriceHistory.series`).
  final List<PricePoint> points;
  final double height;
  final String? semanticLabel;

  @override
  State<PriceHistoryChart> createState() => _PriceHistoryChartState();
}

class _PriceHistoryChartState extends State<PriceHistoryChart> {
  /// 0..1 across the plot while the user scrubs; null at rest.
  double? _scrub;

  PricePoint get _first => widget.points.first;
  PricePoint get _last => widget.points.last;

  /// The recorded price in force at [t] (0..1 of the time span).
  PricePoint _pointAt(double t) {
    final span = _last.at.difference(_first.at).inMilliseconds;
    final target = _first.at.add(Duration(milliseconds: (span * t).round()));
    var found = widget.points.first;
    for (final p in widget.points) {
      if (!p.at.isAfter(target)) found = p;
    }
    return found;
  }

  void _update(double dx, double width) {
    if (width <= 0) return;
    setState(() => _scrub = (dx / width).clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final points = widget.points;
    final scrubbed = _scrub == null ? null : _pointAt(_scrub!);

    final header = scrubbed == null
        ? 'Last ${math.max(1, _last.at.difference(_first.at).inDays)} days'
        : '${Formatters.date(scrubbed.at)} · ${Formatters.price(scrubbed.price)}';

    return Semantics(
      image: true,
      label: widget.semanticLabel ?? 'Price history chart',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            header,
            style: t.labelMedium!.copyWith(color: scrubbed == null ? colors.muted : colors.text, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) => MouseRegion(
              onHover: (e) => _update(e.localPosition.dx, c.maxWidth),
              onExit: (_) => setState(() => _scrub = null),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _update(d.localPosition.dx, c.maxWidth),
                onTapUp: (_) => setState(() => _scrub = null),
                onTapCancel: () => setState(() => _scrub = null),
                onHorizontalDragStart: (d) => _update(d.localPosition.dx, c.maxWidth),
                onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, c.maxWidth),
                onHorizontalDragEnd: (_) => setState(() => _scrub = null),
                onHorizontalDragCancel: () => setState(() => _scrub = null),
                child: CustomPaint(
                  size: Size(c.maxWidth, widget.height),
                  painter: _ChartPainter(
                    points: points,
                    line: colors.primary,
                    area: colors.primary.withValues(alpha: 0.10),
                    grid: colors.border,
                    low: colors.success,
                    surface: colors.surface,
                    scrub: _scrub,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  Formatters.date(_first.at),
                  style: t.labelSmall!.copyWith(color: colors.faint),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text('Today', style: t.labelSmall!.copyWith(color: colors.faint)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.points,
    required this.line,
    required this.area,
    required this.grid,
    required this.low,
    required this.surface,
    required this.scrub,
  });

  final List<PricePoint> points;
  final Color line;
  final Color area;
  final Color grid;
  final Color low;
  final Color surface;
  final double? scrub;

  static const _padTop = 6.0;
  static const _padBottom = 4.0;
  static const _padSide = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final plotW = size.width - _padSide * 2;
    final plotH = size.height - _padTop - _padBottom;
    final startMs = points.first.at.millisecondsSinceEpoch.toDouble();
    final spanMs = math.max(1.0, points.last.at.millisecondsSinceEpoch - startMs);
    var minP = points.map((p) => p.price).reduce(math.min);
    var maxP = points.map((p) => p.price).reduce(math.max);
    if (maxP - minP < 1) maxP = minP + 1;
    final pad = (maxP - minP) * 0.12;
    minP -= pad;
    maxP += pad;

    double x(PricePoint p) => _padSide + (p.at.millisecondsSinceEpoch - startMs) / spanMs * plotW;
    double y(double price) => _padTop + (1 - (price - minP) / (maxP - minP)) * plotH;

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final gy = _padTop + plotH * i / 2;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    final path = Path()..moveTo(x(points.first), y(points.first.price));
    for (var i = 1; i < points.length; i++) {
      path
        ..lineTo(x(points[i]), y(points[i - 1].price))
        ..lineTo(x(points[i]), y(points[i].price));
    }
    final fill = Path.from(path)
      ..lineTo(x(points.last), size.height - _padBottom)
      ..lineTo(x(points.first), size.height - _padBottom)
      ..close();
    canvas.drawPath(fill, Paint()..color = area);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    void dot(Offset c, Color color, double r) {
      canvas.drawCircle(c, r + 2, Paint()..color = surface);
      canvas.drawCircle(c, r, Paint()..color = color);
    }

    // the cheapest recorded price, unless it is today's
    final lowest = points.reduce((a, b) => b.price < a.price ? b : a);
    if (lowest.price < points.last.price) dot(Offset(x(lowest), y(lowest.price)), low, 3.5);
    dot(Offset(x(points.last), y(points.last.price)), line, 4);

    final s = scrub;
    if (s != null) {
      final sx = _padSide + s * plotW;
      final target = startMs + s * spanMs;
      var current = points.first;
      for (final p in points) {
        if (p.at.millisecondsSinceEpoch <= target) current = p;
      }
      canvas.drawLine(
        Offset(sx, _padTop),
        Offset(sx, size.height - _padBottom),
        Paint()
          ..color = line.withValues(alpha: 0.45)
          ..strokeWidth = 1.2,
      );
      dot(Offset(sx, y(current.price)), line, 4.5);
    }
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.points != points || old.scrub != scrub || old.line != line || old.grid != grid || old.surface != surface;
}
