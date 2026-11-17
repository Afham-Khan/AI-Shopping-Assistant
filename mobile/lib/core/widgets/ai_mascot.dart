import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../utils/extensions.dart';

/// How the assistant mascot looks right now.
enum AiMood {
  /// Resting: blinks every few seconds, now and then glances left, right or
  /// up, and every 10–15 s gives a brief happy squint.
  idle,

  /// Working on an answer: the eyes glance side to side and the bag bobs.
  thinking,

  /// Pleased (an answer landed, a goal was met): the eyes become arcs.
  happy,

  /// Paying attention to the user (typing in the composer): the eyes look
  /// toward [AiMascot.gaze] — down at the input by default — and still blink.
  listening,
}

/// The assistant's mascot: a smiling, rounded **shopping bag that is also a
/// speech bubble** — the bag body carries a bubble tail at its lower left,
/// a wide handle loops over the top — with two dot eyes and a small smile.
/// Flat brand blue, no gradient, no glow. Drawn in code.
///
/// ```dart
/// AiMascot(size: 56)                              // idle: blinks, glances, smiles
/// AiMascot(size: 40, mood: AiMood.thinking)       // while the answer streams
/// AiMascot(size: 40, mood: AiMood.happy)
/// AiMascot(size: 28, mood: AiMood.listening, gaze: Offset(0.4, 1)) // watches the composer
/// AiMascot(size: 30, color: Colors.white)         // on a blue fill (eyes turn blue)
/// ```
///
/// **Alive but cheap.** One `AnimationController` per mascot and a tiny
/// [MascotScheduler] that arms a timer for the next beat (a blink, a glance,
/// a squint). The controller only runs *during* a beat — a few frames every
/// couple of seconds — and the eyes are painted by a `CustomPainter` inside
/// its own `RepaintBoundary` that repaints only itself. Everything pauses
/// while the mascot is off-screen (`TickerMode`, e.g. another tab) or the app
/// is in the background, and reduced motion gives a static face.
///
/// From 20 px up it animates with a simplified drawing (bigger eyes, thicker
/// handle, no smile line); below 20 px it is a static icon. `AiSparkleIcon`
/// (the old name) renders this mascot as a static icon.
class AiMascot extends StatefulWidget {
  const AiMascot({
    super.key,
    this.size = 40,
    this.mood = AiMood.idle,
    this.color,
    this.eyeColor,
    this.outline = false,
    this.animate = true,
    this.gaze,
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

  /// Blink / glance / squint / bob. Ignored below 20 px and under reduced motion.
  final bool animate;

  /// Where the eyes rest: −1…1 on each axis (+x right, +y down). Defaults to
  /// centred, or to "down at the input" for [AiMood.listening]. Changing it
  /// glides the eyes there.
  final Offset? gaze;
  final String? semanticLabel;

  /// Smallest size that animates.
  static const minAnimatedSize = 20.0;

  /// Below this size the simplified drawing is used.
  static const simplifiedBelow = 28.0;

  /// Where a listening mascot looks by default: down, a little to the right
  /// (toward the composer).
  static const listeningGaze = Offset(0.3, 1);

  @override
  State<AiMascot> createState() => _AiMascotState();
}

class _AiMascotState extends State<AiMascot> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener(_onStatus);
  final _random = math.Random();
  final Queue<MascotStep> _queue = Queue();

  MascotScheduler? _scheduler;
  Timer? _timer;
  MascotStep? _step;
  MascotPose _rest = MascotPose.rest;

  bool _running = false;
  bool _tickersOn = true;
  bool _foreground = true;

  bool _allowed(BuildContext context) =>
      widget.animate && widget.size >= AiMascot.minAnimatedSize && !context.reduceMotion;

  Offset get _targetGaze => widget.gaze ?? (widget.mood == AiMood.listening ? AiMascot.listeningGaze : Offset.zero);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // off-screen (another tab, a covered route) → TickerMode is off
    _tickersOn = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didUpdateWidget(AiMascot old) {
    super.didUpdateWidget(old);
    if (old.mood != widget.mood || old.animate != widget.animate || old.size != widget.size) {
      _sync(restart: true);
    } else if (_running && old.gaze != widget.gaze && _scheduler != null) {
      _glideTo(_targetGaze);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Starts or stops the loop so it only runs while it can be seen.
  void _sync({bool restart = false}) {
    final shouldRun = _allowed(context) && _tickersOn && _foreground;
    if (shouldRun && (!_running || restart)) {
      _start();
    } else if (!shouldRun && _running) {
      _stop();
    }
  }

  void _start() {
    _stop(settle: false);
    _running = true;
    // a stale squint from a previous mood doesn't come back
    _rest = MascotPose(gaze: _rest.gaze);
    switch (widget.mood) {
      case AiMood.thinking:
        _scheduler = null;
        _step = const MascotStep(MascotBeat.think, Duration(milliseconds: 1400));
        _controller
          ..duration = _step!.duration
          ..repeat();
      case AiMood.happy:
        _scheduler = null;
        _step = const MascotStep(MascotBeat.hop, Duration(milliseconds: 440));
        _controller
          ..duration = _step!.duration
          ..forward(from: 0);
      case AiMood.idle || AiMood.listening:
        final idle = widget.mood == AiMood.idle;
        _scheduler = MascotScheduler(random: _random, glances: idle, smiles: idle);
        _glideTo(_targetGaze, ifFar: true);
    }
  }

  /// Halts everything. [settle] (a pause, not a restart) also returns the face to
  /// rest, so a mascot paused mid-glance or mid-smile doesn't stay frozen that way.
  void _stop({bool settle = true}) {
    _running = false;
    _timer?.cancel();
    _queue.clear();
    _step = null;
    _controller.stop();
    if (settle) _rest = MascotPose(gaze: _targetGaze);
  }

  /// Eases the eyes to [target] now (when they aren't there), then resumes the
  /// idle loop.
  void _glideTo(Offset target, {bool ifFar = false}) {
    _timer?.cancel();
    _queue.clear();
    if (_controller.isAnimating) _controller.stop();
    if (_step != null) {
      // freeze the eyes where they are so the glide starts from there
      final frozen = MascotChoreography.poseAt(_step, _controller.value, rest: _rest);
      _rest = MascotPose(gaze: frozen.gaze, joy: frozen.joy);
      _step = null;
    }
    final far = (target - _rest.gaze).distance > 0.05;
    if (!far && ifFar) {
      _next();
      return;
    }
    _queue.add(MascotStep(MascotBeat.gaze, const Duration(milliseconds: 280), gaze: target));
    _next();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_running) return;
    final done = _step;
    if (done != null) _rest = MascotChoreography.settle(done, _rest);
    _step = null;
    _next();
  }

  /// Arms the timer for the next step of the current (or a freshly planned)
  /// event. Between beats nothing ticks — the face just rests.
  void _next() {
    _timer?.cancel();
    if (!_running) return;
    if (_queue.isEmpty) {
      final plan = _scheduler?.next();
      if (plan == null) return;
      _queue.addAll(plan);
    }
    final step = _queue.removeFirst();
    _timer = Timer(step.delay, () => _play(step));
  }

  void _play(MascotStep step) {
    if (!mounted || !_running) return;
    _step = step;
    _controller
      ..duration = step.duration
      ..forward(from: 0);
  }

  MascotPose _poseNow() => MascotChoreography.poseAt(_step, _controller.value, rest: _rest);

  @override
  Widget build(BuildContext context) {
    final bag = widget.color ?? context.colors.ai;
    final eyes = widget.eyeColor ??
        (widget.outline ? bag : (bag.computeLuminance() > 0.5 ? AppColors.blue : Colors.white));
    final live = _allowed(context);

    final mark = SizedBox.square(
      dimension: widget.size,
      // the face repaints on its own, never with the page around it
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: AiMascotPainter(
            bag: bag,
            eyes: eyes,
            mood: widget.mood,
            outline: widget.outline,
            simplified: widget.size < AiMascot.simplifiedBelow,
            gaze: _targetGaze,
            animation: live ? _controller : null,
            livePose: live ? _poseNow : null,
          ),
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: mark);
    return Semantics(label: label, image: true, child: mark);
  }
}

// ---------------------------------------------------------------------------
// choreography: pure Dart, no widgets — what the face does and when

/// What the eyes are doing at one instant.
@immutable
class MascotPose {
  const MascotPose({this.blink = 0, this.gaze = Offset.zero, this.joy = 0, this.phase = 0});

  /// The face at rest: eyes open and centred, no squint.
  static const rest = MascotPose();

  /// 0 = open … 1 = shut.
  final double blink;

  /// −1…1 per axis; +x right, +y down.
  final Offset gaze;

  /// 0 = neutral … 1 = happy squint (eyes become arcs, bigger smile).
  final double joy;

  /// Phase 0…1 of the current looping beat (bob for thinking, hop for happy).
  final double phase;

  MascotPose copyWith({Offset? gaze, double? joy}) =>
      MascotPose(blink: blink, gaze: gaze ?? this.gaze, joy: joy ?? this.joy, phase: phase);

  @override
  bool operator ==(Object other) =>
      other is MascotPose && other.blink == blink && other.gaze == gaze && other.joy == joy && other.phase == phase;

  @override
  int get hashCode => Object.hash(blink, gaze, joy, phase);
}

/// One kind of move the face can make.
enum MascotBeat {
  /// One quick blink.
  blink,

  /// Two quick blinks in a row.
  doubleBlink,

  /// Eyes glide from where they rest to [MascotStep.gaze] and stay there.
  gaze,

  /// The squint / smile eases to [MascotStep.joy] and stays there.
  joy,

  /// Thinking loop: eyes sweep left and right (looping).
  think,

  /// One small hop (happy).
  hop,
}

/// One move: wait [delay], then play [beat] over [duration].
@immutable
class MascotStep {
  const MascotStep(this.beat, this.duration, {this.delay = Duration.zero, this.gaze = Offset.zero, this.joy = 0});

  final MascotBeat beat;
  final Duration duration;
  final Duration delay;

  /// Target for [MascotBeat.gaze].
  final Offset gaze;

  /// Target for [MascotBeat.joy].
  final double joy;

  MascotStep after(Duration delay) =>
      MascotStep(beat, duration, delay: delay, gaze: gaze, joy: joy);

  Duration get total => delay + duration;
}

/// Maps a step and its progress to a [MascotPose].
abstract final class MascotChoreography {
  static double _smooth(double t) => t * t * (3 - 2 * t);

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// The pose [t] (0…1) of the way through [step], starting from [rest].
  /// A null step is the resting face.
  static MascotPose poseAt(MascotStep? step, double t, {MascotPose rest = MascotPose.rest}) {
    if (step == null) return rest;
    final k = t.clamp(0.0, 1.0);
    switch (step.beat) {
      case MascotBeat.blink:
        return MascotPose(blink: math.sin(k * math.pi), gaze: rest.gaze, joy: rest.joy);
      case MascotBeat.doubleBlink:
        final a = k < 0.42 ? math.sin(k / 0.42 * math.pi) : 0.0;
        final b = k > 0.5 && k < 0.92 ? math.sin((k - 0.5) / 0.42 * math.pi) : 0.0;
        return MascotPose(blink: math.max(a, b), gaze: rest.gaze, joy: rest.joy);
      case MascotBeat.gaze:
        return MascotPose(gaze: Offset.lerp(rest.gaze, step.gaze, _smooth(k))!, joy: rest.joy);
      case MascotBeat.joy:
        return MascotPose(gaze: rest.gaze, joy: _lerp(rest.joy, step.joy, _smooth(k)));
      case MascotBeat.think:
        return MascotPose(gaze: Offset(math.sin(k * 2 * math.pi), 0), phase: k);
      case MascotBeat.hop:
        return MascotPose(gaze: rest.gaze, phase: k);
    }
  }

  /// The resting face after [step] finished.
  static MascotPose settle(MascotStep step, MascotPose rest) => switch (step.beat) {
    MascotBeat.gaze => rest.copyWith(gaze: step.gaze),
    MascotBeat.joy => rest.copyWith(joy: step.joy),
    _ => rest,
  };
}

/// Plans the idle loop with a virtual clock (no timers here, so it is
/// deterministic under a seeded [math.Random] and easy to test):
///
/// - a **blink** every 3–6 s (one in six is a double blink),
/// - a **glance** left, right or up every 5–9 s (the eyes go, hold, come back),
/// - a brief happy **squint / smile** every 10–15 s.
///
/// [next] returns the steps of the following event; the first step's
/// [MascotStep.delay] is the wait since the previous event ended. Between
/// events there is a minimum gap, so beats never stack up.
class MascotScheduler {
  MascotScheduler({math.Random? random, this.glances = true, this.smiles = true}) : _random = random ?? math.Random() {
    // the first beats come early so a new mascot wakes up quickly, and
    // staggered randomly so a row of mascots never blinks in unison
    _dueBlink = _between(const Duration(milliseconds: 900), const Duration(milliseconds: 2800));
    _dueGlance = _between(const Duration(milliseconds: 2500), const Duration(milliseconds: 6000));
    _dueSmile = _between(const Duration(seconds: 6), const Duration(seconds: 11));
  }

  final math.Random _random;
  final bool glances;
  final bool smiles;

  static const blinkEvery = (Duration(seconds: 3), Duration(seconds: 6));
  static const glanceEvery = (Duration(seconds: 5), Duration(seconds: 9));
  static const smileEvery = (Duration(seconds: 10), Duration(seconds: 15));

  /// Quiet time enforced between two events.
  static const minGap = Duration(milliseconds: 350);

  /// Glance targets (gaze units): left, right, up and the two up-diagonals.
  static const glanceTargets = <Offset>[
    Offset(-1, 0),
    Offset(1, 0),
    Offset(0, -1),
    Offset(-0.85, -0.8),
    Offset(0.85, -0.8),
  ];
  static const _glanceWeights = [3, 3, 2, 1, 1];

  Duration _now = Duration.zero;
  late Duration _dueBlink;
  late Duration _dueGlance;
  late Duration _dueSmile;
  int _lastGlance = -1;

  /// Virtual time at which the last planned event ends (for tests).
  Duration get clock => _now;

  Duration _between(Duration min, Duration max) =>
      Duration(milliseconds: min.inMilliseconds + _random.nextInt(max.inMilliseconds - min.inMilliseconds + 1));

  /// The next event: its steps, with the first step's `delay` measured from
  /// the end of the previous event.
  List<MascotStep> next() {
    var kind = MascotBeat.blink;
    var due = _dueBlink;
    if (glances && _dueGlance < due) {
      kind = MascotBeat.gaze;
      due = _dueGlance;
    }
    if (smiles && _dueSmile < due) {
      kind = MascotBeat.joy;
      due = _dueSmile;
    }

    final earliest = _now + minGap;
    final start = due > earliest ? due : earliest;
    final lead = start - _now;

    final List<MascotStep> steps;
    switch (kind) {
      case MascotBeat.gaze:
        steps = _glance();
        _dueGlance = start + _between(glanceEvery.$1, glanceEvery.$2);
      case MascotBeat.joy:
        steps = _smile();
        _dueSmile = start + _between(smileEvery.$1, smileEvery.$2);
      default:
        steps = _blink();
        _dueBlink = start + _between(blinkEvery.$1, blinkEvery.$2);
    }

    steps[0] = steps[0].after(lead);
    // the first step's delay already carries the lead-in
    _now += steps.fold(Duration.zero, (sum, s) => sum + s.total);
    return steps;
  }

  List<MascotStep> _blink() => _random.nextInt(6) == 0
      ? [const MascotStep(MascotBeat.doubleBlink, Duration(milliseconds: 420))]
      : [const MascotStep(MascotBeat.blink, Duration(milliseconds: 160))];

  List<MascotStep> _glance() {
    // never the same direction twice in a row
    var i = 0;
    do {
      var pick = _random.nextInt(_glanceWeights.reduce((a, b) => a + b));
      for (i = 0; i < _glanceWeights.length; i++) {
        pick -= _glanceWeights[i];
        if (pick < 0) break;
      }
    } while (i == _lastGlance);
    _lastGlance = i;
    final target = glanceTargets[i] * (0.8 + 0.2 * _random.nextDouble());
    final hold = Duration(milliseconds: 450 + _random.nextInt(650));
    return [
      MascotStep(MascotBeat.gaze, const Duration(milliseconds: 200), gaze: target),
      MascotStep(MascotBeat.gaze, const Duration(milliseconds: 260), delay: hold),
    ];
  }

  List<MascotStep> _smile() {
    final hold = Duration(milliseconds: 800 + _random.nextInt(500));
    return [
      const MascotStep(MascotBeat.joy, Duration(milliseconds: 240), joy: 1),
      MascotStep(MascotBeat.joy, const Duration(milliseconds: 380), delay: hold),
    ];
  }
}

// ---------------------------------------------------------------------------
// painting

/// Paints the mascot into a square.
///
/// A static face comes from [gaze] and [t] (the loop phase of thinking /
/// happy). An animated face passes [livePose] plus [repaint] (the mascot's
/// controller): the painter then reads the pose on every frame and repaints
/// only itself.
class AiMascotPainter extends CustomPainter {
  const AiMascotPainter({
    required this.bag,
    required this.eyes,
    this.mood = AiMood.idle,
    this.t = 0,
    this.outline = false,
    this.simplified = false,
    this.gaze = Offset.zero,
    this.livePose,
    this.animation,
  }) : super(repaint: animation);

  final Color bag;
  final Color eyes;
  final AiMood mood;

  /// Loop phase 0..1 for a static thinking / happy face.
  final double t;
  final bool outline;
  final bool simplified;

  /// Static gaze (−1…1 per axis) when there is no [livePose].
  final Offset gaze;
  final MascotPose Function()? livePose;

  /// Repaints this painter (and only it) on every tick; the mascot passes its controller.
  final Listenable? animation;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final pose = livePose?.call() ?? MascotPose(gaze: gaze, phase: t);
    canvas.save();
    canvas.scale(s / 100);

    // thinking bobs gently; happy hops once
    final bob = switch (mood) {
      AiMood.thinking => -2.5 * math.sin(pose.phase * 2 * math.pi).abs(),
      AiMood.happy => pose.phase > 0 && pose.phase < 1 ? -4 * math.sin(pose.phase * math.pi) : 0.0,
      AiMood.idle || AiMood.listening => 0.0,
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

    _paintFace(canvas, pose);
    canvas.restore();
  }

  void _paintFace(Canvas canvas, MascotPose pose) {
    final gap = simplified ? 14.0 : 11.0;
    final r = simplified ? 7.0 : 5.2;
    final cy = simplified ? 60.0 : 57.0;

    // where the eyes look (the smile drifts a little with them)
    final dx = pose.gaze.dx * (simplified ? 4.2 : 5.0);
    final dy = pose.gaze.dy * (simplified ? 3.0 : 3.4);

    // happy mood is permanent joy; otherwise the squint comes from the pose
    final joy = mood == AiMood.happy ? 1.0 : pose.joy.clamp(0.0, 1.0);
    // eyes turn from dots into arcs over the second half of the squint
    final arcAmount = ((joy - 0.45) / 0.25).clamp(0.0, 1.0);
    final dotAmount = 1 - arcAmount;

    // a blink shuts the dots; a squint also narrows them before they turn to arcs
    final openness = (1 - 0.92 * pose.blink) * (1 - 0.5 * joy);

    if (dotAmount > 0.01) {
      final dot = Paint()
        ..color = eyes.withValues(alpha: eyes.a * dotAmount)
        ..isAntiAlias = true;
      for (final x in [50 - gap, 50 + gap]) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(x + dx, cy + dy + r * 0.3 * joy), width: r * 2, height: r * 2 * openness),
          dot,
        );
      }
    }

    if (arcAmount > 0.01) {
      // eyes become arcs ( ^ ^ )
      final ink = Paint()
        ..color = eyes.withValues(alpha: eyes.a * arcAmount)
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = simplified ? 5.5 : 4.2;
      for (final x in [50 - gap, 50 + gap]) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x + dx, cy + dy * 0.5 + r * 0.7), radius: r * 1.1),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          ink,
        );
      }
    }

    // the smile (left out at icon size, where two eyes read better alone)
    if (simplified) return;
    final mouth = Paint()
      ..color = eyes
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.6;
    switch (mood) {
      case AiMood.thinking:
        // a small sideways "hmm"
        canvas.drawLine(const Offset(46, 69.5), const Offset(54, 68), mouth);
      case AiMood.happy || AiMood.idle || AiMood.listening:
        // neutral smile → broad grin as joy rises
        final radius = 6.5 + 2.0 * joy;
        final cyMouth = 64.5 - 0.5 * joy;
        final start = math.pi * (0.22 - 0.04 * joy);
        final sweep = math.pi * (0.56 + 0.08 * joy);
        canvas.drawArc(
          Rect.fromCircle(center: Offset(50 + dx * 0.3, cyMouth + dy * 0.25), radius: radius),
          start,
          sweep,
          false,
          mouth,
        );
    }
  }

  @override
  bool shouldRepaint(AiMascotPainter old) =>
      old.bag != bag ||
      old.eyes != eyes ||
      old.mood != mood ||
      old.t != t ||
      old.outline != outline ||
      old.simplified != simplified ||
      old.gaze != gaze ||
      old.livePose != livePose ||
      old.animation != animation;
}
