import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/features/product/presentation/widgets/specs_section.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

MapEntry<String, String> e(String k, String v) => MapEntry(k, v);

final phone = [
  e('OS', 'ColorOS 6 (Android 9)'),
  e('RAM', '8 GB'),
  e('Weight', '183 g'),
  e('Battery', '4000 mAh'),
  e('Display', '6.4-inch Super AMOLED FHD+, 2340 x 1080'),
  e('Network', '4G LTE, dual SIM'),
  e('Storage', '128 GB'),
  e('Charging', '20W VOOC 3.0 fast charging'),
  e('Processor', 'Qualcomm Snapdragon 712 AIE octa-core'),
  e('Fingerprint', 'In-display optical'),
  e('Rear Camera', 'Quad: 64 MP f/1.8 + 8 MP ultra-wide + 2 MP macro + 2 MP depth'),
  e('Front Camera', '16 MP'),
];

Widget host(Widget child, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.light,
  home: MediaQuery.withClampedTextScaling(
    minScaleFactor: textScale,
    maxScaleFactor: textScale,
    child: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
  ),
);

Future<void> size(WidgetTester tester, double w) async {
  tester.view.physicalSize = Size(w, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  group('SpecIcons', () {
    test('maps the common spec names to their icons', () {
      expect(SpecIcons.of('RAM'), Icons.memory_rounded);
      expect(SpecIcons.of('Storage'), Icons.sd_storage_rounded);
      expect(SpecIcons.of('Battery'), Icons.battery_full_rounded);
      expect(SpecIcons.of('Battery Life'), Icons.battery_full_rounded);
      expect(SpecIcons.of('Rear Camera'), Icons.photo_camera_rounded);
      expect(SpecIcons.of('Front Camera'), Icons.camera_front_rounded);
      expect(SpecIcons.of('Processor'), Icons.developer_board_rounded);
      expect(SpecIcons.of('Chip'), Icons.developer_board_rounded);
      expect(SpecIcons.of('Weight'), Icons.scale_rounded);
      expect(SpecIcons.of('Net Weight'), Icons.scale_rounded);
      expect(SpecIcons.of('Fabric'), Icons.texture_rounded);
      expect(SpecIcons.of('Upper Material'), Icons.texture_rounded);
      expect(SpecIcons.of('Volume'), Icons.water_drop_rounded);
      expect(SpecIcons.of('Charging'), Icons.bolt_rounded);
      expect(SpecIcons.of('Dimensions'), Icons.straighten_rounded);
      expect(SpecIcons.of('Water Resistance'), Icons.umbrella_rounded);
      expect(SpecIcons.of('Fingerprint'), Icons.fingerprint_rounded);
      expect(SpecIcons.of('Network'), Icons.signal_cellular_alt_rounded);
      expect(SpecIcons.of('OS'), Icons.settings_suggest_rounded);
      expect(SpecIcons.of('Movement'), Icons.watch_rounded);
      expect(SpecIcons.of('Fuel'), Icons.local_gas_station_rounded);
      expect(SpecIcons.of('Dietary'), Icons.eco_rounded);
      expect(SpecIcons.of('Warranty'), Icons.verified_user_rounded);
    });

    test('Display is a phone for a small screen and a monitor for a big one', () {
      expect(SpecIcons.of('Display', value: '6.4-inch Super AMOLED'), Icons.smartphone_rounded);
      expect(SpecIcons.of('Display', value: '15.6" FHD IPS'), Icons.monitor_rounded);
      expect(SpecIcons.of('Display', value: '27 inch 4K'), Icons.monitor_rounded);
      expect(SpecIcons.of('Display'), Icons.smartphone_rounded);
      expect(SpecIcons.of('Screen', value: '5.5 in'), Icons.smartphone_rounded);
    });

    test('matches whole words, any case, and falls back to a neutral icon', () {
      expect(SpecIcons.of('ram'), Icons.memory_rounded);
      expect(SpecIcons.of('Program'), isNot(Icons.memory_rounded)); // "ram" inside a word
      expect(SpecIcons.of('Cost'), isNot(Icons.settings_suggest_rounded)); // "os" inside a word
      expect(SpecIcons.of('Dimension'), Icons.straighten_rounded);
      expect(SpecIcons.of('Something New'), Icons.tune_rounded);
      expect(SpecIcons.of(''), Icons.tune_rounded);
    });
  });

  group('picking the key specs', () {
    test('a phone gets the six that matter, most important first', () {
      final key = selectKeySpecs(phone);
      expect(key.map((s) => s.key), ['Processor', 'RAM', 'Storage', 'Display', 'Battery', 'Rear Camera']);
    });

    test('works for other departments and prefers exact names', () {
      final watch = [e('Movement', 'Quartz'), e('Case Size', '42 mm'), e('Strap', 'Leather'), e('Water Resistance', '5 ATM')];
      expect(selectKeySpecs(watch).map((s) => s.key), containsAll(['Water Resistance', 'Movement', 'Case Size']));
      final shirt = [e('Fabric', 'Cotton'), e('Fit', 'Slim'), e('Care', 'Machine wash'), e('Closure', 'Buttons')];
      expect(selectKeySpecs(shirt).map((s) => s.key), ['Fabric', 'Fit']);
      final exact = [e('Camera Mode', 'Auto'), e('Camera', '12 MP'), e('RAM', '8 GB')];
      expect(selectKeySpecs(exact).map((s) => s.key), ['RAM', 'Camera']);
    });

    test('with nothing worth featuring (or one thing) there are no tiles', () {
      expect(selectKeySpecs([e('Closure', 'Zip'), e('Care', 'Wash')]), isEmpty);
      expect(selectKeySpecs([e('RAM', '8 GB'), e('Closure', 'Zip')]), isEmpty);
      expect(selectKeySpecs(const []), isEmpty);
      expect(selectKeySpecs([e('RAM', ''), e('Storage', '  ')]), isEmpty);
    });

    test('max limits the tiles', () {
      expect(selectKeySpecs(phone, max: 4), hasLength(4));
    });

    test('a tile shows the headline of a long value', () {
      expect(shortSpecValue('6.4-inch Super AMOLED FHD+, 2340 x 1080'), '6.4-inch Super AMOLED FHD+');
      expect(shortSpecValue('Quad: 64 MP f/1.8 + 8 MP ultra-wide + 2 MP macro'), 'Quad: 64 MP f/1.8');
      expect(shortSpecValue('ColorOS 6 (Android 9)'), 'ColorOS 6');
      expect(shortSpecValue('8 GB'), '8 GB');
      expect(shortSpecValue('  128 GB  '), '128 GB');
      expect(shortSpecValue('A, B'), 'A, B'); // too short to cut
    });

    test('the list keeps everything not featured, plus featured specs whose tile was shortened', () {
      final key = selectKeySpecs(phone);
      final list = specsForList(phone, key);
      final names = list.map((s) => s.key).toList();
      // featured with complete values: only on a tile
      expect(names, isNot(contains('RAM')));
      expect(names, isNot(contains('Storage')));
      expect(names, isNot(contains('Battery')));
      // featured but shortened: complete value stays reachable
      expect(names, containsAll(['Display', 'Rear Camera', 'Processor']));
      // never featured
      expect(names, containsAll(['OS', 'Weight', 'Network', 'Charging', 'Fingerprint', 'Front Camera']));
      // original order is kept
      expect(names, ['OS', 'Weight', 'Display', 'Network', 'Charging', 'Processor', 'Fingerprint', 'Rear Camera', 'Front Camera']);
    });
  });

  group('SpecsSection', () {
    testWidgets('shows the explain card, a grid of key spec tiles and the rest as a list', (tester) async {
      await size(tester, 400);
      var explained = 0;
      await tester.pumpWidget(host(SpecsSection(specs: phone, onExplain: () => explained++)));

      expect(find.text('Explain these specs'), findsOneWidget);
      expect(find.byType(SpecTile), findsNWidgets(6));
      // bold value + muted label per tile
      expect(find.text('8 GB'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('6.4-inch Super AMOLED FHD+'), findsOneWidget);
      // icons per spec type
      expect(find.byIcon(Icons.memory_rounded), findsOneWidget);
      expect(find.byIcon(Icons.sd_storage_rounded), findsOneWidget);
      expect(find.byIcon(Icons.battery_full_rounded), findsOneWidget);
      expect(find.byIcon(Icons.smartphone_rounded), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
      expect(find.byIcon(Icons.developer_board_rounded), findsOneWidget);
      // the list has the full values and a header
      expect(find.text('All specifications'), findsOneWidget);
      expect(find.text('6.4-inch Super AMOLED FHD+, 2340 x 1080'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);

      // two tiles per row on a phone
      final tiles = tester.widgetList<SpecTile>(find.byType(SpecTile)).toList();
      final first = tester.getTopLeft(find.byWidget(tiles[0]));
      final second = tester.getTopLeft(find.byWidget(tiles[1]));
      expect(second.dy, first.dy);
      expect(second.dx, greaterThan(first.dx + 100));

      await tester.tap(find.text('Explain these specs'));
      expect(explained, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the list collapses to six rows and expands on demand', (tester) async {
      await size(tester, 400);
      final many = [
        e('RAM', '8 GB'),
        e('Storage', '128 GB'),
        for (var i = 0; i < 10; i++) e('Extra $i', 'Value $i'),
      ];
      await tester.pumpWidget(host(SpecsSection(specs: many)));
      expect(find.text('Explain these specs'), findsNothing); // no callback, no card
      expect(find.text('Extra 5'), findsOneWidget);
      expect(find.text('Extra 6'), findsNothing);
      expect(find.text('Show all 10 specifications'), findsOneWidget);

      await tester.tap(find.text('Show all 10 specifications'));
      await tester.pumpAndSettle();
      expect(find.text('Extra 9'), findsOneWidget);
      expect(find.text('Show fewer'), findsOneWidget);

      await tester.tap(find.text('Show fewer'));
      await tester.pumpAndSettle();
      expect(find.text('Extra 9'), findsNothing);
    });

    testWidgets('a product with nothing to feature gets just the list', (tester) async {
      await size(tester, 400);
      await tester.pumpWidget(host(SpecsSection(specs: [e('Closure', 'Zip'), e('Care', 'Wash cold')], onExplain: () {})));
      expect(find.byType(SpecTile), findsNothing);
      expect(find.text('All specifications'), findsNothing);
      expect(find.text('Closure'), findsOneWidget);
      expect(find.text('Wash cold'), findsOneWidget);
    });

    testWidgets('an odd number of tiles gives the last one the full row', (tester) async {
      await size(tester, 400);
      final five = [e('RAM', '8 GB'), e('Storage', '128 GB'), e('Battery', '4000 mAh'), e('Weight', '183 g'), e('OS', 'Android 14')];
      await tester.pumpWidget(host(SpecsSection(specs: five)));
      final tiles = tester.widgetList<SpecTile>(find.byType(SpecTile)).toList();
      expect(tiles, hasLength(5));
      final lastWidth = tester.getSize(find.byWidget(tiles.last)).width;
      final firstWidth = tester.getSize(find.byWidget(tiles.first)).width;
      expect(lastWidth, greaterThan(firstWidth * 1.8));
    });

    for (final (width, scale) in [(320.0, 1.0), (320.0, 2.0), (400.0, 2.0), (460.0, 1.0)]) {
      testWidgets('fits without overflow at $width px, text scale $scale', (tester) async {
        await size(tester, width);
        await tester.pumpWidget(host(SpecsSection(specs: phone, onExplain: () {}), textScale: scale));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SpecTile), findsNWidgets(6));
        if (width == 320 && scale == 2.0) {
          // single column when tiles would be cramped
          final tiles = tester.widgetList<SpecTile>(find.byType(SpecTile)).toList();
          expect(tester.getTopLeft(find.byWidget(tiles[1])).dy, greaterThan(tester.getTopLeft(find.byWidget(tiles[0])).dy));
        }
      });
    }

    testWidgets('tiles read as one semantic item with the full value', (tester) async {
      await size(tester, 400);
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host(SpecsSection(specs: phone)));
      expect(find.bySemanticsLabel('Rear Camera: Quad: 64 MP f/1.8 + 8 MP ultra-wide + 2 MP macro + 2 MP depth'), findsOneWidget);
      handle.dispose();
    });
  });

  group('HighlightChips', () {
    testWidgets('each highlight is a chip with a check icon, wrapping on narrow screens', (tester) async {
      await size(tester, 320);
      const items = ['Water resistant to 1 metre', 'Two-year warranty', 'A deliberately long highlight that has to wrap onto a second line inside its chip'];
      await tester.pumpWidget(host(const HighlightChips(items: items), textScale: 2));
      await tester.pumpAndSettle();
      for (final h in items) {
        expect(find.text(h), findsOneWidget);
      }
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  });
}
