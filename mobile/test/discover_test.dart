import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/features/discover/data/deck_model.dart';
import 'package:cartwise/features/discover/data/discover_models.dart';
import 'package:cartwise/features/discover/presentation/reels_viewer.dart';
import 'package:cartwise/features/discover/presentation/widgets/swipe_deck.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

ProductSummary _p(int id, {String cat = 'Laptops', double price = 1000, String? brand}) => ProductSummary(
  id: id,
  title: 'Product $id',
  slug: 'product-$id',
  price: price,
  brand: brand,
  category: NamedRef(id: cat.hashCode, name: cat, slug: cat.toLowerCase()),
);

void main() {
  group('DeckLogic', () {
    test('initial deck drops duplicates and empty ids', () {
      final s = DeckState.initial([_p(1), _p(2), _p(1), _p(0)]);
      expect(s.queue.map((c) => c.id), [1, 2]);
      expect(s.top!.id, 1);
      expect(s.canUndo, isFalse);
    });

    test('swipe moves the top card into history; undo puts it back', () {
      var s = DeckState.initial([_p(1), _p(2), _p(3)]);
      s = DeckLogic.swipe(s, SwipeAction.like);
      s = DeckLogic.swipe(s, SwipeAction.pass);
      expect(s.top!.id, 3);
      expect(s.count(SwipeAction.like), 1);
      expect(s.count(SwipeAction.pass), 1);

      s = s.copyWith(serverTaste: () => const TasteProfile(confidence: 0.9));
      s = DeckLogic.undo(s);
      expect(s.top!.id, 2, reason: 'the passed card is back on top');
      expect(s.history.map((r) => r.card.id), [1]);
      expect(s.serverTaste!.confidence, 0.9, reason: 'the API has no un-swipe, so its taste is kept');

      s = DeckLogic.undo(DeckLogic.undo(s));
      expect(s.queue.map((c) => c.id), [1, 2, 3]);
      expect(DeckLogic.swipe(const DeckState(), SwipeAction.like).isEmpty, isTrue);
    });

    test('inject puts "because you liked" cards right behind the top card, skipping known ones', () {
      var s = DeckState.initial([_p(1), _p(2), _p(3)]);
      s = DeckLogic.swipe(s, SwipeAction.like); // 1 liked, top = 2
      s = DeckLogic.inject(s, [_p(1), _p(3), _p(7), _p(8)], reason: 'Because you liked Product 1');
      expect(s.queue.map((c) => c.id), [2, 7, 8, 3]);
      expect(s.queue[1].reason, 'Because you liked Product 1');
      expect(s.queue.first.reason, isNull);

      s = DeckLogic.append(s, [_p(8), _p(9)]);
      expect(s.queue.map((c) => c.id), [2, 7, 8, 3, 9]);
    });

    test('decide: distance or velocity commits, otherwise springs back', () {
      const card = Size(300, 420);
      expect(DeckLogic.decide(const Offset(40, 10), Offset.zero, card), isNull);
      expect(DeckLogic.decide(const Offset(120, 0), Offset.zero, card), SwipeAction.like);
      expect(DeckLogic.decide(const Offset(-120, 30), Offset.zero, card), SwipeAction.pass);
      expect(DeckLogic.decide(const Offset(10, -120), Offset.zero, card), SwipeAction.bag);
      // short but fast flicks
      expect(DeckLogic.decide(const Offset(20, 0), const Offset(1400, 0), card), SwipeAction.like);
      expect(DeckLogic.decide(const Offset(-20, 0), const Offset(-1400, 0), card), SwipeAction.pass);
      expect(DeckLogic.decide(const Offset(0, -20), const Offset(0, -1400), card), SwipeAction.bag);
      // a mostly-horizontal drag that also moved up is still a like
      expect(DeckLogic.decide(const Offset(200, -150), Offset.zero, card), SwipeAction.like);
      // a fling against the drag direction does not commit
      expect(DeckLogic.decide(const Offset(-30, 0), const Offset(1400, 0), card), isNull);
    });

    test('stamp strength grows to 1 at the threshold', () {
      const card = Size(300, 420);
      final (none, zero) = DeckLogic.stamp(Offset.zero, card);
      expect(none, isNull);
      expect(zero, 0);
      final (like, half) = DeckLogic.stamp(const Offset(45, 0), card);
      expect(like, SwipeAction.like);
      expect(half, closeTo(0.5, 0.01));
      final (bag, full) = DeckLogic.stamp(const Offset(0, -200), card);
      expect(bag, SwipeAction.bag);
      expect(full, 1);
    });

    test('local taste: shares, price appetite, confidence and signals', () {
      var s = DeckState.initial([
        _p(1, cat: 'Laptops', price: 100000, brand: 'Asus'),
        _p(2, cat: 'Laptops', price: 140000, brand: 'Asus'),
        _p(3, cat: 'Headphones', price: 20000),
        _p(4, cat: 'Shoes', price: 9000),
      ]);
      s = DeckLogic.swipe(s, SwipeAction.like);
      s = DeckLogic.swipe(s, SwipeAction.bag);
      s = DeckLogic.swipe(s, SwipeAction.like);
      s = DeckLogic.swipe(s, SwipeAction.pass);

      final taste = s.taste;
      expect(taste.categories.first.name, 'Laptops');
      expect(taste.categories.fold(0.0, (a, c) => a + c.share), closeTo(1, 1e-9));
      expect(taste.categories.any((c) => c.name == 'Shoes'), isFalse, reason: 'passes do not count');
      expect(taste.priceAppetite.min, 20000);
      expect(taste.priceAppetite.max, 140000);
      expect(taste.priceAppetite.avg, closeTo(86666.67, 0.01));
      expect(taste.topSignals, contains('Comes back to Asus'));

      final fewer = DeckLogic.localTaste(s.history.take(1).toList());
      expect(taste.confidence, greaterThan(fewer.confidence));
      expect(DeckLogic.localTaste(const []).isEmpty, isTrue);
    });

    test('reasonFor shortens long titles', () {
      final long = ProductSummary(id: 1, title: 'A' * 40, slug: 'a', price: 1);
      expect(DeckLogic.reasonFor(SwipeAction.like, long).length, lessThan(50));
      expect(DeckLogic.reasonFor(SwipeAction.bag, _p(2)), 'Goes with Product 2');
    });
  });

  group('API parsing (lenient)', () {
    test('taste accepts percents, objects and missing fields', () {
      final t = TasteProfile.fromJson({
        'categories': [
          {'name': 'Laptops', 'share': 60},
          {'name': 'Audio', 'share': 0.4, 'slug': 'audio'},
        ],
        'priceAppetite': {'min': '1000', 'max': 50000, 'avg': 20000},
        'confidence': 72,
        'topSignals': ['Into laptops', {'label': 'Likes Asus'}],
      });
      expect(t.categories.first.share, closeTo(0.6, 1e-9));
      expect(t.categories.last.slug, 'audio');
      expect(t.priceAppetite.min, 1000);
      expect(t.confidence, closeTo(0.72, 1e-9));
      expect(t.topSignals, ['Into laptops', 'Likes Asus']);
      expect(TasteProfile.fromJson(null).isEmpty, isTrue);
    });

    test('swipe response and reels', () {
      final r = SwipeResponse.fromJson({
        'taste': {'confidence': 0.3},
        'next': [
          {'id': 5, 'title': 'X', 'slug': 'x', 'price': 10},
          {'title': 'no id'},
        ],
      });
      expect(r.taste!.confidence, 0.3);
      expect(r.next.map((p) => p.id), [5]);

      final reel = DiscoverReel.fromJson({
        'department': {'name': 'Electronics', 'slug': 'electronics'},
        'headline': 'Top tech',
        'products': [
          {'id': 1, 'title': 'A', 'slug': 'a', 'price': 1},
        ],
      });
      expect(reel.department, 'Electronics');
      expect(reel.slug, 'electronics');
      expect(reel.products, hasLength(1));
    });
  });

  group('ReelsCursor', () {
    const lengths = [2, 0, 3];

    test('next walks products, skips empty stories and ends with null', () {
      var c = const ReelsCursor(0, 0);
      c = c.next(lengths)!;
      expect(c, const ReelsCursor(0, 1));
      c = c.next(lengths)!;
      expect(c, const ReelsCursor(2, 0), reason: 'story 1 is empty');
      c = c.next(lengths)!.next(lengths)!;
      expect(c, const ReelsCursor(2, 2));
      expect(c.next(lengths), isNull);
    });

    test('previous steps back, then to the previous story start, then restarts', () {
      expect(const ReelsCursor(2, 1).previous(lengths), const ReelsCursor(2, 0));
      expect(const ReelsCursor(2, 0).previous(lengths), const ReelsCursor(0, 0));
      expect(const ReelsCursor(0, 0).previous(lengths), const ReelsCursor(0, 0));
    });
  });

  group('SwipeDeck', () {
    setUpAll(() => AppTheme.useGoogleFonts = false);

    testWidgets('drag past the threshold commits, a short drag springs back, buttons fling', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final swiped = <SwipeAction>[];
      final key = GlobalKey<SwipeDeckState>();
      var cards = [DeckCard(_p(1)), DeckCard(_p(2)), DeckCard(_p(3))];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  height: 420,
                  child: StatefulBuilder(
                    builder: (context, setState) => SwipeDeck(
                      key: key,
                      cards: cards,
                      onOpen: (_) {},
                      onSwiped: (a) => setState(() {
                        swiped.add(a);
                        cards = cards.sublist(1);
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // a short drag springs back
      await tester.drag(find.text('Product 1'), const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(swiped, isEmpty);

      // past the threshold: like
      await tester.drag(find.text('Product 1'), const Offset(200, 0));
      await tester.pumpAndSettle();
      expect(swiped, [SwipeAction.like]);
      expect(find.text('Product 1'), findsNothing);

      // up: bag
      await tester.drag(find.text('Product 2'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(swiped, [SwipeAction.like, SwipeAction.bag]);

      // programmatic (buttons / keyboard)
      key.currentState!.fling(SwipeAction.pass);
      await tester.pumpAndSettle();
      expect(swiped.last, SwipeAction.pass);
      expect(tester.takeException(), isNull);
    });
  });

  group('ReelsViewer', () {
    setUpAll(() => AppTheme.useGoogleFonts = false);

    testWidgets('tap right/left moves through products and the timer rolls into the next story', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(400, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final reels = [
        DiscoverReel(department: 'Electronics', slug: 'electronics', headline: 'Tech', products: [_p(1), _p(2)]),
        DiscoverReel(department: 'Fashion', slug: 'fashion', headline: 'Style', products: [_p(3)]),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: ReelsViewer(reels: reels, segment: const Duration(seconds: 2)),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Product 1'), findsOneWidget);
      expect(find.text('Electronics'), findsOneWidget);

      await tester.tapAt(const Offset(330, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Product 2'), findsOneWidget);
      expect(find.text('Product 1'), findsNothing);

      await tester.tapAt(const Offset(40, 300));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Product 1'), findsOneWidget);

      // let the segments run out: product 2, then the Fashion story
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Product 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      // the page animation needs a couple of frames to start, then ~360 ms
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('Fashion'), findsOneWidget);
      expect(find.text('Product 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
