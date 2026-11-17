import 'dart:ui' as ui;

import 'package:cartwise/features/ai/data/ai_repository.dart';
import 'package:cartwise/features/ai/data/models/ai_models.dart';
import 'package:cartwise/features/ai/data/models/shopping_models.dart';
import 'package:cartwise/features/ai/presentation/widgets/image_cropper.dart';
import 'package:cartwise/features/ai/providers/ai_providers.dart';
import 'package:cartwise/features/ai/providers/gift_finder_controller.dart';
import 'package:cartwise/features/assistant/data/chat_models.dart';
import 'package:cartwise/features/assistant/data/speech_text.dart';
import 'package:cartwise/features/notifications/providers/notifications_providers.dart';
import 'package:cartwise/features/product/data/models/price_history.dart';
import 'package:cartwise/features/profile/data/memory_models.dart';
import 'package:cartwise/features/wishlist/data/price_watch_models.dart';
import 'package:cartwise/core/network/api_client.dart';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _card(int id, {String title = 'Item', double price = 1000, String slug = 'tops', Map<String, dynamic>? match}) => {
  'id': id,
  'title': title,
  'slug': 'p-$id',
  'category': {'id': 1, 'name': 'Category', 'slug': slug},
  'price': price,
  'stock': 5,
  'inStock': true,
  'match': ?match,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('price watch', () {
    test('PriceWatch parses the documented shape', () {
      final w = PriceWatch.fromJson({
        'id': 3,
        'product': _card(9, title: 'Phone', price: 47999),
        'targetPrice': 45000,
        'notifyRestock': true,
        'initialPrice': 49999,
        'createdAt': '2026-11-01T10:00:00.000Z',
        'lastNotifiedAt': null,
        'status': {
          'currentPrice': 47999,
          'inStock': true,
          'targetReached': false,
          'dropSinceWatch': 2000,
          'summary': 'Rs 2,999 above your target of Rs 45,000',
        },
      });
      expect(w.productId, 9);
      expect(w.hasTarget, isTrue);
      expect(w.badgeLabel, 'Watching · target Rs 45,000');
      expect(w.targetLabel, 'Target Rs 45,000');
      expect(w.status.dropSinceWatch, 2000);
      expect(w.status.summary, contains('above your target'));
      expect(w.createdAt, isNotNull);
      expect(w.lastNotifiedAt, isNull);
    });

    test('a null target means any drop; decimals and strings are tolerated', () {
      final w = PriceWatch.fromJson({'id': '4', 'product': _card(2), 'targetPrice': null, 'notifyRestock': 'false'});
      expect(w.id, 4);
      expect(w.hasTarget, isFalse);
      expect(w.notifyRestock, isFalse);
      expect(w.badgeLabel, 'Watching · any drop');
      expect(w.currentPrice, 1000);
    });

    test('target presets are always below today\'s price', () {
      expect(WatchTarget.forKind(WatchTargetKind.anyDrop, 1000), isNull);
      expect(WatchTarget.forKind(WatchTargetKind.percent5, 1000), 950);
      expect(WatchTarget.forKind(WatchTargetKind.percent10, 279999), 251999);
      expect(WatchTarget.forKind(WatchTargetKind.percent10, 5)!, lessThan(5));
      expect(WatchTarget.forKind(WatchTargetKind.percent5, 1), isNull);
      expect(WatchTarget.forKind(WatchTargetKind.custom, 1000, custom: 800), 800);
    });

    test('an existing target maps back to its chip', () {
      expect(WatchTarget.kindFor(null, 1000), WatchTargetKind.anyDrop);
      expect(WatchTarget.kindFor(950, 1000), WatchTargetKind.percent5);
      expect(WatchTarget.kindFor(900, 1000), WatchTargetKind.percent10);
      expect(WatchTarget.kindFor(777, 1000), WatchTargetKind.custom);
    });

    test('custom targets are parsed and validated', () {
      expect(WatchTarget.parse('Rs 41,500'), 41500);
      expect(WatchTarget.parse('abc'), isNull);
      expect(WatchTarget.validateCustom('', 1000), 'Enter an amount');
      expect(WatchTarget.validateCustom('0', 1000), contains('above Rs 0'));
      expect(WatchTarget.validateCustom('1000', 1000), contains('below today'));
      expect(WatchTarget.validateCustom('999', 1000), isNull);
      expect(WatchTarget.percentBelow(900, 1000), '10% below today\'s price');
      expect(WatchTarget.percentBelow(1000, 1000), isNull);
    });
  });

  group('price history', () {
    final json = {
      'productId': 9,
      'currency': 'PKR',
      'days': 90,
      'current': {'price': 90, 'compareAtPrice': 100, 'inStock': true},
      'stats': {'lowest': 80, 'highest': 100, 'average': 91.5, 'changes': 2},
      'trend': 'down',
      'insight': 'Rs 2 below its 90-day average.',
      'points': [
        {'price': 100, 'compareAtPrice': null, 'stock': 5, 'source': 'seed', 'recordedAt': '2026-09-01T10:00:00.000Z'},
        {'price': 80, 'compareAtPrice': 100, 'stock': 5, 'source': 'admin', 'recordedAt': '2026-10-10T10:00:00.000Z'},
        {'price': 90, 'compareAtPrice': 100, 'stock': 5, 'source': 'admin', 'recordedAt': '2026-10-20T10:00:00.000Z'},
      ],
    };

    test('parses stats, trend and points oldest first', () {
      final h = PriceHistory.fromJson(json);
      expect(h.points.length, 3);
      expect(h.points.first.price, 100);
      expect(h.currentPrice, 90);
      expect(h.low, 80);
      expect(h.high, 100);
      expect(h.average, 91.5);
      expect(h.trend, 'down');
      expect(h.insight, contains('average'));
      expect(h.hasChanges, isTrue);
      expect(h.isEmpty, isFalse);
      expect(h.changes, 2);
    });

    test('the series extends the last price to now', () {
      final h = PriceHistory.fromJson(json);
      final now = DateTime.utc(2026, 11, 17);
      final s = h.series(now: now);
      expect(s.length, 4);
      expect(s.last.at, now);
      expect(s.last.price, 90);
    });

    test('unsorted points are ordered by time', () {
      final h = PriceHistory.fromJson({
        'current': {'price': 5},
        'points': [
          {'price': 5, 'recordedAt': '2026-10-20T10:00:00.000Z'},
          {'price': 9, 'recordedAt': '2026-10-01T10:00:00.000Z'},
        ],
      });
      expect(h.points.first.price, 9);
    });

    test('no history is the honest empty state', () {
      final h = PriceHistory.fromJson({'current': {'price': 500}, 'points': []});
      expect(h.isEmpty, isTrue);
      expect(h.hasChanges, isFalse);
      expect(h.series(), isEmpty);
    });

    test('one recorded price and no change has no chart', () {
      final h = PriceHistory.fromJson({
        'current': {'price': 500},
        'points': [
          {'price': 500, 'recordedAt': '2026-10-01T10:00:00.000Z'},
        ],
      });
      expect(h.isEmpty, isFalse);
      expect(h.hasChanges, isFalse);
      expect(h.changes, 0);
    });
  });

  group('complete the look', () {
    test('parses roles, reasons and flat extras without duplicates', () {
      final look = CompleteLook.fromJson({
        'base': _card(1, slug: 'womens-dresses'),
        'kind': 'outfit',
        'title': 'Complete the look: Red dress',
        'look': [
          {
            'role': 'Shoes',
            'category': {'slug': 'womens-shoes', 'name': "Women's Shoes"},
            'product': _card(2, title: 'Heels', price: 8000, slug: 'womens-shoes', match: {'score': 0.9, 'reasons': ['Black goes with red']}),
            'alternatives': [_card(5)],
          },
          {
            'role': 'Bag',
            'category': {'slug': 'womens-bags', 'name': "Women's Bags"},
            'product': _card(3, title: 'Clutch', price: 4000, slug: 'womens-bags'),
            'alternatives': <Map<String, dynamic>>[],
          },
        ],
        'products': [
          _card(2, title: 'Heels', slug: 'womens-shoes'),
          _card(4, title: 'Earrings', price: 1200, slug: 'womens-jewellery'),
        ],
        'palette': {'color': 'Red', 'family': 'colour', 'tip': 'Red works with neutrals.'},
      });
      expect(look.isOutfit, isTrue);
      expect(look.items.map((i) => i.role), ['Shoes', 'Bag', 'Jewellery']);
      expect(look.items.map((i) => i.product.id), [2, 3, 4]);
      expect(look.items.first.product.match!.reasons, ['Black goes with red']);
      expect(look.items.first.alternatives.single.id, 5);
      expect(look.paletteTip, 'Red works with neutrals.');
      expect(look.total, 13200);
    });

    test('a bare list of recommended products works too', () {
      final look = CompleteLook.fromJson([_card(7, slug: 'sunglasses'), _card(8, slug: 'mens-watches')]);
      expect(look.items.map((i) => i.role), ['Sunglasses', 'Watch']);
      expect(look.isOutfit, isTrue);
    });

    test('a complementary fallback is not an outfit', () {
      final look = CompleteLook.fromJson({'kind': 'complementary', 'look': [], 'products': [_card(1)]});
      expect(look.isOutfit, isFalse);
    });

    test('fashion detection uses the department or category', () {
      expect(isFashionProduct(departmentSlug: 'fashion'), isTrue);
      expect(isFashionProduct(categorySlug: 'womens-bags'), isTrue);
      expect(isFashionProduct(departmentSlug: 'electronics', categorySlug: 'laptops'), isFalse);
    });
  });

  group('spec explainer', () {
    final json = {
      'product': {'id': 130, 'title': 'Realme XT', 'category': {'slug': 'smartphones', 'name': 'Smartphones'}, 'kind': 'phone'},
      'overall': {'level': 3.4, 'label': 'Good'},
      'whoFor': ['everyday users', 'social media fans'],
      'summary': 'This phone suits everyday users. Its strongest point is the battery.',
      'specs': [
        {
          'key': 'RAM',
          'value': '8 GB',
          'title': '8 GB RAM: great multitasking',
          'meaning': 'Keeps many apps open.',
          'level': 4,
          'levelLabel': 'Great',
          'scale': 'Multitasking',
        },
        {'key': 'Weight', 'value': '200 g', 'title': 'Light', 'meaning': 'Easy to carry.', 'level': null, 'levelLabel': null, 'scale': null},
        {'key': 'Storage', 'value': '128 GB', 'meaning': 'Room for photos.', 'level': 9},
      ],
      'others': [
        {'key': 'Colour', 'value': 'Blue'},
        {'key': '', 'value': 'x'},
      ],
    };

    test('parses the documented shape', () {
      final e = SpecExplainer.fromJson(json);
      expect(e.productTitle, 'Realme XT');
      expect(e.summary, startsWith('This phone suits'));
      expect(e.whoFor, ['everyday users', 'social media fans']);
      expect(e.specs.length, 3);
      expect(e.specs.first.label, 'RAM');
      expect(e.specs.first.level, 4);
      expect(e.specs.first.levelLabel, 'Great');
      expect(e.specs.first.scale, 'Multitasking');
      expect(e.specs.first.isRated, isTrue);
      expect(e.specs[1].isRated, isFalse);
      // out-of-range levels are clamped
      expect(e.specs[2].level, 5);
      expect(e.others.single.key, 'Colour');
      expect(e.overallLabel, 'Good');
      expect(e.isEmpty, isFalse);
      expect(e.highlights.first.label, 'Storage');
    });

    test('accepts label/whoItsFor as the lead described the contract', () {
      final e = SpecExplainer.fromJson({
        'whoItsFor': 'Great for students.',
        'specs': [
          {'label': 'Battery', 'value': '5000 mAh', 'meaning': 'Two days.', 'level': 5},
        ],
      });
      expect(e.summary, 'Great for students.');
      expect(e.whoFor, isEmpty);
      expect(e.specs.single.label, 'Battery');
      expect(e.specs.single.levelLabel, 'Excellent');
    });

    test('empty data is detected', () {
      expect(SpecExplainer.fromJson({'specs': []}).isEmpty, isTrue);
      expect(SpecExplainer.fromJson(null).isEmpty, isTrue);
    });

    test('a chat reply carries the explainer in meta', () {
      final meta = ChatMeta.fromJson({'intent': 'explain_specs', 'explain': json});
      expect(meta.explain, isNotNull);
      expect(meta.explain!.specs.length, 3);
      expect(ChatMeta.fromJson({'intent': 'greeting'}).explain, isNull);
    });
  });

  group('compare v2', () {
    Map<String, dynamic> compare() => {
      'products': [_card(1, title: 'A'), _card(2, title: 'B')],
      'rows': [
        {'label': 'Price', 'values': ['Rs 10', 'Rs 20'], 'bestIndex': 0, 'differs': true},
        {'label': 'Brand', 'values': ['X', 'X'], 'bestIndex': null, 'differs': false},
        {'label': 'Colour', 'values': ['Black', 'black'], 'bestIndex': null},
        {'label': 'Screen', 'values': ['6 in', '7 in'], 'bestIndex': null},
      ],
      'differencesCount': 2,
      'verdict': {'summary': 'A is cheaper.', 'picks': []},
      'prosCons': [
        {'productId': 1, 'pros': ['Cheapest of the 2 at Rs 10'], 'cons': <String>[]},
        {'productId': 2, 'pros': ['Bigger screen'], 'cons': ['Most expensive at Rs 20']},
      ],
      'forYou': {'productId': 2, 'need': 'gaming', 'matched': true, 'reason': 'For gaming, B is the better fit.', 'scores': []},
    };

    test('rows carry differs, falling back to comparing the values', () {
      final r = CompareResult.fromJson(compare());
      expect(r.rows.map((x) => x.isDifferent), [true, false, false, true]);
      expect(r.differingRows.map((x) => x.label), ['Price', 'Screen']);
    });

    test('pros and cons are keyed by product id', () {
      final r = CompareResult.fromJson(compare());
      expect(r.prosCons[1]!.pros, ['Cheapest of the 2 at Rs 10']);
      expect(r.prosCons[1]!.cons, isEmpty);
      expect(r.prosCons[2]!.cons.single, startsWith('Most expensive'));
    });

    test('pros and cons inside each product work too', () {
      final json = compare()
        ..remove('prosCons')
        ..['products'] = [
          {..._card(1), 'pros': ['Light'], 'cons': <String>[]},
          {..._card(2), 'pros': <String>[], 'cons': ['Heavy']},
        ];
      final r = CompareResult.fromJson(json);
      expect(r.prosCons[1]!.pros, ['Light']);
      expect(r.prosCons[2]!.cons, ['Heavy']);
    });

    test('forYou names the product and the reason', () {
      final r = CompareResult.fromJson(compare());
      expect(r.forYou!.productId, 2);
      expect(r.forYou!.reason, contains('better fit'));
      expect(r.productById(r.forYou!.productId)!.title, 'B');
      expect(CompareResult.fromJson(compare()..remove('forYou')).forYou, isNull);
    });

    test('an older server without v2 fields still parses', () {
      final r = CompareResult.fromJson({
        'products': [_card(1), _card(2)],
        'rows': [
          {'label': 'Price', 'values': ['1', '2'], 'bestIndex': 0},
        ],
        'verdict': {'summary': '', 'picks': []},
      });
      expect(r.prosCons, isEmpty);
      expect(r.forYou, isNull);
      expect(r.rows.single.isDifferent, isTrue);
    });

    test('the provider key carries the need', () {
      expect(compareKey([1, 2]), '1,2');
      expect(compareKey([1, 2], need: '  '), '1,2');
      expect(compareKey([1, 2], need: ' gaming '), '1,2|gaming');
    });
  });

  group('gift finder', () {
    test('parses the documented gift shape (and items as a fallback)', () {
      final g = GiftResult.fromJson({
        'title': 'Birthday gifts for your mom under Rs 10K',
        'note': 'A curated mix of jewellery.',
        'products': [
          _card(1, title: 'Ring', match: {'score': 0.8, 'reasons': ['Within your Rs 10,000 budget']}),
        ],
        'criteria': {'recipient': 'mom'},
        'relaxed': false,
      });
      expect(g.title, startsWith('Birthday gifts'));
      expect(g.note, contains('jewellery'));
      expect(g.products.single.match!.reasons, ['Within your Rs 10,000 budget']);
      expect(g.isEmpty, isFalse);

      final wrapped = GiftResult.fromJson({
        'items': [
          {'product': _card(2), 'score': 0.5, 'reasons': ['Popular pick']},
        ],
      });
      expect(wrapped.products.single.match!.reasons, ['Popular pick']);
      expect(GiftResult.fromJson({'products': []}).isEmpty, isTrue);
    });

    test('the "Ask Zel" prompt reads naturally', () {
      expect(
        giftPrompt(recipient: 'Mom', occasion: 'Birthday', budget: 10000, interests: ['Jewellery', 'Perfumes']),
        'Gift for my mom for birthday under Rs 10,000, they like jewellery and perfumes',
      );
      expect(giftPrompt(recipient: null, occasion: '', budget: 5000), 'Gift for someone under Rs 5,000');
      expect(giftPrompt(recipient: 'Dad', occasion: 'Eid', budget: 3000, interests: ['Watches']), endsWith('they like watches'));
    });

    test('smart defaults follow who the gift is for', () {
      expect(giftDefaultBudget('Kid'), 5000);
      expect(giftDefaultBudget('Wife'), 20000);
      expect(giftDefaultBudget('Friend'), 10000);
      expect(giftInterestsFor('Mom').ordered.first, 'Jewellery');
      expect(giftInterestsFor('Mom').suggested, greaterThan(0));
      expect(giftInterestsFor('Dad').ordered.first, 'Watches');
      expect(giftInterestsFor('Friend').suggested, 0);
      // nothing is dropped or duplicated
      expect(giftInterestsFor('Mom').ordered.toSet(), kGiftInterests.toSet());
      expect(giftInterestsFor('Mom').ordered.length, kGiftInterests.length);
    });
  });

  group('gift finder controller', () {
    ProviderContainer container({GiftResult? result, Object? error}) {
      final c = ProviderContainer(
        overrides: [aiRepositoryProvider.overrideWithValue(_FakeAi(result: result, error: error))],
      );
      addTearDown(c.dispose);
      c.listen(giftFinderProvider, (_, _) {}); // keep the autoDispose state alive
      return c;
    }

    test('walks who → occasion → budget → interests and asks for ideas', () async {
      final fake = _FakeAi(result: const GiftResult(title: 'Ideas', products: []));
      final c = ProviderContainer(overrides: [aiRepositoryProvider.overrideWithValue(fake)]);
      addTearDown(c.dispose);
      c.listen(giftFinderProvider, (_, _) {});
      final ctl = c.read(giftFinderProvider.notifier);

      expect(c.read(giftFinderProvider).canContinue, isFalse);
      ctl.setRecipient('Wife');
      expect(c.read(giftFinderProvider).budget, 20000); // smart default
      await ctl.next();
      expect(c.read(giftFinderProvider).step, GiftStep.occasion);
      ctl.setOccasion('Anniversary');
      await ctl.next();
      ctl.setBudget(7500);
      ctl.setRecipient('Husband'); // a touched budget is not reset
      expect(c.read(giftFinderProvider).budget, 7500);
      await ctl.next();
      expect(c.read(giftFinderProvider).isLastStep, isTrue);
      ctl.toggleInterest('Watches');
      await ctl.next();

      expect(fake.calls.single.recipient, 'husband');
      expect(fake.calls.single.occasion, 'anniversary');
      expect(fake.calls.single.budget, 7500);
      expect(fake.calls.single.interests, ['watches']);
      expect(c.read(giftFinderProvider).result!.value!.title, 'Ideas');
    });

    test('at most four interests can be picked', () {
      final c = container();
      final ctl = c.read(giftFinderProvider.notifier);
      for (final i in ['Fashion', 'Jewellery', 'Perfumes', 'Watches', 'Gaming']) {
        ctl.toggleInterest(i);
      }
      expect(c.read(giftFinderProvider).interests.length, kGiftMaxInterests);
      ctl.toggleInterest('Fashion'); // un-pick still works
      expect(c.read(giftFinderProvider).interests.contains('Fashion'), isFalse);
    });

    test('a failure keeps the brief and can go back or retry', () async {
      final c = container(error: const ApiException('Down', statusCode: 500));
      final ctl = c.read(giftFinderProvider.notifier);
      ctl.setRecipient('Mom');
      await ctl.submit();
      final s = c.read(giftFinderProvider);
      expect(s.result!.hasError, isTrue);
      expect(s.recipient, 'Mom');
      ctl.back();
      expect(c.read(giftFinderProvider).showingResults, isFalse);
      expect(c.read(giftFinderProvider).step, GiftStep.interests);
    });

    test('"Ask Zel instead" uses the current brief', () {
      final c = container();
      final ctl = c.read(giftFinderProvider.notifier);
      ctl.setRecipient('Dad');
      ctl.setOccasion('Eid');
      ctl.setBudget(5000);
      expect(ctl.promptForZel, 'Gift for my dad for eid under Rs 5,000');
    });
  });

  group('shopping memory', () {
    test('parses the documented snapshot', () {
      final m = ShoppingMemory.fromJson({
        'enabled': true,
        'summary': ['You browse mostly Smartphones.', 'Recent searches: "gaming laptop".'],
        'topCategories': [
          {'slug': 'smartphones', 'name': 'Smartphones', 'share': 0.62},
        ],
        'topBrands': [
          {'name': 'Apple', 'share': 50},
        ],
        'budgetBand': {'min': 4000, 'max': 80000, 'avg': 35210, 'label': 'Rs 4,000 to Rs 80,000'},
        'recentSearches': ['gaming laptop'],
        'counts': {'interactions': 14, 'searches': 3, 'chats': 1},
        'lastActivityAt': '2026-11-16T10:00:00.000Z',
      });
      expect(m.enabled, isTrue);
      expect(m.summary.length, 2);
      expect(m.topCategories.single.share, 0.62);
      expect(m.topBrands.single.share, 0.5); // percentages are normalised
      expect(m.budgetLabel, 'Rs 4,000 to Rs 80,000');
      expect(m.recentSearches, ['gaming laptop']);
      expect(m.interactions, 14);
      expect(m.hasNothing, isFalse);
      expect(m.lastActivityAt, isNotNull);
    });

    test('an empty snapshot has nothing and keeps the consent flag', () {
      final m = ShoppingMemory.fromJson({
        'enabled': false,
        'summary': ['Nothing remembered yet.'],
        'topCategories': [],
        'topBrands': [],
        'budgetBand': null,
        'recentSearches': [],
        'counts': {'interactions': 0, 'searches': 0, 'chats': 0},
      });
      expect(m.enabled, isFalse);
      expect(m.hasNothing, isTrue);
      expect(m.cleared().enabled, isFalse);
      expect(m.copyWith(enabled: true).enabled, isTrue);
    });

    test('a flat list of remembered items is folded into the summary', () {
      final m = ShoppingMemory.fromJson({
        'enabled': true,
        'items': ['Likes Apple', {'text': 'Budget under 50k'}],
      });
      expect(m.summary, ['Likes Apple', 'Budget under 50k']);
    });
  });

  group('price alert notifications', () {
    test('price_drop carries old and new price', () {
      final n = AppNotification.fromJson({
        'id': 1,
        'type': 'price_drop',
        'title': 'Price drop: Phone',
        'body': 'Now Rs 39,999 (was Rs 45,000)',
        'data': {
          'productId': 9,
          'slug': 'phone',
          'thumbnail': '/uploads/a.webp',
          'oldPrice': 45000,
          'newPrice': 39999,
          'dropPercent': 11.13,
          'targetPrice': null,
          'reason': 'watch',
          'event': 'price_drop',
        },
        'readAt': null,
        'createdAt': '2026-11-17T10:00:00.000Z',
      });
      expect(n.isPriceAlert, isTrue);
      expect(n.productId, 9);
      expect(n.oldPrice, 45000);
      expect(n.newPrice, 39999);
      expect(n.dropPercent, closeTo(11.13, 0.001));
      expect(n.hasPriceChange, isTrue);
      expect(n.thumbnail, '/uploads/a.webp');
    });

    test('a restock without a price change has no old→new line', () {
      final n = AppNotification.fromJson({
        'id': 2,
        'type': 'restock',
        'title': 'Back in stock',
        'body': 'Available again',
        'data': {'productId': 9, 'oldPrice': 100, 'newPrice': 100},
      });
      expect(n.isPriceAlert, isTrue);
      expect(n.hasPriceChange, isFalse);
      expect(AppNotification.fromJson({'id': 3, 'type': 'order', 'title': 't', 'body': 'b'}).isPriceAlert, isFalse);
    });
  });

  group('snap & find crop', () {
    test('a selection maps to whole pixels inside the photo', () {
      final r = cropPixelRect(const Rect.fromLTRB(0.25, 0.5, 0.75, 1.0), 200, 100);
      expect(r, const Rect.fromLTRB(50, 50, 150, 100));
      // out-of-range input is clamped and never empty
      final clamped = cropPixelRect(const Rect.fromLTRB(-1, -1, 2, 2), 50, 40);
      expect(clamped, const Rect.fromLTRB(0, 0, 50, 40));
      final tiny = cropPixelRect(const Rect.fromLTRB(0.5, 0.5, 0.5, 0.5), 10, 10);
      expect(tiny.width, greaterThanOrEqualTo(1));
      expect(tiny.height, greaterThanOrEqualTo(1));
    });

    test('output is scaled down to the longest side', () {
      expect(cropOutputSize(const Rect.fromLTWH(0, 0, 800, 400)), const Size(800, 400));
      expect(cropOutputSize(const Rect.fromLTWH(0, 0, 2048, 1024)), const Size(1024, 512));
      expect(cropOutputSize(const Rect.fromLTWH(0, 0, 1000, 4000), maxSide: 400), const Size(100, 400));
    });

    test('a near-full selection counts as the whole photo', () {
      expect(isWholeImage(kWholeImage), isTrue);
      expect(isWholeImage(const Rect.fromLTRB(0.01, 0.0, 1, 0.99)), isTrue);
      expect(isWholeImage(kDefaultCrop), isFalse);
    });

    test('cropToPng cuts the region and encodes a PNG', () async {
      // a 40x20 photo: left half red, right half blue
      final image = await _twoColourImage(40, 20);
      final bytes = await cropToPng(image, const Rect.fromLTRB(0.5, 0, 1, 1));
      expect(bytes, isNotNull);
      // PNG signature
      expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final cut = await decodeImageBytes(bytes);
      expect(cut.width, 20);
      expect(cut.height, 20);
      final raw = (await cut.toByteData())!;
      // the right half of the source is blue
      expect(raw.getUint8(0), 0);
      expect(raw.getUint8(2), 255);
      cut.dispose();
      image.dispose();
    });
  });

  group('read aloud text', () {
    test('markdown becomes speakable', () {
      expect(speechTextFromMarkdown('Here are **2 phones** near `Rs 30,000`:\n- Great battery\n- Big screen'), 'Here are 2 phones near Rs 30,000: Great battery. Big screen');
      expect(speechTextFromMarkdown('## Title\n1. First\n2. Second'), 'Title. First. Second');
      expect(speechTextFromMarkdown('See [the list](https://example.com/x) now'), 'See the list now');
      expect(speechTextFromMarkdown('   '), '');
    });
  });
}

Future<ui.Image> _twoColourImage(int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Rect.fromLTWH(0, 0, w / 2, h.toDouble()), Paint()..color = const Color(0xFFFF0000));
  canvas.drawRect(Rect.fromLTWH(w / 2, 0, w / 2, h.toDouble()), Paint()..color = const Color(0xFF0000FF));
  final picture = recorder.endRecording();
  final image = await picture.toImage(w, h);
  picture.dispose();
  return image;
}

class _GiftCall {
  _GiftCall(this.recipient, this.occasion, this.budget, this.interests);

  final String recipient;
  final String occasion;
  final num budget;
  final List<String> interests;
}

class _FakeAi extends AiRepository {
  _FakeAi({this.result, this.error}) : super(ApiClient(Dio()));

  final GiftResult? result;
  final Object? error;
  final calls = <_GiftCall>[];

  @override
  Future<GiftResult> gift({
    required String recipient,
    required String occasion,
    required num budget,
    List<String> interests = const [],
  }) async {
    calls.add(_GiftCall(recipient, occasion, budget, interests));
    if (error != null) throw error!;
    return result ?? const GiftResult(title: 'Gift ideas');
  }
}
