import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/features/cart/data/models/cart.dart';
import 'package:cartwise/features/catalog/data/models/product_query.dart';
import 'package:cartwise/features/checkout/presentation/widgets/card_utils.dart';
import 'package:cartwise/features/compare_tray/compare_tray_provider.dart';
import 'package:cartwise/features/orders/data/models/order.dart';
import 'package:cartwise/features/profile/presentation/widgets/address_form.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProductSummary _p(int id, {double price = 1000, int stock = 20}) =>
    ProductSummary(id: id, title: 'P$id', slug: 'p$id', price: price, stock: stock);

void main() {
  group('card utils', () {
    test('detects brands', () {
      expect(CardBrand.detect('4242'), CardBrand.visa);
      expect(CardBrand.detect('5555'), CardBrand.mastercard);
      expect(CardBrand.detect('2221'), CardBrand.mastercard);
      expect(CardBrand.detect('3782'), CardBrand.amex);
      expect(CardBrand.detect('6200'), CardBrand.unionPay);
      expect(CardBrand.detect('9999'), CardBrand.unknown);
    });

    test('luhn + number validation', () {
      expect(CardValidators.number('4242 4242 4242 4242'), isNull);
      expect(CardValidators.number('3782 822463 10005'), isNull);
      expect(CardValidators.number('4242 4242 4242 4241'), isNotNull);
      expect(CardValidators.number('4242'), isNotNull);
      expect(CardValidators.number(''), isNotNull);
    });

    test('expiry', () {
      final now = DateTime(2026, 11, 17);
      expect(CardValidators.expiry('11/26', now: now), isNull);
      expect(CardValidators.expiry('10/26', now: now), 'This card has expired');
      expect(CardValidators.expiry('13/27', now: now), 'Invalid month');
      expect(CardValidators.expiry('1127', now: now), 'Use MM/YY');
    });

    test('cvv length follows brand', () {
      expect(CardValidators.cvv('123', CardBrand.visa), isNull);
      expect(CardValidators.cvv('123', CardBrand.amex), isNotNull);
      expect(CardValidators.cvv('1234', CardBrand.amex), isNull);
    });

    test('number formatter groups digits', () {
      final f = CardNumberFormatter();
      String fmt(String s) => f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s)).text;
      expect(fmt('4242424242424242'), '4242 4242 4242 4242');
      expect(fmt('378282246310005'), '3782 822463 10005');
      expect(fmt('42424242424242429999'), '4242 4242 4242 4242');
    });

    test('expiry formatter inserts slash', () {
      final f = ExpiryFormatter();
      String fmt(String s) => f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s)).text;
      expect(fmt('1127'), '11/27');
      expect(fmt('4'), '04/');
    });
  });

  test('Pakistani phone validation', () {
    expect(validatePkPhone('0300 1234567'), isNull);
    expect(validatePkPhone('+92 300 1234567'), isNull);
    expect(validatePkPhone('12345'), isNotNull);
    expect(validatePkPhone(''), isNotNull);
  });

  group('ProductQuery', () {
    test('value equality (provider family key)', () {
      const a = ProductQuery(category: 'laptops', brands: ['Apple', 'Dell'], minRating: 4);
      const b = ProductQuery(category: 'laptops', brands: ['Apple', 'Dell'], minRating: 4);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(brands: ['Apple']), isFalse);
    });

    test('filters count and query map', () {
      const q = ProductQuery(q: 'phone', brands: ['Apple'], maxPrice: 50000, inStock: true);
      expect(q.activeFilterCount, 3);
      expect(q.effectiveSort, ProductSort.relevance);
      final map = q.toQuery(page: 2);
      expect(map['brand'], ['Apple']);
      expect(map['maxPrice'], 50000);
      expect(map['inStock'], true);
      expect(map['onSale'], isNull);
      expect(map['page'], 2);
      expect(q.clearFilters().activeFilterCount, 0);
      expect(q.clearFilters().q, 'phone');
    });
  });

  group('Cart', () {
    final cart = Cart(
      items: [
        CartItem(productId: 1, product: _p(1, stock: 3), quantity: 2, lineTotal: 2000),
        CartItem(productId: 2, product: _p(2), quantity: 1, lineTotal: 1000),
      ],
      summary: const CartSummary(itemCount: 3, subtotal: 3000, total: 3250, shippingFee: 250),
    );

    test('optimistic quantity edit and removal', () {
      final more = cart.withQuantity(2, 4);
      expect(more.quantityOf(2), 4);
      expect(more.summary.itemCount, 6);
      final removed = cart.withQuantity(1, 0);
      expect(removed.items.length, 1);
      expect(removed.summary.itemCount, 1);
    });

    test('max quantity respects stock and the 10 cap', () {
      expect(cart.items.first.maxQuantity, 3);
      expect(cart.items.last.maxQuantity, 10);
    });

    test('free shipping progress', () {
      expect(cart.summary.remainingForFreeShipping, 2000);
      expect(cart.summary.freeShippingProgress, closeTo(0.6, 0.001));
      const free = CartSummary(subtotal: 6000);
      expect(free.remainingForFreeShipping, 0);
    });
  });

  test('order status helpers', () {
    expect(OrderStatus.parse('out_for_delivery'), OrderStatus.outForDelivery);
    expect(OrderStatus.placed.canCancel, isTrue);
    expect(OrderStatus.shipped.canCancel, isFalse);
    expect(OrderStatus.delivered.isActive, isFalse);
  });

  test('compare tray holds up to 4 distinct products', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final tray = container.read(compareTrayProvider.notifier);
    for (var i = 1; i <= 4; i++) {
      expect(tray.toggle(_p(i)), CompareToggleResult.added);
    }
    expect(tray.toggle(_p(5)), CompareToggleResult.full);
    expect(tray.toggle(_p(2)), CompareToggleResult.removed);
    expect(tray.ids, [1, 3, 4]);
    tray.clear();
    expect(container.read(compareTrayProvider), isEmpty);
  });
}
