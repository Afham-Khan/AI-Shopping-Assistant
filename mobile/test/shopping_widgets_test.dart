import 'dart:ui' as ui;

import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/network/api_client.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/core/widgets/widgets.dart';
import 'package:cartwise/features/ai/data/ai_repository.dart';
import 'package:cartwise/features/ai/data/models/ai_models.dart';
import 'package:cartwise/features/ai/data/models/shopping_models.dart';
import 'package:cartwise/features/ai/presentation/compare_screen.dart';
import 'package:cartwise/features/ai/presentation/gift_finder_screen.dart';
import 'package:cartwise/features/ai/presentation/widgets/complete_the_look.dart';
import 'package:cartwise/features/ai/presentation/widgets/compare_extras.dart';
import 'package:cartwise/features/ai/presentation/widgets/image_cropper.dart';
import 'package:cartwise/features/ai/presentation/widgets/spec_explainer.dart';
import 'package:cartwise/features/ai/providers/ai_providers.dart';
import 'package:cartwise/features/assistant/presentation/widgets/chat_input_bar.dart';
import 'package:cartwise/features/auth/providers/auth_controller.dart';
import 'package:cartwise/features/notifications/presentation/notifications_screen.dart';
import 'package:cartwise/features/notifications/providers/notifications_providers.dart';
import 'package:cartwise/features/product/data/models/price_history.dart';
import 'package:cartwise/features/product/presentation/widgets/price_history_card.dart';
import 'package:cartwise/features/product/presentation/widgets/price_history_chart.dart';
import 'package:cartwise/features/product/providers/product_providers.dart';
import 'package:cartwise/features/profile/data/memory_models.dart';
import 'package:cartwise/features/profile/data/memory_repository.dart';
import 'package:cartwise/features/profile/presentation/shopping_memory_screen.dart';
import 'package:cartwise/features/wishlist/data/price_watch_models.dart';
import 'package:cartwise/features/wishlist/data/price_watch_repository.dart';
import 'package:cartwise/features/wishlist/presentation/price_alerts_screen.dart';
import 'package:cartwise/features/wishlist/presentation/widgets/price_watch_badge.dart';
import 'package:cartwise/features/wishlist/presentation/widgets/watch_price_sheet.dart';
import 'package:cartwise/features/wishlist/presentation/wishlist_screen.dart';
import 'package:cartwise/features/wishlist/providers/price_watch_providers.dart';
import 'package:cartwise/features/wishlist/providers/wishlist_items_provider.dart';
import 'package:cartwise/features/wishlist/providers/wishlist_provider.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = ProductSummary(
  id: 7,
  title: 'Galaxy S24',
  slug: 'galaxy-s24',
  brand: 'Samsung',
  category: NamedRef(id: 1, name: 'Smartphones', slug: 'smartphones'),
  price: 100000,
  stock: 5,
);

const _dress = ProductSummary(
  id: 20,
  title: 'Red evening dress',
  slug: 'red-dress',
  category: NamedRef(id: 9, name: "Women's Dresses", slug: 'womens-dresses'),
  price: 20000,
  stock: 5,
);

Map<String, dynamic> _card(int id, String title, double price, String slug, {List<String> reasons = const []}) => {
  'id': id,
  'title': title,
  'slug': 'p-$id',
  'category': {'id': 1, 'name': 'Category', 'slug': slug},
  'price': price,
  'stock': 5,
  'inStock': true,
  if (reasons.isNotEmpty) 'match': {'score': 0.8, 'reasons': reasons},
};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  double scale = 1,
  Size size = const Size(400, 900),
  bool signedIn = true,
}) async {
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
        isAuthenticatedProvider.overrideWithValue(signedIn),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery.withClampedTextScaling(minScaleFactor: scale, maxScaleFactor: scale, child: home),
      ),
    ),
  );
  await _settle(tester);
}

// ---------------------------------------------------------------- fakes

class _FakeWatchRepo extends PriceWatchRepository {
  _FakeWatchRepo({List<PriceWatch> initial = const []}) : items = [...initial], super(ApiClient(Dio()));

  List<PriceWatch> items;
  final saves = <({int productId, double? target, bool restock})>[];
  final removed = <int>[];

  @override
  Future<List<PriceWatch>> list() async => [...items];

  @override
  Future<PriceWatchSaved> save({required int productId, double? targetPrice, bool notifyRestock = true}) async {
    saves.add((productId: productId, target: targetPrice, restock: notifyRestock));
    final w = PriceWatch(id: 1, product: _phone, targetPrice: targetPrice, notifyRestock: notifyRestock);
    items = [w, ...items.where((i) => i.productId != productId)];
    return (watch: w, message: 'Watching Galaxy S24');
  }

  @override
  Future<String?> remove(int productId) async {
    removed.add(productId);
    items = [...items.where((i) => i.productId != productId)];
    return 'Price watch removed';
  }
}

PriceWatch _watch({double? target = 95000, bool restock = true, String summary = ''}) => PriceWatch(
  id: 1,
  product: _phone,
  targetPrice: target,
  notifyRestock: restock,
  status: PriceWatchStatus(currentPrice: 100000, summary: summary),
);

/// A page that, like the product page, keeps the watch list loaded and opens the sheet.
class _SheetHost extends ConsumerWidget {
  const _SheetHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(priceWatchesProvider);
    return Scaffold(
      body: Center(
        child: TextButton(
          onPressed: () => showAppBottomSheet<void>(context, builder: (_) => const WatchPriceSheet(product: _phone)),
          child: const Text('Open'),
        ),
      ),
    );
  }
}

class _FakeMemoryRepo extends MemoryRepository {
  _FakeMemoryRepo(this.memory) : super(ApiClient(Dio()));

  ShoppingMemory memory;
  final enabledCalls = <bool>[];
  var forgot = 0;

  @override
  Future<ShoppingMemory> get() async => memory;

  @override
  Future<String?> setEnabled(bool enabled) async {
    enabledCalls.add(enabled);
    return enabled ? 'Shopping memory is on' : 'Shopping memory is off';
  }

  @override
  Future<String?> forgetAll() async {
    forgot++;
    memory = ShoppingMemory(enabled: memory.enabled);
    return 'Shopping memory cleared';
  }
}

class _FakeNotifications extends NotificationsRepository {
  _FakeNotifications(this.items) : super(ApiClient(Dio()));

  final List<AppNotification> items;

  @override
  Future<Paginated<AppNotification>> list({int page = 1}) async =>
      Paginated(items: items, page: 1, limit: 20, total: items.length, totalPages: 1, meta: {'unreadCount': items.length});

  @override
  Future<int> unreadCount() async => items.length;
}

class _FakeGiftAi extends AiRepository {
  _FakeGiftAi() : super(ApiClient(Dio()));

  final calls = <Map<String, Object?>>[];

  @override
  Future<GiftResult> gift({
    required String recipient,
    required String occasion,
    required num budget,
    List<String> interests = const [],
  }) async {
    calls.add({'recipient': recipient, 'occasion': occasion, 'budget': budget, 'interests': interests});
    return GiftResult.fromJson({
      'title': 'Birthday gifts for your mom under Rs 10K',
      'note': 'A curated mix of jewellery.',
      'products': [
        _card(31, 'Gold ring', 8500, 'womens-jewellery', reasons: ['Within your Rs 10,000 budget', 'Rated 4.5 by 12 shoppers']),
        _card(32, 'Rose perfume', 6200, 'fragrances', reasons: ['A classic birthday gift']),
      ],
    });
  }
}

class _Ids extends WishlistController {
  @override
  Set<int> build() => {7};
}

// ---------------------------------------------------------------- tests

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppTheme.useGoogleFonts = false);

  group('watch price sheet', () {
    testWidgets('picks 10% lower and starts watching', (tester) async {
      final repo = _FakeWatchRepo();
      await _pump(tester, const _SheetHost(), overrides: [priceWatchRepositoryProvider.overrideWithValue(repo)]);
      await tester.tap(find.text('Open'));
      await _settle(tester);

      expect(find.text('Watch price'), findsOneWidget);
      expect(find.text('Any drop'), findsOneWidget);
      expect(find.textContaining('the moment the price drops'), findsOneWidget);

      await tester.tap(find.text('10% lower'));
      await tester.pump();
      expect(find.textContaining('Rs 90,000 or lower'), findsOneWidget);

      await tester.tap(find.text('Start watching'));
      await _settle(tester);
      expect(repo.saves.single.productId, 7);
      expect(repo.saves.single.target, 90000);
      expect(repo.saves.single.restock, isTrue);
      expect(find.byType(WatchPriceSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a custom target must be below today\'s price', (tester) async {
      final repo = _FakeWatchRepo();
      await _pump(tester, const _SheetHost(), overrides: [priceWatchRepositoryProvider.overrideWithValue(repo)]);
      await tester.tap(find.text('Open'));
      await _settle(tester);

      await tester.tap(find.text('Custom'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), '120000');
      await tester.tap(find.text('Start watching'));
      await _settle(tester);
      expect(find.textContaining("below today's Rs 100,000"), findsOneWidget);
      expect(repo.saves, isEmpty);

      await tester.enterText(find.byType(TextField), '85,000');
      await tester.pump();
      expect(find.textContaining('Rs 85,000 or lower (15% below'), findsOneWidget);
      await tester.tap(find.text('Start watching'));
      await _settle(tester);
      expect(repo.saves.single.target, 85000);
    });

    testWidgets('editing shows the current choice and can stop watching', (tester) async {
      final repo = _FakeWatchRepo(initial: [_watch(target: 95000, restock: false)]);
      await _pump(tester, const _SheetHost(), overrides: [priceWatchRepositoryProvider.overrideWithValue(repo)]);
      await tester.tap(find.text('Open'));
      await _settle(tester);

      expect(find.text('Price alert'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '5% lower')).selected, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      await tester.tap(find.text('Stop watching'));
      await _settle(tester);
      await tester.tap(find.descendant(of: find.byType(ConfirmDialog), matching: find.text('Stop watching')));
      await _settle(tester);
      expect(repo.removed, [7]);
      expect(find.byType(WatchPriceSheet), findsNothing);
    });
  });

  group('price history card', () {
    Future<void> pumpCard(WidgetTester tester, Map<String, dynamic> history, {_FakeWatchRepo? repo, double scale = 1}) => _pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PriceHistoryCard(product: _phone),
        ),
      ),
      scale: scale,
      size: const Size(360, 900),
      overrides: [
        priceHistoryProvider.overrideWith((ref, id) async => PriceHistory.fromJson(history)),
        priceWatchRepositoryProvider.overrideWithValue(repo ?? _FakeWatchRepo()),
      ],
    );

    testWidgets('no history says tracking started today and offers the watch', (tester) async {
      await pumpCard(tester, {'current': {'price': 100000}, 'points': []});
      expect(find.text('Price history'), findsOneWidget);
      expect(find.text('Tracking started today'), findsOneWidget);
      expect(find.byType(PriceHistoryChart), findsNothing);
      expect(find.text('Watch price'), findsOneWidget);
    });

    testWidgets('one flat price is honest about it too', (tester) async {
      await pumpCard(tester, {
        'current': {'price': 100000},
        'points': [
          {'price': 100000, 'recordedAt': '2026-10-01T10:00:00.000Z'},
        ],
      });
      expect(find.textContaining('Tracking since'), findsOneWidget);
      expect(find.textContaining('No price changes yet'), findsOneWidget);
      expect(find.byType(PriceHistoryChart), findsNothing);
    });

    testWidgets('real changes draw the chart with lowest, average and highest', (tester) async {
      await pumpCard(tester, {
        'days': 90,
        'current': {'price': 90000},
        'stats': {'lowest': 80000, 'highest': 100000, 'average': 91500, 'changes': 2},
        'trend': 'down',
        'insight': 'Rs 1,500 below its 90-day average.',
        'points': [
          {'price': 100000, 'recordedAt': '2026-09-01T10:00:00.000Z'},
          {'price': 80000, 'recordedAt': '2026-10-10T10:00:00.000Z'},
          {'price': 90000, 'recordedAt': '2026-10-20T10:00:00.000Z'},
        ],
      });
      expect(find.byType(PriceHistoryChart), findsOneWidget);
      expect(find.text('Lowest'), findsOneWidget);
      expect(find.text('Rs 80,000'), findsOneWidget);
      expect(find.text('Highest'), findsOneWidget);
      expect(find.text('Price is down'), findsOneWidget);
      expect(find.textContaining('below its 90-day average'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrubbing the chart reads a price', (tester) async {
      await pumpCard(tester, {
        'current': {'price': 90000},
        'points': [
          {'price': 100000, 'recordedAt': '2026-09-01T10:00:00.000Z'},
          {'price': 90000, 'recordedAt': '2026-10-20T10:00:00.000Z'},
        ],
      });
      expect(find.textContaining('Last '), findsOneWidget);
      // press near the start of the chart: the first price is in force
      final gesture = await tester.startGesture(tester.getTopLeft(find.byType(PriceHistoryChart)) + const Offset(20, 60));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('· Rs 100,000'), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('· Rs 100,000'), findsNothing);
    });

    testWidgets('when already watching, shows the target and an edit action', (tester) async {
      final repo = _FakeWatchRepo(initial: [_watch(target: 95000)]);
      await pumpCard(tester, {'current': {'price': 100000}, 'points': []}, repo: repo);
      expect(find.text('Watching · target Rs 95,000'), findsOneWidget);
      expect(find.text('Edit price alert'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits at 320 px, text scale $scale', (tester) async {
        await _pump(
          tester,
          Scaffold(
            body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: PriceHistoryCard(product: _phone)),
          ),
          scale: scale,
          size: const Size(320, 800),
          overrides: [
            priceHistoryProvider.overrideWith(
              (ref, id) async => PriceHistory.fromJson({
                'current': {'price': 90000},
                'stats': {'lowest': 80000, 'highest': 100000, 'average': 91500},
                'trend': 'down',
                'insight': 'Rs 1,500 below its 90-day average.',
                'points': [
                  {'price': 100000, 'recordedAt': '2026-09-01T10:00:00.000Z'},
                  {'price': 80000, 'recordedAt': '2026-10-10T10:00:00.000Z'},
                ],
              }),
            ),
            priceWatchRepositoryProvider.overrideWithValue(_FakeWatchRepo()),
          ],
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('wishlist and price alerts', () {
    testWidgets('a watched wishlist tile shows "Watching · target Rs X"', (tester) async {
      final repo = _FakeWatchRepo(initial: [_watch(target: 95000)]);
      await _pump(
        tester,
        const Scaffold(body: Column(children: [PriceWatchBadge(product: _phone)])),
        overrides: [priceWatchRepositoryProvider.overrideWithValue(repo)],
      );
      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('target Rs 95,000'), findsOneWidget);
    });

    testWidgets('an unwatched wishlist tile offers to watch', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: Column(children: [PriceWatchBadge(product: _phone)])),
        overrides: [priceWatchRepositoryProvider.overrideWithValue(_FakeWatchRepo())],
      );
      expect(find.text('Watch price'), findsOneWidget);
      expect(find.text('Watching'), findsNothing);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('the wishlist grid fits at 360 px, text scale $scale', (tester) async {
        final repo = _FakeWatchRepo(initial: [_watch(target: 95000)]);
        await _pump(
          tester,
          const WishlistScreen(),
          scale: scale,
          size: const Size(360, 900),
          overrides: [
            priceWatchRepositoryProvider.overrideWithValue(repo),
            wishlistItemsProvider.overrideWith((ref) async => [_phone]),
            wishlistIdsProvider.overrideWith(_Ids.new),
          ],
        );
        expect(find.byTooltip('Price alerts'), findsOneWidget);
        expect(find.textContaining('Zel watches what you save'), findsOneWidget);
        // at large text the grid starts further down: scroll to the tile
        await tester.scrollUntilVisible(find.text('Watching'), 300, scrollable: find.byType(Scrollable).first);
        expect(find.text('Watching'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('price alerts list shows status and removes after confirming', (tester) async {
      final repo = _FakeWatchRepo(initial: [_watch(target: 95000, summary: 'Rs 5,000 above your target of Rs 95,000')]);
      await _pump(
        tester,
        const PriceAlertsScreen(),
        overrides: [priceWatchRepositoryProvider.overrideWithValue(repo)],
      );
      expect(find.text('Galaxy S24'), findsOneWidget);
      expect(find.text('Target Rs 95,000'), findsOneWidget);
      expect(find.textContaining('above your target'), findsOneWidget);
      expect(find.text('Restock alert on'), findsOneWidget);

      await tester.tap(find.text('Stop watching'));
      await _settle(tester);
      await tester.tap(find.descendant(of: find.byType(ConfirmDialog), matching: find.text('Stop watching')));
      await _settle(tester);
      expect(repo.removed, [7]);
      expect(find.text('No price alerts yet'), findsOneWidget);
    });

    testWidgets('price alerts empty state', (tester) async {
      await _pump(
        tester,
        const PriceAlertsScreen(),
        overrides: [priceWatchRepositoryProvider.overrideWithValue(_FakeWatchRepo())],
      );
      expect(find.text('No price alerts yet'), findsOneWidget);
      expect(find.text('Explore products'), findsOneWidget);
    });
  });

  group('notifications', () {
    testWidgets('a price drop shows old → new price and a discount badge', (tester) async {
      final n = AppNotification.fromJson({
        'id': 1,
        'type': 'price_drop',
        'title': 'Price drop: Galaxy S24',
        'body': 'Now Rs 39,999 (was Rs 45,000), 11% lower.',
        'data': {'productId': 7, 'oldPrice': 45000, 'newPrice': 39999, 'dropPercent': 11.13, 'event': 'price_drop'},
        'createdAt': DateTime.now().toIso8601String(),
      });
      final restock = AppNotification.fromJson({
        'id': 2,
        'type': 'restock',
        'title': 'Back in stock: Galaxy S24',
        'body': 'Available again at Rs 100,000.',
        'data': {'productId': 7, 'oldPrice': 100000, 'newPrice': 100000, 'event': 'restock'},
        'createdAt': DateTime.now().toIso8601String(),
      });
      await _pump(
        tester,
        const NotificationsScreen(),
        overrides: [notificationsRepositoryProvider.overrideWithValue(_FakeNotifications([n, restock]))],
      );
      expect(find.text('Price drop: Galaxy S24'), findsOneWidget);
      expect(find.text('Rs 45,000'), findsOneWidget);
      expect(find.text('Rs 39,999'), findsOneWidget);
      expect(find.text('-11%'), findsOneWidget);
      // a restock without a price change has no old → new line
      expect(find.text('Back in stock: Galaxy S24'), findsOneWidget);
      expect(find.text('Rs 100,000'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('complete the look', () {
    final look = CompleteLook.fromJson({
      'kind': 'outfit',
      'title': 'Complete the look',
      'look': [
        {'role': 'Shoes', 'product': _card(21, 'Black heels', 8000, 'womens-shoes', reasons: ['Black goes with red']), 'alternatives': []},
        {'role': 'Bag', 'product': _card(22, 'Gold clutch', 4000, 'womens-bags', reasons: ['Gold adds a pop of colour']), 'alternatives': []},
        {'role': 'Jewellery', 'product': _card(23, 'Pearl earrings', 1500, 'womens-jewellery'), 'alternatives': []},
      ],
      'palette': {'tip': 'Red works with neutrals.'},
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('shows roles, reasons and the whole look at 320 px, text scale $scale', (tester) async {
        await _pump(
          tester,
          Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(20),
              children: const [CompleteTheLookSection(product: _dress, departmentSlug: 'fashion')],
            ),
          ),
          scale: scale,
          size: const Size(320, 1000),
          overrides: [completeLookProvider.overrideWith((ref, id) async => look)],
        );
        expect(find.text('Complete the look'), findsOneWidget);
        expect(find.text('Shoes'), findsOneWidget);
        expect(find.text('Bag'), findsOneWidget);
        expect(find.text('Jewellery'), findsOneWidget);
        expect(find.text('Red works with neutrals.'), findsOneWidget);
        expect(find.text('Add the look'), findsOneWidget);
        // the dress plus three pieces
        expect(find.textContaining('4 pieces · Rs 33,500'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('is hidden for non-fashion products and for complementary fallbacks', (tester) async {
      await _pump(
        tester,
        const Scaffold(body: CompleteTheLookSection(product: _phone, departmentSlug: 'electronics')),
        overrides: [completeLookProvider.overrideWith((ref, id) async => look)],
      );
      expect(find.text('Complete the look'), findsNothing);

      await _pump(
        tester,
        const Scaffold(body: CompleteTheLookSection(product: _dress, departmentSlug: 'fashion')),
        overrides: [
          completeLookProvider.overrideWith(
            (ref, id) async => CompleteLook.fromJson({'kind': 'complementary', 'products': [_card(1, 'Case', 10, 'mobile-accessories')]}),
          ),
        ],
      );
      expect(find.text('Complete the look'), findsNothing);
    });
  });

  group('spec explainer', () {
    final data = SpecExplainer.fromJson({
      'product': {'id': 7, 'title': 'Galaxy S24'},
      'whoFor': ['everyday users'],
      'summary': 'This phone suits everyday users.',
      'specs': [
        {'key': 'RAM', 'value': '8 GB', 'meaning': 'Keeps many apps open.', 'level': 4, 'levelLabel': 'Great', 'scale': 'Multitasking'},
        {'key': 'Weight', 'value': '200 g', 'meaning': 'Easy to carry.'},
        {'key': 'Storage', 'value': '64 GB', 'meaning': 'Fills up fast.', 'level': 2, 'scale': 'Space'},
      ],
      'others': [
        {'key': 'Colour', 'value': 'Blue'},
      ],
    });

    testWidgets('shows who it is for and each spec in plain words with a level bar', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SpecExplainerBody(data: data))));
      expect(find.text("Who it's for"), findsOneWidget);
      expect(find.text('This phone suits everyday users.'), findsOneWidget);
      expect(find.text('everyday users'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('8 GB'), findsOneWidget);
      expect(find.text('Keeps many apps open.'), findsOneWidget);
      expect(find.text('Great · 4/5'), findsOneWidget);
      expect(find.text('Fair · 2/5'), findsOneWidget);
      // the unrated spec has words but no bar
      expect(find.text('Easy to carry.'), findsOneWidget);
      expect(find.byType(SpecLevelBar), findsNWidgets(2));
      expect(find.bySemanticsLabel('Multitasking: Great, level 4 of 5'), findsOneWidget);
      expect(find.text('Also listed'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an empty explanation says so', (tester) async {
      await _pump(tester, Scaffold(body: SpecExplainerBody(data: SpecExplainer.fromJson({'specs': []}))));
      expect(find.text('Nothing to explain yet'), findsOneWidget);
    });

    testWidgets('the chat card opens the full sheet', (tester) async {
      await _pump(tester, Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: SpecExplainerCard(data: data))));
      expect(find.text('Specs, explained'), findsOneWidget);
      expect(find.text('See all 3 specs'), findsOneWidget);
      await tester.tap(find.text('See all 3 specs'));
      await _settle(tester);
      expect(find.text('Explain these specs'), findsOneWidget);
      expect(find.text('Spec by spec'), findsOneWidget);
    });
  });

  group('compare v2', () {
    CompareResult result({bool forYou = false}) => CompareResult.fromJson({
      'products': [_card(1, 'Phone A', 50000, 'smartphones'), _card(2, 'Phone B', 70000, 'smartphones')],
      'rows': [
        {'label': 'Price', 'values': ['Rs 50,000', 'Rs 70,000'], 'bestIndex': 0, 'differs': true},
        {'label': 'Brand', 'values': ['Acme', 'Acme'], 'bestIndex': null, 'differs': false},
        {'label': 'Screen', 'values': ['6 in', '7 in'], 'bestIndex': 1, 'differs': true},
      ],
      'verdict': {'summary': 'Phone A is cheaper.', 'picks': []},
      'prosCons': [
        {'productId': 1, 'pros': ['Cheapest of the 2'], 'cons': <String>[]},
        {'productId': 2, 'pros': ['Bigger screen'], 'cons': ['Most expensive at Rs 70,000']},
      ],
      if (forYou) 'forYou': {'productId': 2, 'need': 'Gaming', 'matched': true, 'reason': 'For gaming, Phone B is the better fit.'},
    });

    testWidgets('only show differences hides identical rows', (tester) async {
      await _pump(
        tester,
        const CompareScreen(productIds: [1, 2]),
        overrides: [compareProvider.overrideWith((ref, key) async => result())],
      );
      expect(find.text('BRAND'), findsOneWidget);
      expect(find.textContaining('2 of 3 rows differ'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await _settle(tester);
      expect(find.text('BRAND'), findsNothing);
      expect(find.text('PRICE'), findsOneWidget);
      expect(find.text('SCREEN'), findsOneWidget);
    });

    testWidgets('a need re-queries with it and highlights Best for you with the reason', (tester) async {
      final keys = <String>[];
      await _pump(
        tester,
        const CompareScreen(productIds: [1, 2]),
        overrides: [
          compareProvider.overrideWith((ref, key) async {
            keys.add(key);
            return result(forYou: key.contains('|'));
          }),
        ],
      );
      expect(keys, ['1,2']);
      expect(find.text('What do you need it for?'), findsOneWidget);
      expect(find.text('Best for you'), findsNothing);

      await tester.tap(find.text('Gaming'));
      await _settle(tester);
      expect(keys, ['1,2', '1,2|Gaming']);
      expect(find.text('Best for "Gaming"'), findsOneWidget);
      expect(find.textContaining('Phone B is the better fit'), findsOneWidget);
      // the winning column is labelled in the pinned header
      expect(find.text('Best for you'), findsWidgets);
      expect(find.text('Picked for "Gaming"'), findsOneWidget);

      await tester.tap(find.text('Clear'));
      await _settle(tester);
      expect(keys.last, '1,2');
      expect(find.text('Best for "Gaming"'), findsNothing);

      // pros and cons sit below the table
      await tester.scrollUntilVisible(find.text('Pros and cons'), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Cheapest of the 2'), findsOneWidget);
      expect(find.text('Most expensive at Rs 70,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits at 320 px, text scale $scale', (tester) async {
        await _pump(
          tester,
          const CompareScreen(productIds: [1, 2]),
          scale: scale,
          size: const Size(320, 800),
          overrides: [compareProvider.overrideWith((ref, key) async => result(forYou: true))],
        );
        expect(find.text('What do you need it for?'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('typing a need and asking Zel works', (tester) async {
      final keys = <String>[];
      await _pump(
        tester,
        const CompareScreen(productIds: [1, 2]),
        overrides: [
          compareProvider.overrideWith((ref, key) async {
            keys.add(key);
            return result(forYou: key.contains('|'));
          }),
        ],
      );
      await tester.enterText(find.byType(TextField), 'a gift for my mom');
      await tester.tap(find.text('Ask Zel'));
      await _settle(tester);
      expect(keys.last, '1,2|a gift for my mom');
    });

    testWidgets('extras render alone too', (tester) async {
      String? submitted;
      var cleared = false;
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: CompareNeedField(need: 'travel', busy: false, onSubmit: (v) => submitted = v, onClear: () => cleared = true),
          ),
        ),
      );
      expect(find.text('Picked for "travel"'), findsOneWidget);
      await tester.tap(find.text('Work'));
      expect(submitted, 'Work');
      await tester.tap(find.text('Clear'));
      expect(cleared, isTrue);
    });

    testWidgets('the differences toggle reports its value', (tester) async {
      bool? value;
      await _pump(
        tester,
        Scaffold(body: DifferencesToggle(value: false, onChanged: (v) => value = v, differing: 3, total: 3)),
      );
      expect(find.text('Every row is different'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      expect(value, isTrue);
    });
  });

  group('gift finder', () {
    testWidgets('walks the steps with smart defaults and shows a curated collection', (tester) async {
      final ai = _FakeGiftAi();
      await _pump(tester, const GiftFinderScreen(), overrides: [aiRepositoryProvider.overrideWithValue(ai)]);

      expect(find.text('Who is it for?'), findsOneWidget);
      // "Next" waits for a recipient
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNull);
      await tester.tap(find.text('Mom'));
      await _settle(tester);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      expect(find.text('What is the occasion?'), findsOneWidget);
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Birthday')).selected, isTrue);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      expect(find.text('How much would you like to spend?'), findsOneWidget);
      expect(find.text('Up to Rs 10,000'), findsOneWidget);
      await tester.tap(find.text('Next'));
      await _settle(tester);

      expect(find.text('What are they into?'), findsOneWidget);
      // gifts for a mum lead with jewellery
      expect(find.textContaining('Popular picks for your mom'), findsOneWidget);
      await tester.tap(find.text('Jewellery'));
      await tester.pump();
      await tester.tap(find.text('Find gifts'));
      await _settle(tester);

      expect(ai.calls.single, {'recipient': 'mom', 'occasion': 'birthday', 'budget': 10000, 'interests': ['jewellery']});
      expect(find.text('Birthday gifts for your mom under Rs 10K'), findsOneWidget);
      expect(find.text('A curated mix of jewellery.'), findsOneWidget);
      expect(find.text('Gold ring'), findsOneWidget);
      expect(find.text('Within your Rs 10,000 budget'), findsOneWidget);
      expect(find.text('Rose perfume'), findsOneWidget);
      expect(find.text('Ask Zel instead'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a typed recipient counts and fits at 320 px, text scale 2.0', (tester) async {
      await _pump(
        tester,
        const GiftFinderScreen(),
        scale: 2,
        size: const Size(320, 700),
        overrides: [aiRepositoryProvider.overrideWithValue(_FakeGiftAi())],
      );
      await tester.enterText(find.byType(TextField), 'neighbour');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('shopping memory screen', () {
    ShoppingMemory memory({bool enabled = true}) => ShoppingMemory.fromJson({
      'enabled': enabled,
      'summary': ['You browse mostly Smartphones.', 'Recent searches: "gaming laptop".'],
      'topCategories': [
        {'name': 'Smartphones', 'share': 0.62},
      ],
      'topBrands': [
        {'name': 'Apple', 'share': 0.5},
      ],
      'budgetBand': {'label': 'Rs 4,000 to Rs 80,000'},
      'recentSearches': ['gaming laptop'],
      'counts': {'interactions': 14, 'searches': 3, 'chats': 1},
    });

    testWidgets('lists what Zel remembers and pauses memory with the switch', (tester) async {
      final repo = _FakeMemoryRepo(memory());
      await _pump(tester, const ShoppingMemoryScreen(), overrides: [memoryRepositoryProvider.overrideWithValue(repo)]);
      expect(find.text('What Zel remembers'), findsOneWidget);
      expect(find.text('You browse mostly Smartphones.'), findsOneWidget);
      expect(find.text('Rs 4,000 to Rs 80,000'), findsOneWidget);
      expect(find.text('gaming laptop'), findsOneWidget);
      expect(find.textContaining('On. Zel keeps learning'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await _settle(tester);
      expect(repo.enabledCalls, [false]);
      expect(find.textContaining('Paused'), findsOneWidget);
    });

    testWidgets('forget everything asks first, then clears', (tester) async {
      final repo = _FakeMemoryRepo(memory());
      await _pump(tester, const ShoppingMemoryScreen(), overrides: [memoryRepositoryProvider.overrideWithValue(repo)]);

      await tester.ensureVisible(find.text('Forget everything'));
      await tester.pump();
      await tester.tap(find.text('Forget everything'));
      await _settle(tester);
      expect(find.byType(ConfirmDialog), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);
      expect(repo.forgot, 0);

      await tester.tap(find.descendant(of: find.byType(ConfirmDialog), matching: find.text('Forget everything')));
      await _settle(tester);
      expect(repo.forgot, 1);
      expect(find.text('Nothing remembered yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty memory has nothing to forget', (tester) async {
      final repo = _FakeMemoryRepo(const ShoppingMemory());
      await _pump(tester, const ShoppingMemoryScreen(), overrides: [memoryRepositoryProvider.overrideWithValue(repo)]);
      expect(find.text('Nothing remembered yet'), findsOneWidget);
      await tester.ensureVisible(find.text('Forget everything'));
      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Forget everything')).onPressed, isNull);
    });
  });

  group('voice input', () {
    testWidgets('the mic explains itself instead of crashing when recognition is unavailable', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(onSend: (_) {}, sending: false),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Voice input'));
      // the platform call to the (missing) plugin completes on the real event loop
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await _settle(tester);
      // no plugin in tests (and no Web Speech API in some browsers): a friendly message, no exception
      expect(find.textContaining("Voice input isn't"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('snap & find cropper', () {
    Future<ui.Image> photo(WidgetTester tester) async {
      final image = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 40, 20), Paint()..color = const Color(0xFF3366CC));
        final picture = recorder.endRecording();
        final out = await picture.toImage(40, 20);
        picture.dispose();
        return out;
      });
      addTearDown(image!.dispose);
      return image;
    }

    Future<List<Rect>> pumpCropper(WidgetTester tester, ui.Image image) async {
      final changes = <Rect>[];
      var rect = kDefaultCrop;
      await _pump(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            // the photo is 2:1, so it is shown 400 x 200
            child: SizedBox(
              width: 400,
              height: 200,
              child: StatefulBuilder(
                builder: (context, setState) => ImageCropper(
                  image: image,
                  rect: rect,
                  onChanged: (r) {
                    changes.add(r);
                    setState(() => rect = r);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      return changes;
    }

    testWidgets('dragging inside moves the box and keeps it on the photo', (tester) async {
      final image = await photo(tester);
      final changes = await pumpCropper(tester, image);
      await tester.drag(find.byType(ImageCropper), const Offset(120, 0));
      await tester.pump();
      expect(changes, isNotEmpty);
      final last = changes.last;
      expect(last.width, closeTo(0.8, 0.001));
      // pushed against the right edge, not past it
      expect(last.right, closeTo(1.0, 0.001));
      expect(last.left, closeTo(0.2, 0.001));
    });

    testWidgets('dragging a corner resizes it', (tester) async {
      final image = await photo(tester);
      final changes = await pumpCropper(tester, image);
      final topLeft = tester.getTopLeft(find.byType(ImageCropper));
      // the photo is shown 400 x 200; the default box's bottom-right corner is at (360, 180)
      await tester.dragFrom(topLeft + const Offset(360, 180), const Offset(-40, -40));
      await tester.pump();
      final last = changes.last;
      expect(last.left, closeTo(0.1, 0.001));
      expect(last.top, closeTo(0.1, 0.001));
      expect(last.right, closeTo(0.8, 0.001));
      expect(last.bottom, closeTo(0.7, 0.001));
    });

    testWidgets('dragging outside the box draws a new one, never smaller than the minimum', (tester) async {
      final image = await photo(tester);
      final changes = await pumpCropper(tester, image);
      final topLeft = tester.getTopLeft(find.byType(ImageCropper));
      await tester.dragFrom(topLeft + const Offset(4, 4), const Offset(100, 60));
      await tester.pump();
      final last = changes.last;
      expect(last.left, closeTo(0.01, 0.001));
      expect(last.right, closeTo(0.26, 0.001));
      for (final r in changes) {
        expect(r.width, greaterThanOrEqualTo(kMinCropFraction));
        expect(r.height, greaterThanOrEqualTo(kMinCropFraction));
      }
    });
  });
}
