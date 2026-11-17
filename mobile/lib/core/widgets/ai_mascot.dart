import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../utils/extensions.dart';

/// How the assistant mascot looks right now.
enum AiMood {
  /// Resting; blinks now and then.
  idle,

  /// Working on an answer: the eyes glance side to side and the bag bobs.
  thinking,

  /// Pleased (an answer landed, a goal was met): the eyes become arcs.
  happy,
}

/// The assistant's mascot: a smiling, rounded **shopping bag that is also a
/// speech bubble** — the bag body carries a bubble tail at its lower left,
/// a wide handle loops over the top — with two dot eyes and a small smile.
/// Flat brand blue, no gradient, no glow. Drawn in code.
///
/// ```dart
/// AiMascot(size: 56)                              // idle, blinks
/// AiMascot(size: 40, mood: AiMood.thinking)       // while the answer streams
/// AiMascot(size: 40, mood: AiMood.happy)
/// AiMascot(size: 24, color: Colors.white)         // on a blue fill (eyes turn blue)
/// ```
/// Below 28 px it draws a simplified, heavier version (bigger eyes, thicker
/// handle) and doesn't animate, so it stays legible at 16–20 px. Under
/// reduced motion it never animates. `AiSparkleIcon` (the old name) renders
/// this mascot too.
class AiMascot extends StatefulWidget {
  const AiMascot({
    super.key,
    this.size = 40,
    this.mood = AiMood.idle,
    this.color,
    this.eyeColor,
    this.outline = false,
    this.animate = true,
    this.semanticLabel,
  });

  final double size;
  final AiMood mood;

  /// Bag color (defaults to the AI accent, i.e. brand blue).
  final Color? color;

  /// Eye color; defaults to white on a dark bag and brand blue on a light one.
  final Color? eyeColor;

  /// Outlined bag (unselected / quiet states) instead of a filled one.
  final bool outline;

  /// Blink / glance / bob. Ignored below 28 px and under reduced motion.
  final bool animate;
  final String? semanticLabel;

  @override
  State<AiMascot> createState() => _AiMascotState();
}

class _AiMascotState extends State<AiMascot> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  bool _shouldAnimate(BuildContext context) => widget.animate && widget.size >= 28 && !context.reduceMotion;

  Duration get _period => switch (widget.mood) {
    AiMood.idle => const Duration(milliseconds: 4200),
    AiMood.thinking => const Duration(milliseconds: 1400),
    AiMood.happy => const Duration(milliseconds: 2400),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(AiMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood || old.animate != widget.animate || old.size != widget.size) _sync();
  }

  void _sync() {
    if (_shouldAnimate(context)) {
      final c = _controller ??= AnimationController(vsync: this);
      c.duration = _period;
      c
        ..reset()
        ..repeat();
    } else {
      _controller?.stop();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bag = widget.color ?? context.colors.ai;
    final eyes = widget.eyeColor ??
        (widget.outline ? bag : (bag.computeLuminance() > 0.5 ? AppColors.blue : Colors.white));
    final controller = _controller;
    final animating = controller != null && controller.isAnimating;

    Widget paint(double t) => CustomPaint(
      size: Size.square(widget.size),
      painter: AiMascotPainter(
        bag: bag,
        eyes: eyes,
        mood: widget.mood,
        t: t,
        outline: widget.outline,
        simplified: widget.size < 28,
      ),
    );

    final mark = SizedBox.square(
      dimension: widget.size,
      child: animating ? AnimatedBuilder(animation: controller, builder: (_, _) => paint(controller.value)) : paint(0),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: mark);
    return Semantics(label: label, image: true, child: mark);
  }
}

/// Paints the mascot into a square. [t] is the 0..1 phase of the mood's loop.
class AiMascotPainter extends CustomPainter {
  const AiMascotPainter({
    required this.bag,
    required this.eyes,
    this.mood = AiMood.idle,
    this.t = 0,
    this.outline = false,
    this.simplified = false,
  });

  final Color bag;
  final Color eyes;
  final AiMood mood;
  final double t;
  final bool outline;
  final bool simplified;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.scale(s / 100);

    // thinking bobs gently; happy hops once per loop
    final bob = switch (mood) {
      AiMood.thinking => -2.5 * math.sin(t * 2 * math.pi).abs(),
      AiMood.happy => t < 0.18 ? -4 * math.sin(t / 0.18 * math.pi) : 0.0,
      AiMood.idle => 0.0,
    };
    canvas.translate(0, bob);

    final stroke = simplified ? 8.0 : 6.0;
    final fill = Paint()
      ..color = bag
      ..isAntiAlias = true;
    final line = Paint()
      ..color = bag
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // body: a soft trapezoid bag, a little wider at the base. Built as a
    // polygon stroked with a fat round join so every corner is rounded.
    final core = Path()
      ..addPolygon(const [Offset(30, 45), Offset(70, 45), Offset(75, 79), Offset(25, 79)], true);
    // the speech-bubble tail at the lower left (drawn separately so the
    // two shapes never cancel each other out)
    final tail = Path()
      ..addPolygon(const [Offset(22, 76), Offset(11, 96), Offset(40, 86)], true);

    if (outline) {
      final outer = Path()
        ..addPolygon(const [Offset(22, 37), Offset(78, 37), Offset(84, 87), Offset(16, 87)], true);
      canvas.drawPath(outer, line..strokeWidth = stroke);
      canvas.drawPath(tail, fill);
    } else {
      canvas.drawPath(core, fill);
      canvas.drawPath(core, Paint()
        ..color = bag
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeJoin = StrokeJoin.round);
      canvas.drawPath(tail, fill);
      canvas.drawPath(tail, Paint()
        ..color = bag
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round);
    }

    // handle: a wide, low loop — a bag handle, not a padlock shackle
    final handle = Path()
      ..moveTo(29, 38)
      ..lineTo(29, 34)
      ..arcToPoint(const Offset(71, 34), radius: const Radius.elliptical(21, 14))
      ..lineTo(71, 38);
    canvas.drawPath(handle, line..strokeWidth = simplified ? stroke : 5.2);

    _paintEyes(canvas);
    canvas.restore();
  }

  void _paintEyes(Canvas canvas) {
    final eyePaint = Paint()
      ..color = eyes
      ..isAntiAlias = true;
    final ink = Paint()
      ..color = eyes
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final gap = simplified ? 14.0 : 11.0;
    final r = simplified ? 7.0 : 5.2;
    final cy = simplified ? 60.0 : 57.0;

    if (mood == AiMood.happy) {
      // eyes become arcs ( ^ ^ )
      for (final x in [50 - gap, 50 + gap]) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x, cy + r * 0.7), radius: r * 1.1),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          ink..strokeWidth = simplified ? 5.5 : 4.2,
        );
      }
    } else {
      var dx = 0.0;
      var squash = 1.0;
      if (mood == AiMood.thinking) {
        // glance left … right
        dx = 4 * math.sin(t * 2 * math.pi);
      } else {
        // blink once per loop, briefly
        const start = 0.90;
        const length = 0.06;
        if (t > start && t < start + length) {
          final k = (t - start) / length;
          squash = 0.12 + 0.88 * (1 - math.sin(k * math.pi));
        }
      }
      for (final x in [50 - gap, 50 + gap]) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x + dx, cy), width: r * 2, height: r * 2 * squash),
          eyePaint,
        );
      }
    }

    // the smile (left out at icon size, where two eyes read better alone)
    if (simplified) return;
    ink.strokeWidth = 3.6;
    switch (mood) {
      case AiMood.thinking:
        // a small sideways "hmm"
        canvas.drawLine(const Offset(46, 69.5), const Offset(54, 68), ink);
      case AiMood.happy:
        canvas.drawArc(Rect.fromCircle(center: const Offset(50, 64), radius: 8.5), math.pi * 0.18, math.pi * 0.64, false, ink);
      case AiMood.idle:
        canvas.drawArc(Rect.fromCircle(center: const Offset(50, 64.5), radius: 6.5), math.pi * 0.22, math.pi * 0.56, false, ink);
    }
  }

  @override
  bool shouldRepaint(AiMascotPainter old) =>
      old.bag != bag ||
      old.eyes != eyes ||
      old.mood != mood ||
      old.t != t ||
      old.outline != outline ||
      old.simplified != simplified;
}
