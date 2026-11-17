import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/network/api_client.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/features/cart/data/models/cart.dart';
import 'package:cartwise/features/cart/presentation/cart_screen.dart';
import 'package:cartwise/features/cart/providers/cart_controller.dart';
import 'package:cartwise/features/catalog/data/models/catalog_models.dart';
import 'package:cartwise/features/catalog/providers/catalog_providers.dart';
import 'package:cartwise/features/checkout/presentation/checkout_screen.dart';
import 'package:cartwise/features/home/presentation/home_screen.dart';
import 'package:cartwise/features/product/data/models/product_detail.dart';
import 'package:cartwise/features/product/presentation/product_detail_screen.dart';
import 'package:cartwise/features/product/providers/product_providers.dart';
import 'package:cartwise/features/profile/data/models/address.dart';
import 'package:cartwise/features/profile/providers/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = ProductSummary(
  id: 7,
  title: 'Samsung Galaxy S24 Ultra 512GB Titanium Black with a very long name',
  slug: 'galaxy-s24',
  brand: 'Samsung',
  category: NamedRef(id: 1, name: 'Smartphones', slug: 'smartphones'),
  price: 389999,
  compareAtPrice: 429999,
  rating: 4.4,
  ratingCount: 87,
  stock: 3,
);

final _cart = Cart(
  items: [
    const CartItem(productId: 7, product: _phone, quantity: 2, lineTotal: 779998),
    CartItem(
      productId: 8,
      product: ProductSummary.fromJson(const {'id': 8, 'title': 'Out of stock case', 'slug': 'c', 'price': 999, 'inStock': false}),
      quantity: 1,
      lineTotal: 0,
    ),
  ],
  summary: const CartSummary(
    itemCount: 3,
    subtotal: 779998,
    discount: 2000,
    total: 777998,
    coupon: AppliedCoupon(code: 'WELCOME10', description: '10% off your order (up to Rs 2,000)'),
    savings: 81998,
  ),
);

final _detail = ProductDetail(
  summary: _phone,
  description: 'A' * 400,
  images: const ['/uploads/a.webp', '/uploads/b.webp'],
  highlights: const ['200 MP camera', 'Titanium frame', 'S Pen built in'],
  specs: [for (var i = 0; i < 9; i++) MapEntry('Spec $i', 'Value $i with some longer text')],
  warranty: '1 year warranty',
  shippingInfo: 'Ships in 2 days',
  returnPolicy: '7 days return',
  soldCount: 1240,
  ratingBreakdown: const {5: 50, 4: 20, 3: 10, 2: 4, 1: 3},
);

final _feed = HomeFeed(
  banners: const [
    HomeBanner(
      id: 1,
      title: 'Mega Electronics Week with a long headline',
      subtitle: 'Up to 30% off smartphones, laptops & tablets',
      ctaLabel: 'Shop now',
      target: BannerTarget(type: 'department', value: 'electronics'),
      theme: 'indigo',
    ),
    HomeBanner(id: 2, title: 'Ask the AI', target: BannerTarget(type: 'assistant'), theme: 'violet'),
  ],
  departments: const [
    Department(id: 1, name: 'Electronics', slug: 'electronics', icon: 'devices'),
    Department(id: 2, name: 'Beauty & Personal Care', slug: 'beauty-personal-care'),
  ],
  flashDeals: const [_phone],
  trending: const [_phone],
  topRated: const [_phone],
  newArrivals: const [_phone],
  dealEndsAt: DateTime.now().add(const Duration(hours: 5)),
);

class _FakeAddresses extends AddressesController {
  @override
  Future<List<Address>> build() async => const [
    Address(
      id: 1,
      label: 'Home',
      fullName: 'Ayesha Khan',
      phone: '+92 300 1234567',
      line1: 'House 42, Street 7, Block 5',
      line2: 'Clifton',
      city: 'Karachi',
      province: 'Sindh',
      postalCode: '75600',
      isDefault: true,
    ),
  ];
}

class _FakeCart extends CartController {
  @override
  Future<Cart> build() async => _cart;
}

Future<void> _pump(WidgetTester tester, Widget screen, {required double scale, Size size = const Size(320, 640)}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        cartProvider.overrideWith(_FakeCart.new),
        productDetailProvider.overrideWith((ref, id) async => _detail),
        topReviewsProvider.overrideWith((ref, id) async => const Paginated<Review>.empty()),
        homeFeedProvider.overrideWith((ref) async => _feed),
        addressesProvider.overrideWith(_FakeAddresses.new),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery.withClampedTextScaling(minScaleFactor: scale, maxScaleFactor: scale, child: screen),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  for (final scale in [1.0, 2.0]) {
    testWidgets('cart renders at 320 px, text scale $scale', (tester) async {
      await _pump(tester, const CartScreen(), scale: scale);
      expect(find.text('WELCOME10 applied'), findsOneWidget);
      expect(find.text('Checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('product detail renders at 320 px, text scale $scale', (tester) async {
      await _pump(tester, const ProductDetailScreen(idOrSlug: '7'), scale: scale);
      expect(find.textContaining('Only 3 left'), findsOneWidget);
      expect(find.text('Buy now'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('home renders at 320 px, text scale $scale', (tester) async {
      await _pump(tester, const HomeScreen(), scale: scale);
      expect(find.text('Guided Finder'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Flash deals'), 300, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Flash deals'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('checkout renders at 320 px, text scale $scale', (tester) async {
      await _pump(tester, const CheckoutScreen(), scale: scale);
      expect(find.text('Delivery address'), findsOneWidget);
      await tester.ensureVisible(find.text('Credit / debit card'));
      await tester.pump();
      await tester.tap(find.text('Credit / debit card'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Card number'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('product detail uses two columns on desktop', (tester) async {
    await _pump(tester, const ProductDetailScreen(idOrSlug: '7'), scale: 1, size: const Size(1280, 900));
    expect(find.text('Buy now'), findsOneWidget);
    expect(find.text('Warranty'), findsOneWidget); // service info lives in the side panel
    expect(tester.takeException(), isNull);
  });
}
