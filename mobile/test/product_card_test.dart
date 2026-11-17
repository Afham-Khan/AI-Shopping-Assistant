import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/core/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _product = ProductSummary(
  id: 1,
  title: 'iPhone 13 Pro with a deliberately long title that needs two lines',
  slug: 'iphone-13-pro',
  brand: 'Apple',
  price: 279999,
  compareAtPrice: 309999,
  discountPercent: 9.7,
  rating: 4.6,
  ratingCount: 128,
  stock: 23,
);

Future<void> _pump(WidgetTester tester, Widget child, {double textScale = 1, Size size = const Size(400, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(body: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  testWidgets('compact card shows brand, title, rating, prices and discount', (tester) async {
    await _pump(tester, const Center(child: SizedBox(width: 180, child: ProductCard(product: _product))));

    expect(find.text('APPLE'), findsOneWidget); // brand is set as an uppercase eyebrow
    expect(find.textContaining('iPhone 13 Pro'), findsOneWidget);
    expect(find.text('Rs 279,999'), findsOneWidget);
    expect(find.text('Rs 309,999'), findsOneWidget);
    expect(find.text('-10%'), findsOneWidget);
    expect(find.text('4.6'), findsOneWidget);
    expect(find.byTooltip('Save to wishlist'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide card renders without overflow', (tester) async {
    await _pump(
      tester,
      const ProductCard(product: _product, variant: ProductCardVariant.wide),
      size: const Size(320, 640),
    );
    expect(find.text('Rs 279,999'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('grid at 320 px fits at text scale $scale', (tester) async {
      await _pump(
        tester,
        ProductGrid(products: List.generate(4, (i) => _product)),
        textScale: scale,
        size: const Size(320, 900),
      );
      expect(find.byType(ProductCard), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('grid uses more columns on wide screens', (tester) async {
    expect(ProductGrid.columnsFor(320), 2);
    expect(ProductGrid.columnsFor(700), 3);
    expect(ProductGrid.columnsFor(1000), 4);
    expect(ProductGrid.columnsFor(1200), 5);
  });
}
