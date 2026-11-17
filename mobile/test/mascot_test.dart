import 'dart:math' as math;

import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/core/widgets/widgets.dart';
import 'package:cartwise/features/assistant/presentation/widgets/chat_input_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Start time of an event and its steps, from a scheduler's virtual clock.
class PlanEvent {
  PlanEvent(this.start, this.end, this.steps);
  final Duration start;
  final Duration end;
  final List<MascotStep> steps;
  MascotBeat get beat => steps.first.beat;
}

List<PlanEvent> plan(MascotScheduler s, Duration horizon) {
  final events = <PlanEvent>[];
  while (s.clock < horizon) {
    final before = s.clock;
    final steps = s.next();
    events.add(PlanEvent(before + steps.first.delay, s.clock, steps));
  }
  return events;
}

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.light,
  builder: (context, home) =>
      MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: home!),
  home: Scaffold(body: Center(child: child)),
);

AiMascotPainter painterOf(WidgetTester tester) {
  final paint = tester.widgetList<CustomPaint>(find.descendant(of: find.byType(AiMascot), matching: find.byType(CustomPaint)))
      .firstWhere((p) => p.painter is AiMascotPainter);
  return paint.painter! as AiMascotPainter;
}

/// Steps the fake clock in 40 ms frames and records every pose.
Future<List<MascotPose>> sample(WidgetTester tester, Duration length, {Duration step = const Duration(milliseconds: 40)}) async {
  final poses = <MascotPose>[];
  for (var t = Duration.zero; t < length; t += step) {
    await tester.pump(step);
    final live = painterOf(tester).livePose;
    poses.add(live?.call() ?? MascotPose.rest);
  }
  return poses;
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  group('MascotScheduler (the idle loop plan)', () {
    test('blinks every 3-6 s, glances every 5-9 s, smiles every 10-15 s (plus the time other beats take)', () {
      for (final seed in [1, 7, 42, 2024]) {
        final events = plan(MascotScheduler(random: math.Random(seed)), const Duration(minutes: 10));
        Iterable<Duration> gaps(bool Function(PlanEvent) of) {
          final starts = events.where(of).map((e) => e.start).toList();
          return [for (var i = 1; i < starts.length; i++) starts[i] - starts[i - 1]];
        }

        final blinks = gaps((e) => e.beat == MascotBeat.blink || e.beat == MascotBeat.doubleBlink);
        final glances = gaps((e) => e.beat == MascotBeat.gaze);
        final smiles = gaps((e) => e.beat == MascotBeat.joy);
        expect(blinks.length, greaterThan(60));
        expect(blinks.every((g) => g >= const Duration(seconds: 3)), isTrue, reason: 'seed $seed blink min');
        expect(blinks.every((g) => g <= const Duration(seconds: 11)), isTrue, reason: 'seed $seed blink max');
        expect(glances.every((g) => g >= const Duration(seconds: 5) && g <= const Duration(seconds: 14)), isTrue, reason: 'seed $seed glance');
        expect(smiles.every((g) => g >= const Duration(seconds: 10) && g <= const Duration(seconds: 19)), isTrue, reason: 'seed $seed smile');
        expect(smiles.length, greaterThan(25));
      }
    });

    test('the first blink comes early and events never overlap or stack without a gap', () {
      final events = plan(MascotScheduler(random: math.Random(3)), const Duration(minutes: 5));
      expect(events.first.start, lessThanOrEqualTo(const Duration(seconds: 4)));
      for (var i = 1; i < events.length; i++) {
        expect(events[i].start - events[i - 1].end, greaterThanOrEqualTo(MascotScheduler.minGap));
      }
    });

    test('glances go left, right and up (never the same way twice in a row) within gaze range', () {
      final events = plan(MascotScheduler(random: math.Random(11)), const Duration(minutes: 10));
      final targets = [for (final e in events) if (e.beat == MascotBeat.gaze) e.steps.first.gaze];
      expect(targets.any((g) => g.dx < -0.7 && g.dy == 0), isTrue, reason: 'left');
      expect(targets.any((g) => g.dx > 0.7 && g.dy == 0), isTrue, reason: 'right');
      expect(targets.any((g) => g.dx == 0 && g.dy < -0.7), isTrue, reason: 'up');
      expect(targets.every((g) => g.dx.abs() <= 1 && g.dy.abs() <= 1 && g.dy <= 0), isTrue);
      for (var i = 1; i < targets.length; i++) {
        final a = targets[i - 1], b = targets[i];
        expect((a.dx.sign, a.dy.sign) == (b.dx.sign, b.dy.sign), isFalse);
      }
      // each glance goes out and comes back to centre
      final glance = events.firstWhere((e) => e.beat == MascotBeat.gaze).steps;
      expect(glance, hasLength(2));
      expect(glance.last.gaze, Offset.zero);
    });

    test('a smile eases up, holds and eases down', () {
      final smile = plan(MascotScheduler(random: math.Random(5)), const Duration(minutes: 1)).firstWhere((e) => e.beat == MascotBeat.joy).steps;
      expect(smile.map((s) => s.joy), [1, 0]);
      expect(smile.last.delay, greaterThanOrEqualTo(const Duration(milliseconds: 800)));
    });

    test('some blinks are double blinks', () {
      final events = plan(MascotScheduler(random: math.Random(9)), const Duration(minutes: 10));
      expect(events.where((e) => e.beat == MascotBeat.doubleBlink), isNotEmpty);
      expect(events.where((e) => e.beat == MascotBeat.blink).length, greaterThan(events.where((e) => e.beat == MascotBeat.doubleBlink).length));
    });

    test('glances: false / smiles: false leave only blinks (the listening mascot)', () {
      final events = plan(MascotScheduler(random: math.Random(2), glances: false, smiles: false), const Duration(minutes: 3));
      expect(events.every((e) => e.beat == MascotBeat.blink || e.beat == MascotBeat.doubleBlink), isTrue);
    });
  });

  group('MascotChoreography', () {
    const rest = MascotPose(gaze: Offset(0.3, 1), joy: 0.2);

    test('no step is the resting face', () {
      expect(MascotChoreography.poseAt(null, 0.5, rest: rest), rest);
    });

    test('a blink shuts the eyes at its middle and keeps the resting gaze', () {
      const blink = MascotStep(MascotBeat.blink, Duration(milliseconds: 160));
      expect(MascotChoreography.poseAt(blink, 0).blink, 0);
      expect(MascotChoreography.poseAt(blink, 0.5, rest: rest).blink, closeTo(1, 1e-9));
      expect(MascotChoreography.poseAt(blink, 1).blink, closeTo(0, 1e-9));
      expect(MascotChoreography.poseAt(blink, 0.5, rest: rest).gaze, rest.gaze);
      const twice = MascotStep(MascotBeat.doubleBlink, Duration(milliseconds: 420));
      expect(MascotChoreography.poseAt(twice, 0.21).blink, closeTo(1, 1e-9));
      expect(MascotChoreography.poseAt(twice, 0.46).blink, 0);
      expect(MascotChoreography.poseAt(twice, 0.71).blink, closeTo(1, 1e-9));
    });

    test('gaze and joy glide from the resting face to the target and settle there', () {
      const look = MascotStep(MascotBeat.gaze, Duration(milliseconds: 200), gaze: Offset(-1, 0));
      expect(MascotChoreography.poseAt(look, 0, rest: rest).gaze, rest.gaze);
      expect(MascotChoreography.poseAt(look, 1, rest: rest).gaze, const Offset(-1, 0));
      final mid = MascotChoreography.poseAt(look, 0.5, rest: rest).gaze;
      expect(mid.dx, inExclusiveRange(-1, 0.3));
      expect(MascotChoreography.settle(look, rest).gaze, const Offset(-1, 0));
      expect(MascotChoreography.settle(look, rest).joy, rest.joy);

      const smile = MascotStep(MascotBeat.joy, Duration(milliseconds: 240), joy: 1);
      expect(MascotChoreography.poseAt(smile, 1, rest: rest).joy, 1);
      expect(MascotChoreography.settle(smile, rest).joy, 1);
      expect(MascotChoreography.settle(smile, rest).gaze, rest.gaze);
    });

    test('thinking sweeps the eyes both ways, hop and blink settle to nothing', () {
      const think = MascotStep(MascotBeat.think, Duration(milliseconds: 1400));
      final xs = [for (var i = 0; i <= 20; i++) MascotChoreography.poseAt(think, i / 20).gaze.dx];
      expect(xs.reduce(math.min), lessThan(-0.9));
      expect(xs.reduce(math.max), greaterThan(0.9));
      expect(MascotChoreography.poseAt(think, 0.25).phase, 0.25);
      const blink = MascotStep(MascotBeat.blink, Duration(milliseconds: 160));
      expect(MascotChoreography.settle(blink, rest), rest);
    });
  });

  group('AiMascot widget', () {
    testWidgets('an idle mascot really blinks, glances and smiles over time', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 56)));
      final poses = await sample(tester, const Duration(seconds: 24));
      expect(poses.any((p) => p.blink > 0.8), isTrue, reason: 'blinked');
      expect(poses.any((p) => p.gaze.dx.abs() > 0.5 || p.gaze.dy < -0.5), isTrue, reason: 'glanced away');
      expect(poses.any((p) => p.joy > 0.9), isTrue, reason: 'smiled');
      // and it rests between beats: most frames are the plain face
      expect(poses.where((p) => p == MascotPose.rest).length, greaterThan(poses.length ~/ 3));
      await tester.pumpWidget(const SizedBox()); // disposes: the pending timer must be cancelled
    });

    testWidgets('animates down to 20 px (the nav bar) with the simplified drawing, but not below', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 30)));
      expect(painterOf(tester).livePose, isNotNull);
      expect(painterOf(tester).simplified, isFalse);
      await tester.pumpWidget(host(const AiMascot(size: 24)));
      expect(painterOf(tester).livePose, isNotNull);
      expect(painterOf(tester).simplified, isTrue);
      await tester.pumpWidget(host(const AiMascot(size: 20)));
      expect(painterOf(tester).livePose, isNotNull);
      await tester.pumpWidget(host(const AiMascot(size: 16)));
      expect(painterOf(tester).livePose, isNull);
      expect(painterOf(tester).animation, isNull);
      await tester.pumpWidget(host(const AiMascot(size: 30, animate: false)));
      expect(painterOf(tester).livePose, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('reduced motion is a static face (no controller, no timers)', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 56), reduceMotion: true));
      expect(painterOf(tester).livePose, isNull);
      expect(painterOf(tester).animation, isNull);
      await tester.pump(const Duration(seconds: 30));
      expect(tester.binding.hasScheduledFrame, isFalse);
      // a listening mascot still faces the composer — that is a pose, not motion
      await tester.pumpWidget(host(const AiMascot(size: 28, mood: AiMood.listening), reduceMotion: true));
      expect(painterOf(tester).gaze, AiMascot.listeningGaze);
      expect(painterOf(tester).livePose, isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('it paints only itself: a RepaintBoundary around a painter that listens to its controller', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 56)));
      expect(find.descendant(of: find.byType(AiMascot), matching: find.byType(RepaintBoundary)), findsWidgets);
      expect(painterOf(tester).animation, isA<AnimationController>());
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('nothing runs while it is off-screen (TickerMode off); it wakes up when shown again', (tester) async {
      Widget tree(bool on) => host(TickerMode(enabled: on, child: const AiMascot(size: 56)));
      await tester.pumpWidget(tree(false));
      final hidden = await sample(tester, const Duration(seconds: 30));
      expect(hidden.every((p) => p == MascotPose.rest), isTrue);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await tester.pumpWidget(tree(true));
      final shown = await sample(tester, const Duration(seconds: 8));
      expect(shown.any((p) => p.blink > 0.5 || p.gaze != Offset.zero), isTrue);

      // and it stops again
      await tester.pumpWidget(tree(false));
      await tester.pump(const Duration(seconds: 1));
      final stopped = await sample(tester, const Duration(seconds: 20));
      expect(stopped.every((p) => p == MascotPose.rest), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pauses when the app goes to the background', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 56)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      final away = await sample(tester, const Duration(seconds: 20));
      expect(away.every((p) => p == MascotPose.rest), isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final back = await sample(tester, const Duration(seconds: 8));
      expect(back.any((p) => p.blink > 0.5 || p.gaze != Offset.zero), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('thinking sweeps the eyes side to side', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 28, mood: AiMood.thinking)));
      final poses = await sample(tester, const Duration(milliseconds: 1500));
      expect(poses.any((p) => p.gaze.dx < -0.8), isTrue);
      expect(poses.any((p) => p.gaze.dx > 0.8), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('happy hops once and then rests (no endless loop)', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 40, mood: AiMood.happy)));
      final poses = await sample(tester, const Duration(seconds: 2));
      expect(poses.first.phase, greaterThan(0));
      expect(poses.last, MascotPose.rest);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a listening mascot glides its eyes to the composer, follows gaze changes and still blinks', (tester) async {
      await tester.pumpWidget(host(const AiMascot(size: 28, mood: AiMood.listening)));
      await sample(tester, const Duration(milliseconds: 600)); // glide takes 280 ms
      expect(painterOf(tester).livePose!().gaze, AiMascot.listeningGaze);

      await tester.pumpWidget(host(const AiMascot(size: 28, mood: AiMood.listening, gaze: Offset(-0.5, 0.9))));
      await sample(tester, const Duration(milliseconds: 600));
      expect(painterOf(tester).livePose!().gaze, const Offset(-0.5, 0.9));

      final poses = await sample(tester, const Duration(seconds: 8));
      expect(poses.any((p) => p.blink > 0.5), isTrue);
      // blinking while looking at the input; no wandering glances or smiles
      expect(poses.every((p) => p.gaze == const Offset(-0.5, 0.9) && p.joy == 0), isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('mood changes restart the loop without errors, in every size and colour setup', (tester) async {
      for (final mood in AiMood.values) {
        for (final size in [16.0, 20.0, 28.0, 56.0]) {
          await tester.pumpWidget(host(AiMascot(size: size, mood: mood, outline: size == 20)));
          await tester.pump(const Duration(milliseconds: 600));
        }
      }
      await tester.pumpWidget(host(const AiMascot(size: 30, color: Colors.white, eyeColor: Colors.blue, mood: AiMood.happy)));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the chat composer tells the header how far the user has typed (null when idle)', (tester) async {
      final seen = <double?>[];
      await tester.pumpWidget(host(Align(
        alignment: Alignment.bottomCenter,
        child: ChatInputBar(onSend: (_) {}, sending: false, onTyping: seen.add),
      )));
      expect(seen, isEmpty);

      await tester.enterText(find.byType(TextField), 'a' * 20);
      await tester.pump();
      expect(seen.last, 0.5);

      // growing past a short message tops out at 1; same value is not reported twice
      await tester.enterText(find.byType(TextField), 'a' * 200);
      await tester.pump();
      expect(seen.last, 1.0);
      final count = seen.length;
      await tester.enterText(find.byType(TextField), 'b' * 210);
      await tester.pump();
      expect(seen.length, count);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(seen.last, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AiSparkleIcon stays a static icon', (tester) async {
      await tester.pumpWidget(host(const AiSparkleIcon(size: 24)));
      expect(painterOf(tester).livePose, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
