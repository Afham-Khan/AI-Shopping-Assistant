import 'dart:convert';
import 'dart:io';

import 'package:cartwise/features/ai/data/models/ai_models.dart';
import 'package:cartwise/features/ai/data/models/shopping_models.dart';
import 'package:cartwise/features/product/data/models/price_history.dart';
import 'package:cartwise/features/profile/data/memory_models.dart';
import 'package:cartwise/features/wishlist/data/price_watch_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// `data` of a real backend response saved in test/fixtures/api (captured from
/// the running API), so the parsers are checked against the true shapes.
Object? _data(String name) {
  final json = jsonDecode(File('test/fixtures/api/$name.json').readAsStringSync()) as Map<String, dynamic>;
  expect(json['success'], isTrue, reason: '$name fixture is a success envelope');
  return json['data'];
}

void main() {
  test('complete-look (fashion): roles, reasons, palette tip', () {
    final look = CompleteLook.fromJson(_data('look'));
    expect(look.isOutfit, isTrue);
    expect(look.items, isNotEmpty);
    expect(look.items.length, lessThanOrEqualTo(8));
    // every card has a role label, a product and at least one reason
    for (final i in look.items) {
      expect(i.role, isNotEmpty);
      expect(i.product.id, greaterThan(0));
      expect(i.product.title, isNotEmpty);
    }
    expect(look.items.first.product.match!.reasons, isNotEmpty);
    // no product twice
    expect(look.items.map((i) => i.product.id).toSet().length, look.items.length);
    expect(look.items.any((i) => i.role == 'Shoes' || i.role == 'Bag' || i.role == 'Jewellery'), isTrue);
    expect(look.total, greaterThan(0));
  });

  test('complete-look (non-fashion) falls back to complementary: no outfit section', () {
    final look = CompleteLook.fromJson(_data('look_phone'));
    expect(look.kind, 'complementary');
    expect(look.isOutfit, isFalse);
  });

  test('explain: who it is for, specs with plain meaning and levels', () {
    final e = SpecExplainer.fromJson(_data('explain'));
    expect(e.isEmpty, isFalse);
    expect(e.productTitle, isNotNull);
    expect(e.summary, isNotEmpty);
    expect(e.whoFor, isNotEmpty);
    expect(e.specs, isNotEmpty);
    for (final s in e.specs) {
      expect(s.label, isNotEmpty);
      expect(s.value, isNotEmpty);
      expect(s.meaning, isNotEmpty);
      expect(s.level, inInclusiveRange(0, 5));
    }
    expect(e.specs.any((s) => s.isRated && s.levelLabel != null && s.scale != null), isTrue);
    expect(e.highlights.length, lessThanOrEqualTo(3));
  });

  test('compare v2: differs on every row, pros/cons per product, forYou for the need', () {
    final r = CompareResult.fromJson(_data('compare'));
    expect(r.products.length, 2);
    expect(r.rows, isNotEmpty);
    expect(r.rows.every((row) => row.differs != null), isTrue, reason: 'the server sends differs on every row');
    expect(r.differingRows.length, lessThanOrEqualTo(r.rows.length));
    expect(r.prosCons.keys.toSet(), r.products.map((p) => p.id).toSet());
    expect(r.prosCons.values.every((pc) => pc.pros.isNotEmpty), isTrue);
    expect(r.forYou, isNotNull);
    expect(r.productById(r.forYou!.productId), isNotNull);
    expect(r.forYou!.reason, startsWith('For gaming'));
    // existing parts still parse
    expect(r.picks, isNotEmpty);
    expect(r.summary, isNotEmpty);
  });

  test('gift: title, note and products with reasons', () {
    final g = GiftResult.fromJson(_data('gift'));
    expect(g.title, contains('mom'));
    expect(g.note, isNotEmpty);
    expect(g.products, isNotEmpty);
    expect(g.products.every((p) => p.price <= 10000), isTrue, reason: 'never above the budget');
    expect(g.products.first.match!.reasons, isNotEmpty);
  });

  test('memory: summary lines and facts', () {
    final m = ShoppingMemory.fromJson(_data('memory'));
    expect(m.enabled, isTrue);
    expect(m.summary, isNotEmpty);
    expect(m.topCategories, isNotEmpty);
    expect(m.topCategories.first.share, inInclusiveRange(0, 1));
    expect(m.hasNothing, isFalse);
  });

  test('price history: the seed row alone is a flat, honest state', () {
    final h = PriceHistory.fromJson(_data('history'));
    expect(h.points.length, 1);
    expect(h.currentPrice, greaterThan(0));
    expect(h.hasChanges, isFalse);
    expect(h.isEmpty, isFalse);
    expect(h.trend, 'flat');
    expect(h.insight, isNotNull);
  });

  test('price watches: product card, status line and target', () {
    final list = (_data('watches') as List).cast<Map<String, dynamic>>().map(PriceWatch.fromJson).toList();
    expect(list, isNotEmpty);
    final w = list.first;
    expect(w.productId, greaterThan(0));
    expect(w.product.title, isNotEmpty);
    expect(w.status.summary, isNotEmpty);
    expect(w.badgeLabel, startsWith('Watching'));
  });
}
