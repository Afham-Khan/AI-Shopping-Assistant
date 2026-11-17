import 'dart:math' as math;

import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/network/api_client.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/core/widgets/widgets.dart';
import 'package:cartwise/features/ai/data/ai_repository.dart';
import 'package:cartwise/features/ai/data/models/ai_models.dart';
import 'package:cartwise/features/home/data/room_repository.dart';
import 'package:cartwise/features/home/presentation/room/room_layout.dart';
import 'package:cartwise/features/home/presentation/room/room_section.dart';
import 'package:cartwise/features/home/presentation/widgets/scroll_depth.dart';
import 'package:cartwise/features/home/presentation/widgets/scroll_story.dart';
import 'package:cartwise/features/home/providers/room_providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _story = ProductSummary(id: 1, title: 'Desk lamp', slug: 'lamp', price: 4999);

ProductSummary _p(int id, String title, double price, String cat) => ProductSummary(
  id: id,
  title: title,
  slug: 'p-$id',
  price: price,
  category: NamedRef(id: id, name: cat, slug: cat),
);

Map<String, dynamic> _item(String role, int id, String title, double price, String cat) => {
  'role': role,
  'product': {
    'id': id,
    'title': title,
    'slug': 'p-$id',
    'price': price,
    'category': {'id': id, 'name': cat, 'slug': cat},
  },
};

class _FakeAi extends AiRepository {
  _FakeAi() : super(ApiClient(Dio()));

  @override
  Future<List<BundleTemplate>> bundleTemplates() async => const [
    BundleTemplate(id: 'gaming_setup', goal: 'gaming setup', label: 'Gaming setup', suggestedBudget: 375000),
  ];

  @override
  Future<BundleResult> bundle({required String goal, required double budget}) async => BundleResult.fromJson({
    'title': 'Gaming setup',
    'budget': budget,
    'items': [
      _item('Gaming laptop', 81, 'Lenovo Yoga 920', 307999, 'laptops'),
      _item('Headphones', 107, 'Beats Flex Wireless Earphones', 13999, 'mobile-accessories'),
      _item('Speaker', 103, 'Apple HomePod Mini', 27999, 'mobile-accessories'),
    ],
    'skippedRoles': ['Gaming chair'],
    'explanation': 'I split your budget across 3 pieces (a knapsack optimization over 7 candidates).',
    'savingsTips': ['The speaker is optional.'],
    'budgetAdvice': {'missingRequired': <String>[], 'suggestedBudget': 375000},
  });
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  group('ScrollStory', () {
    Future<ScrollController> pumpStory(WidgetTester tester, {bool reduceMotion = false, bool settleIntro = true}) async {
      final prefs = await _prefs();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
                child: Scaffold(
                  body: CustomScrollView(
                    controller: controller,
                    slivers: const [
                      SliverToBoxAdapter(child: SizedBox(height: 1000)),
                      SliverToBoxAdapter(child: ScrollStory(product: _story)),
                      SliverToBoxAdapter(child: SizedBox(height: 1500)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      if (settleIntro) await tester.pump(const Duration(milliseconds: 1200));
      return controller;
    }

    ({double angle, Offset offset}) readPose(WidgetTester tester) {
      final flow = tester.renderObject<RenderBox>(find.byKey(const ValueKey('scroll-story-flow')));
      final image = tester.renderObject<RenderBox>(
        find.descendant(of: find.byKey(const ValueKey('scroll-story-flow')), matching: find.byType(AppNetworkImage)),
      );
      final tl = image.localToGlobal(Offset.zero);
      final tr = image.localToGlobal(Offset(image.size.width, 0));
      final centre = image.localToGlobal(image.size.center(Offset.zero));
      return (
        angle: math.atan2(tr.dy - tl.dy, tr.dx - tl.dx) * 180 / math.pi,
        offset: centre - flow.localToGlobal(flow.size.center(Offset.zero)),
      );
    }

    /// Scrolls so the story sits at viewport progress [p], then reads the
    /// cut-out's angle (degrees) and its centre relative to the moving stage.
    Future<({double angle, Offset offset})> poseAt(WidgetTester tester, ScrollController c, double p) async {
      c.jumpTo(600); // bring the story into the built range to measure it
      await tester.pump();
      final story = tester.renderObject<RenderBox>(find.byType(ScrollStory));
      const view = 844.0;
      final extent = story.size.height;
      // progress = (view - top) / (view + extent)  →  top for the wanted p
      final top = view - p * (view + extent);
      c.jumpTo(1000 - top);
      await tester.pump();
      return readPose(tester);
    }

    testWidgets('the cut-out spins in, settles, then tips and drops as the page scrolls', (tester) async {
      final c = await pumpStory(tester);

      final entering = await poseAt(tester, c, 0.1);
      final approaching = await poseAt(tester, c, 0.35);
      final centred = await poseAt(tester, c, 0.5);
      final passing = await poseAt(tester, c, 0.65);
      final leaving = await poseAt(tester, c, 0.95);

      // no plateau: the pose keeps changing through the middle of the screen
      expect(approaching.angle, lessThan(-10));
      expect(passing.angle, greaterThan(8));

      expect(entering.angle, lessThan(-25), reason: 'arrives turned');
      expect(entering.offset.dx, greaterThan(40), reason: 'arrives from the right edge');
      expect(centred.angle.abs(), lessThan(2), reason: 'upright while centred');
      expect(centred.offset.distance, lessThan(12), reason: 'resting on its disc');
      expect(leaving.angle, greaterThan(20), reason: 'tips the other way on the way out');
      expect(leaving.offset.dy, greaterThan(80), reason: 'drops toward the next section');
      expect(tester.takeException(), isNull);
    });

    testWidgets('on open the cut-out lands: from off-card, turned, then upright', (tester) async {
      final c = await pumpStory(tester, settleIntro: false);
      c.jumpTo(1000 - 300); // story near the top half, scroll pose almost settled
      await tester.pump();
      final start = readPose(tester);
      await tester.pump(const Duration(milliseconds: 1200));
      final landed = readPose(tester);
      expect(start.offset.dx - landed.offset.dx, greaterThan(60), reason: 'starts off to the right');
      expect(landed.angle - start.angle, greaterThan(15), reason: 'turns upright as it lands');
    });

    testWidgets('reduced motion keeps the settled pose while scrolling', (tester) async {
      final c = await pumpStory(tester, reduceMotion: true);

      for (final p in [0.1, 0.5, 0.95]) {
        final pose = await poseAt(tester, c, p);
        expect(pose.angle.abs(), lessThan(0.5), reason: 'p=$p');
        expect(pose.offset.distance, lessThan(12), reason: 'p=$p');
      }
    });

    testWidgets('rail images drift against the rail scroll', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final rail = ScrollController();
      addTearDown(rail.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: ListView.builder(
                controller: rail,
                scrollDirection: Axis.horizontal,
                itemCount: 10,
                itemBuilder: (_, i) => SizedBox(
                  key: ValueKey('tile-$i'),
                  width: 150,
                  child: ParallaxImage(child: ColoredBox(key: ValueKey('img-$i'), color: Colors.red)),
                ),
              ),
            ),
          ),
        ),
      );
      double drift() {
        final tile = tester.getTopLeft(find.byKey(const ValueKey('tile-1')));
        return tester.getTopLeft(find.byKey(const ValueKey('img-1'))).dx - tile.dx;
      }

      final before = drift();
      rail.jumpTo(200);
      await tester.pump();
      final after = drift();
      expect((after - before).abs(), greaterThan(6), reason: 'the image moves inside its tile');
    });

    test('poses are continuous and settle in the middle', () {
      final mid = StoryPose.at(0.5, 180);
      expect(mid.rotation, 0);
      expect(mid.dx, 0);
      var last = StoryPose.at(0, 180);
      for (var i = 1; i <= 100; i++) {
        final next = StoryPose.at(i / 100, 180);
        expect((next.rotation - last.rotation).abs(), lessThan(0.12), reason: 'no jumps at ${i / 100}');
        last = next;
      }
    });
  });

  group('Scroll depth', () {
    Future<ScrollController> pumpList(WidgetTester tester, List<Widget> children) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ScrollController();
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ListView(controller: c, children: children)),
        ),
      );
      return c;
    }

    testWidgets('layers with different shifts drift apart as the page scrolls', (tester) async {
      final c = await pumpList(tester, [
        const SizedBox(height: 700),
        SizedBox(
          height: 300,
          child: Stack(
            children: [
              Positioned.fill(child: ScrollDepth(shift: 18, child: Container(key: const Key('back'), color: Colors.blue))),
              Positioned.fill(child: Container(key: const Key('front'), color: Colors.transparent)),
              Positioned.fill(child: ScrollDepth(shift: -12, child: Container(key: const Key('near')))),
            ],
          ),
        ),
        const SizedBox(height: 1500),
      ]);
      double rel(String key) => tester.getTopLeft(find.byKey(Key(key))).dy - tester.getTopLeft(find.byKey(const Key('front'))).dy;
      await tester.pump();
      final backBefore = rel('back');
      final nearBefore = rel('near');
      c.jumpTo(600);
      await tester.pump();
      final backAfter = rel('back');
      final nearAfter = rel('near');
      expect(backAfter - backBefore, greaterThan(8), reason: 'the far layer lags behind the page');
      expect(nearAfter - nearBefore, lessThan(-5), reason: 'the near layer runs ahead');
    });

    testWidgets('the header lags, shrinks and fades over the first scroll', (tester) async {
      final c = await pumpList(tester, [
        const ScrollCollapse(child: SizedBox(key: Key('header'), height: 120)),
        const SizedBox(height: 2000),
      ]);
      c.jumpTo(80);
      await tester.pump();
      // -80 from the scroll, +14 lag at half way (28 px over 160 px)
      expect(tester.getTopLeft(find.byKey(const Key('header'))).dy, closeTo(-66, 1));
      final box = tester.renderObject<RenderScrollCollapse>(
        find.ancestor(of: find.byKey(const Key('header')), matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ScrollCollapseBox')),
      );
      expect(box.amount, closeTo(0.5, 1e-6));
    });
  });

  group('Build my setup in the room', () {
    final zones = RoomLayout.merge([
      RoomZoneData(
        id: 'desk',
        label: 'The desk',
        department: 'electronics',
        categories: const ['laptops', 'mobile-accessories'],
        featured: [_p(9, 'Featured monitor', 50000, 'laptops')],
      ),
      const RoomZoneData(id: 'shelf', label: 'The shelf', department: 'home-living', categories: ['home-decoration']),
    ]);

    test('gaming pieces map to sensible zones', () {
      expect(RoomLayout.zoneForItem(_p(1, 'Lenovo Yoga 920', 1, 'laptops'), 'Gaming laptop', zones), 'desk');
      expect(RoomLayout.zoneForItem(_p(2, 'Beats Flex', 1, 'mobile-accessories'), 'Headphones', zones), 'desk');
      expect(RoomLayout.zoneForItem(_p(3, 'HomePod Mini', 1, 'mobile-accessories'), 'Speaker', zones), 'shelf');
      expect(RoomLayout.zoneForItem(_p(4, 'Racer chair', 1, 'furniture'), 'Gaming chair', zones), isNull,
          reason: 'a chair stands on the floor');
      expect(RoomLayout.zoneForItem(_p(5, 'iPad Air', 1, 'laptops'), 'Laptop or tablet', zones), 'desk',
          reason: '"tablet" is not a table');
    });

    test('pinned pieces are larger than the featured cut-out and stay in the scene', () {
      final slot = RoomLayout.spec('desk')!.slot;
      for (var n = 1; n <= 3; n++) {
        final rects = RoomLayout.pinRects('desk', n);
        expect(rects, hasLength(n));
        for (final r in rects) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(RoomLayout.size.width));
          expect(r.bottom, closeTo(slot.bottom, 1e-6));
        }
      }
      expect(RoomLayout.pinRects('desk', 1).single.width, greaterThan(slot.width * 1.3));
    });

    Future<ProviderContainer> pumpRoom(WidgetTester tester, {bool reduceMotion = false}) async {
      final prefs = await _prefs();
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          aiRepositoryProvider.overrideWithValue(_FakeAi()),
          roomZonesProvider.overrideWith((ref) async => zones),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
                child: const Scaffold(
                  body: SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(children: [SizedBox(height: 700), RoomSection(), SizedBox(height: 900)]),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return container;
    }

    Future<void> build(WidgetTester tester) async {
      await tester.scrollUntilVisible(find.text('Build my setup'), 200);
      expect(find.text('Let Zel furnish this room for your budget'), findsOneWidget);
      await tester.tap(find.text('Build my setup'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('Furnish a room with AI'), findsOneWidget);
      expect(find.text('Rs 375,000'), findsOneWidget, reason: 'the goal starts at the suggested budget');
      await tester.tap(find.text('Furnish the room'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('the room itself changes: header, pinned pieces with chips, explanation, clear', (tester) async {
      final container = await pumpRoom(tester);
      await build(tester);
      // sheet closing + the stage scrolling into view
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final setup = container.read(roomSetupProvider)!;
      expect({for (final i in setup.items) i.role: i.zoneId}, {
        'Gaming laptop': 'desk',
        'Headphones': 'desk',
        'Speaker': 'shelf',
      });
      expect(find.text('Your Gaming setup'), findsOneWidget);
      expect(find.text('Shop the room'), findsNothing);
      expect(find.text('Featured monitor'), findsNothing, reason: "the furnished desk drops its featured cut-out");

      // mid-flight the first piece is still travelling
      final layer = find.byKey(const ValueKey('room-pinned-layer'));
      expect(layer, findsOneWidget);
      Offset firstPiece() => tester
          .renderObject<RenderBox>(find.descendant(of: layer, matching: find.byType(AppNetworkImage)).first)
          .localToGlobal(Offset.zero);
      await tester.pump(const Duration(milliseconds: 150));
      final early = firstPiece();
      await tester.pump(const Duration(seconds: 2));
      final landed = firstPiece();
      expect((landed - early).distance, greaterThan(20), reason: 'the piece flew into place');

      // the stage is on screen
      final stage = tester.getRect(layer);
      expect(stage.top, greaterThanOrEqualTo(0));
      expect(stage.bottom, lessThanOrEqualTo(844));

      // chips: role + price
      expect(find.text('Gaming laptop'), findsOneWidget);
      expect(find.text('Rs 307,999'), findsOneWidget);
      expect(find.text('Speaker'), findsOneWidget);

      // "How Zel chose these"
      await tester.ensureVisible(find.text('How Zel chose these'));
      await tester.tap(find.text('How Zel chose these'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('knapsack', findRichText: true), findsWidgets);
      expect(find.textContaining('Budget used: Rs 349,997 of Rs 375,000'), findsOneWidget);
      expect(find.textContaining('Left out to stay within budget: Gaming chair'), findsOneWidget);

      // Clear room
      await tester.ensureVisible(find.text('Clear room'));
      await tester.tap(find.text('Clear room'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(container.read(roomSetupProvider), isNull);
      expect(find.text('Shop the room'), findsOneWidget);
      expect(find.text('Your Gaming setup'), findsNothing);
      expect(find.byKey(const ValueKey('room-pinned-layer')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('the room has three depth layers that separate while scrolling', (tester) async {
      await pumpRoom(tester);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
      double rel(String key) {
        final front = tester.getTopLeft(find.byKey(const ValueKey('room-depth-front')));
        final layer = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(RepaintBoundary)).first;
        return tester.getTopLeft(layer).dy - front.dy;
      }

      scroll.position.jumpTo(300);
      await tester.pump();
      final back1 = rel('room-depth-back');
      final cut1 = rel('room-depth-cutouts');
      scroll.position.jumpTo(900);
      await tester.pump();
      final back2 = rel('room-depth-back');
      final cut2 = rel('room-depth-cutouts');
      expect(back2 - back1, greaterThan(6), reason: 'the wall lags behind');
      expect(cut2 - cut1, lessThan(-4), reason: 'the cut-outs lead');
      await tester.pump(const Duration(seconds: 10));
    });

    testWidgets('reduced motion places everything at once', (tester) async {
      await pumpRoom(tester, reduceMotion: true);
      await build(tester);
      await tester.pump();
      await tester.pump();
      expect(find.text('Your Gaming setup'), findsOneWidget);
      expect(find.text('Gaming laptop'), findsOneWidget);
      expect(find.text('Rs 27,999'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
