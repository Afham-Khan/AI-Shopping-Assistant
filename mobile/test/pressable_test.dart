import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_colors.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/core/widgets/widgets.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _box = Key('box');

Widget app(Widget child, {bool reduceMotion = false, List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: AppTheme.light,
    builder: (context, home) =>
        MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: home!),
    home: Scaffold(body: Center(child: child)),
  ),
);

Widget box() => const SizedBox(key: _box, width: 100, height: 100, child: ColoredBox(color: Color(0xFF123456)));

Offset topLeft(WidgetTester t) => t.getTopLeft(find.byKey(_box));
double width(WidgetTester t) => t.getTopRight(find.byKey(_box)).dx - t.getTopLeft(find.byKey(_box)).dx;

Future<TestGesture> mouse(WidgetTester tester) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: const Offset(2, 2));
  addTearDown(g.removePointer);
  await tester.pump();
  return g;
}

// implicit animations start on the frame after the state change, so let them finish
Future<void> settle(WidgetTester tester) => tester.pumpAndSettle();

Finder materialIn(Key key) => find.descendant(of: find.byKey(key), matching: find.byType(Material)).first;

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  group('Pressable', () {
    testWidgets('a mouse lifts the surface 2 px and puts it back when it leaves', (tester) async {
      await tester.pumpWidget(app(Pressable(child: box())));
      final rest = topLeft(tester);
      final g = await mouse(tester);

      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(topLeft(tester).dy, closeTo(rest.dy - Pressable.liftDistance, 0.01));
      expect(topLeft(tester).dx, rest.dx);

      await g.moveTo(const Offset(2, 2));
      await settle(tester);
      expect(topLeft(tester), rest);
    });

    testWidgets('the lift animates over ~180 ms rather than jumping', (tester) async {
      await tester.pumpWidget(app(Pressable(child: box())));
      final rest = topLeft(tester).dy;
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      final partway = topLeft(tester).dy;
      expect(partway, lessThan(rest));
      expect(partway, greaterThan(rest - Pressable.liftDistance));
      await settle(tester);
      expect(topLeft(tester).dy, closeTo(rest - 2, 0.01));
    });

    testWidgets('a press settles to 0.97 and springs back on release (touch or mouse)', (tester) async {
      await tester.pumpWidget(app(Pressable(child: box())));
      expect(width(tester), closeTo(100, 0.01));
      final g = await tester.startGesture(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(width(tester), closeTo(97, 0.05));
      await g.up();
      await settle(tester);
      expect(width(tester), closeTo(100, 0.05));
    });

    testWidgets('a custom press scale is honoured; hovering while pressed does not stack the lift', (tester) async {
      await tester.pumpWidget(app(Pressable(scale: 0.9, child: box())));
      final mouseGesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouseGesture.addPointer(location: tester.getCenter(find.byKey(_box)));
      addTearDown(mouseGesture.removePointer);
      await mouseGesture.down(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(width(tester), closeTo(90, 0.05));
      await mouseGesture.up();
      await settle(tester);
    });

    testWidgets('a press that turns into a scroll or drag lets go', (tester) async {
      await tester.pumpWidget(app(Pressable(child: box())));
      final g = await tester.startGesture(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(width(tester), lessThan(99));
      await g.moveBy(const Offset(0, 40));
      await settle(tester);
      expect(width(tester), closeTo(100, 0.05));
      await g.up();
    });

    Future<void> hoverOver(WidgetTester tester, Widget pressable) async {
      await tester.pumpWidget(app(pressable));
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
    }

    testWidgets('grow hovers to 1.02 by default', (tester) async {
      await hoverOver(tester, Pressable(hover: PressableHover.grow, child: box()));
      expect(width(tester), closeTo(102, 0.05));
    });

    testWidgets('grow honours a custom hoverScale', (tester) async {
      await hoverOver(tester, Pressable(hover: PressableHover.grow, hoverScale: 1.06, child: box()));
      expect(width(tester), closeTo(106, 0.05));
    });

    testWidgets('none stays put under a mouse', (tester) async {
      await tester.pumpWidget(app(Pressable(hover: PressableHover.none, child: box())));
      final rest = topLeft(tester);
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(topLeft(tester), rest);
      expect(width(tester), closeTo(100, 0.01));
    });

    testWidgets('a disabled surface neither lifts nor shrinks', (tester) async {
      await tester.pumpWidget(app(Pressable(enabled: false, child: box())));
      final rest = topLeft(tester);
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(topLeft(tester), rest);
      await g.down(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(width(tester), closeTo(100, 0.01));
      await g.up();
    });

    testWidgets('reduced motion keeps still: no lift, no press scale, no hover growth', (tester) async {
      await tester.pumpWidget(app(Pressable(child: box()), reduceMotion: true));
      final rest = topLeft(tester);
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(topLeft(tester), rest);
      await g.down(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(width(tester), closeTo(100, 0.01));
      await g.up();
    });

    testWidgets('builder gets hovered / pressed so content can swap shadows and tints', (tester) async {
      final seen = <(bool, bool)>[];
      await tester.pumpWidget(app(Pressable.builder(builder: (context, hovered, pressed) {
        seen.add((hovered, pressed));
        return box();
      })));
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await tester.pump();
      expect(seen.last, (true, false));
      await g.down(tester.getCenter(find.byKey(_box)));
      await tester.pump();
      expect(seen.last, (true, true));
      await g.up();
      await g.moveTo(const Offset(2, 2));
      await tester.pump();
      expect(seen.last, (false, false));
    });

    testWidgets('the hover region is the resting footprint, so a lifted surface never flickers at its lower edge', (tester) async {
      await tester.pumpWidget(app(Pressable(child: box())));
      final g = await mouse(tester);
      final rest = topLeft(tester).dy;
      final bottom = tester.getBottomLeft(find.byKey(_box)) + const Offset(50, -0.5);
      await g.moveTo(bottom);
      await settle(tester);
      // the box rose 2 px, so the pointer now sits 1.5 px below its drawn edge;
      // the surface must stay lifted (a hover region inside the transform would drop it)
      expect(topLeft(tester).dy, closeTo(rest - 2, 0.01));
      await tester.pump(const Duration(milliseconds: 300));
      await settle(tester);
      expect(topLeft(tester).dy, closeTo(rest - 2, 0.01));
    });
  });

  group('shared surfaces use it', () {
    testWidgets('a tappable AppCard lifts and deepens its shadow; a plain one does not', (tester) async {
      var taps = 0;
      await tester.pumpWidget(app(SizedBox(width: 200, child: AppCard(key: _box, onTap: () => taps++, child: const Text('Card')))));
      List<BoxShadow>? shadow() {
        final c = tester.widgetList<AnimatedContainer>(find.descendant(of: find.byType(AppCard), matching: find.byType(AnimatedContainer)))
            .firstWhere((c) => c.decoration != null);
        return (c.decoration! as BoxDecoration).boxShadow;
      }

      final rest = tester.getTopLeft(materialIn(_box));
      expect(shadow(), AppPalette.light.shadowSm);
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(tester.getTopLeft(materialIn(_box)).dy, closeTo(rest.dy - 2, 0.01));
      expect(shadow(), AppPalette.light.shadowMd);

      await g.down(tester.getCenter(find.byKey(_box)));
      await g.up();
      await settle(tester);
      expect(taps, 1);

      await tester.pumpWidget(app(const SizedBox(width: 200, child: AppCard(key: _box, child: Text('Plain')))));
      expect(find.descendant(of: find.byType(AppCard), matching: find.byType(Pressable)), findsNothing);
    });

    testWidgets('CircleIconButton grows, tints and deepens its shadow under a mouse, and still taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(app(CircleIconButton(key: _box, icon: Icons.favorite_border_rounded, tooltip: 'Save', onPressed: () => taps++)));
      final g = await mouse(tester);
      double circleWidth() {
        final ink = find.descendant(of: find.byKey(_box), matching: find.byType(InkWell));
        return tester.getTopRight(ink).dx - tester.getTopLeft(ink).dx;
      }

      final before = circleWidth();
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(circleWidth(), closeTo(before * 1.06, 0.1));
      final circle = tester.widgetList<AnimatedContainer>(find.descendant(of: find.byType(CircleIconButton), matching: find.byType(AnimatedContainer)))
          .firstWhere((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).shape == BoxShape.circle);
      expect((circle.decoration! as BoxDecoration).boxShadow, AppPalette.light.shadowMd);
      expect((circle.decoration! as BoxDecoration).color, isNot(AppPalette.light.surface));

      await g.down(tester.getCenter(find.byKey(_box)));
      await g.up();
      await settle(tester);
      expect(taps, 1);
    });

    testWidgets('a ProductCard lifts under a mouse and the photo well is tinted by department', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      const phone = ProductSummary(
        id: 1,
        title: 'Phone',
        slug: 'phone',
        price: 1000,
        category: NamedRef(id: 1, name: 'Smartphones', slug: 'smartphones'),
      );
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        app(
          const SizedBox(width: 180, height: 300, child: ProductCard(key: _box, product: phone)),
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        ),
      );
      final rest = tester.getTopLeft(materialIn(_box));
      final g = await mouse(tester);
      await g.moveTo(tester.getCenter(find.byKey(_box)));
      await settle(tester);
      expect(tester.getTopLeft(materialIn(_box)).dy, closeTo(rest.dy - 2, 0.01));

      final wells = tester.widgetList<ColoredBox>(find.descendant(of: find.byType(ProductCard), matching: find.byType(ColoredBox)));
      expect(wells.map((w) => w.color), contains(AppPalette.light.departmentWell('smartphones')));
      expect(AppPalette.light.departmentWell('smartphones'), isNot(AppPalette.light.imageWell));
    });
  });
}
