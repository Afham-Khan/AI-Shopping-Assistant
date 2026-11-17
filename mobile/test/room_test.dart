import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/features/home/data/room_repository.dart';
import 'package:cartwise/features/home/presentation/room/room_layout.dart';
import 'package:cartwise/features/home/presentation/room/room_section.dart';
import 'package:cartwise/features/home/providers/room_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSummary _p(int id, String title, {String cat = 'laptops'}) => ProductSummary(
  id: id,
  title: title,
  slug: 'p-$id',
  price: 1000.0 * id,
  category: NamedRef(id: id, name: cat, slug: cat),
);

void main() {
  group('RoomLayout', () {
    test('every zone has a unique id and number, and its hotspot and slot sit inside the scene', () {
      final scene = Offset.zero & RoomLayout.size;
      expect(RoomLayout.zones.map((z) => z.id).toSet(), hasLength(7));
      expect(RoomLayout.zones.map((z) => z.number).toSet(), {1, 2, 3, 4, 5, 6, 7});
      for (final z in RoomLayout.zones) {
        expect(scene.contains(z.hotspot), isTrue, reason: z.id);
        expect(z.hit.contains(z.hotspot), isTrue, reason: '${z.id} hotspot inside its zone');
        expect(scene.intersect(z.slot), z.slot, reason: z.id);
      }
    });

    test('zoneAt resolves taps, specific zones first', () {
      expect(RoomLayout.zoneAt(const Offset(140, 400)), 'wardrobe');
      expect(RoomLayout.zoneAt(const Offset(450, 150)), 'garage', reason: 'the window sits above the desk');
      expect(RoomLayout.zoneAt(const Offset(500, 420)), 'desk');
      expect(RoomLayout.zoneAt(const Offset(750, 360)), 'vanity');
      expect(RoomLayout.zoneAt(const Offset(920, 560)), 'kitchen');
      expect(RoomLayout.zoneAt(const Offset(800, 150)), 'shelf');
      expect(RoomLayout.zoneAt(const Offset(120, 760)), 'corner');
      expect(RoomLayout.zoneAt(const Offset(520, 760)), isNull, reason: 'the rug is not a zone');
    });

    test('viewportFor keeps the scene aspect, stays inside the scene and caps the zoom', () {
      final aspect = RoomLayout.size.width / RoomLayout.size.height;
      for (final z in RoomLayout.zones) {
        final v = RoomLayout.viewportFor(z.hit);
        expect(v.width / v.height, closeTo(aspect, 1e-6), reason: z.id);
        expect(v.left, greaterThanOrEqualTo(0));
        expect(v.top, greaterThanOrEqualTo(0));
        expect(v.right, lessThanOrEqualTo(RoomLayout.size.width + 1e-6));
        expect(v.bottom, lessThanOrEqualTo(RoomLayout.size.height + 1e-6));
        expect(RoomLayout.size.width / v.width, lessThanOrEqualTo(2.6 + 1e-6));
        expect(v.contains(z.hit.center), isTrue);
      }
      final tiny = RoomLayout.viewportFor(const Rect.fromLTWH(500, 400, 10, 10));
      expect(RoomLayout.size.width / tiny.width, closeTo(2.6, 1e-6));
    });

    test('merge fills defaults, keeps API data and orders by hotspot number', () {
      final zones = RoomLayout.merge([
        RoomZoneData(id: 'desk', label: 'Workspace', department: 'electronics', featured: [_p(1, 'Laptop')]),
      ]);
      expect(zones.map((z) => z.spec.number), [1, 2, 3, 4, 5, 6, 7]);
      final desk = zones.firstWhere((z) => z.id == 'desk');
      expect(desk.label, 'Workspace');
      expect(desk.featured.single.title, 'Laptop');
      expect(zones.firstWhere((z) => z.id == 'vanity').department, 'beauty-personal-care');
    });

    test('products map to zones by category; placed items share a slot', () {
      final zones = RoomLayout.merge([
        const RoomZoneData(id: 'desk', label: 'Desk', department: 'electronics', categories: ['laptops']),
        const RoomZoneData(id: 'corner', label: 'Gym', department: 'sports-outdoors', categories: ['fitness']),
      ]);
      expect(RoomLayout.zoneForProduct(_p(1, 'A', cat: 'laptops'), zones), 'desk');
      expect(RoomLayout.zoneForProduct(_p(2, 'B', cat: 'fitness'), zones), 'corner');
      expect(RoomLayout.zoneForProduct(_p(3, 'C', cat: 'unknown'), zones), isNull);

      const slot = Rect.fromLTWH(0, 0, 120, 100);
      expect(RoomLayout.placedRect(slot, 0, 1), slot);
      final a = RoomLayout.placedRect(slot, 0, 3);
      final c = RoomLayout.placedRect(slot, 2, 3);
      expect(a.left, 0);
      expect(c.right, closeTo(slot.right, 1e-6));
      expect(a.bottom, slot.bottom);
    });

    test('night factor follows the clock with soft dusk and dawn', () {
      expect(RoomLayout.nightFactor(DateTime(2026, 1, 1, 12)), 0);
      expect(RoomLayout.nightFactor(DateTime(2026, 1, 1, 23)), 1);
      expect(RoomLayout.nightFactor(DateTime(2026, 1, 1, 3)), 1);
      expect(RoomLayout.nightFactor(DateTime(2026, 1, 1, 18)), closeTo(0.5, 1e-9));
      expect(RoomLayout.nightFactor(DateTime(2026, 1, 1, 6)), closeTo(0.5, 1e-9));
    });

    test('department names', () {
      expect(RoomLayout.departmentName('home-living'), 'Home & Living');
      expect(RoomLayout.departmentName('electronics'), 'Electronics');
    });
  });

  group('RoomSection', () {
    setUpAll(() => AppTheme.useGoogleFonts = false);

    testWidgets('tapping a hotspot opens its tray, counts it as explored, and Back closes it', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final zones = RoomLayout.merge([
        RoomZoneData(
          id: 'wardrobe',
          label: 'The wardrobe',
          department: 'fashion',
          featured: [_p(1, 'Linen shirt', cat: 'shirts'), _p(2, 'Canvas tote', cat: 'bags')],
        ),
        RoomZoneData(id: 'desk', label: 'The desk', department: 'electronics', featured: [_p(3, 'Laptop')]),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            roomZonesProvider.overrideWith((ref) async => zones),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: RoomSection(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('0/7 explored'), findsOneWidget);
      expect(find.text('Linen shirt'), findsNothing, reason: 'the tray is closed');

      await tester.tap(find.byTooltip('The wardrobe'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('1/7 explored'), findsOneWidget);
      expect(find.text('Linen shirt'), findsOneWidget);
      expect(find.text('Canvas tote'), findsOneWidget);
      expect(find.text('Fashion'), findsWidgets, reason: 'the zoomed-in label');
      expect(prefs.getStringList(RoomExploredController.storageKey), ['wardrobe']);

      // switching zones while zoomed swaps the tray
      await tester.tap(find.byTooltip('Back to the room'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Linen shirt'), findsNothing);

      await tester.tap(find.byTooltip('The desk'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('2/7 explored'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // let the hotspot pulses finish so no ticker is left running
      await tester.pump(const Duration(seconds: 10));
    });
  });
}
