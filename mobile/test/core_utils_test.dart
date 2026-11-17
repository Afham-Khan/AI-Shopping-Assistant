import 'package:cartwise/core/config/app_config.dart';
import 'package:cartwise/core/network/api_client.dart';
import 'package:cartwise/core/router/routes.dart';
import 'package:cartwise/core/utils/formatters.dart';
import 'package:cartwise/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Formatters', () {
    test('price uses Rs and thousands separators', () {
      expect(Formatters.price(45999), 'Rs 45,999');
      expect(Formatters.price(279999.4), 'Rs 279,999');
      expect(Formatters.price(0), 'Rs 0');
      expect(Formatters.price(null), 'Rs 0');
    });

    test('compact values', () {
      expect(Formatters.priceCompact(279999), 'Rs 280K');
      expect(Formatters.compact(12800), '12.8K');
      expect(Formatters.rating(4.56), '4.6');
      expect(Formatters.rating(4), '4');
      expect(Formatters.discount(9.7), '-10%');
      expect(Formatters.percentFromRatio(0.87), '87%');
    });

    test('relative dates', () {
      final now = DateTime(2026, 11, 17, 15);
      expect(Formatters.relative(now.subtract(const Duration(seconds: 10)), now: now), 'Just now');
      expect(Formatters.relative(now.subtract(const Duration(minutes: 5)), now: now), '5m ago');
      expect(Formatters.relative(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
      expect(Formatters.relative(DateTime(2026, 11, 16, 20), now: now), 'Yesterday');
      expect(Formatters.relative(DateTime(2026, 11, 13, 9), now: now), '4d ago');
      expect(Formatters.relative(DateTime(2026, 10, 2), now: now), 'Oct 2');
      expect(Formatters.relative(DateTime(2025, 10, 2), now: now), 'Oct 2, 2025');
    });

    test('plural', () {
      expect(Formatters.plural(1, 'item'), '1 item');
      expect(Formatters.plural(3, 'item'), '3 items');
    });
  });

  group('Validators', () {
    test('email', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('ali@'), isNotNull);
      expect(Validators.email('ali@x.com'), isNull);
    });

    test('password mirrors API rule', () {
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('allletters'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password('secret123'), isNull);
    });

    test('confirm, otp, phone, required', () {
      expect(Validators.confirmPassword(() => 'abc12345')('abc12345'), isNull);
      expect(Validators.confirmPassword(() => 'abc12345')('abc'), isNotNull);
      expect(Validators.otp('123456'), isNull);
      expect(Validators.otp('12345'), isNotNull);
      expect(Validators.phone(''), isNull);
      expect(Validators.phone('+92 300 1234567'), isNull);
      expect(Validators.phone('abc'), isNotNull);
      expect(Validators.required('Name')('  '), 'Name is required');
    });

    test('strength', () {
      expect(Validators.strength(''), PasswordStrength.empty);
      expect(Validators.strength('abc'), PasswordStrength.weak);
      expect(Validators.strength('secret123'), PasswordStrength.fair);
      expect(Validators.strength('Secret123!long'), PasswordStrength.strong);
    });
  });

  group('AppConfig', () {
    test('resolves relative image urls', () {
      const base = 'http://localhost:5000';
      expect(AppConfig.resolveAgainst(base, '/uploads/a.webp'), '$base/uploads/a.webp');
      expect(AppConfig.resolveAgainst(base, 'uploads/a.webp'), '$base/uploads/a.webp');
      expect(AppConfig.resolveAgainst(base, 'https://cdn.x/a.png'), 'https://cdn.x/a.png');
      expect(AppConfig.resolveAgainst(base, ''), isNull);
      expect(AppConfig.resolveAgainst(base, null), isNull);
    });

    test('normalizes user-entered server addresses', () {
      expect(AppConfig.normalize('192.168.1.5:5000/'), 'http://192.168.1.5:5000');
      expect(AppConfig.normalize('http://10.0.2.2:5000/api/v1'), 'http://10.0.2.2:5000');
      expect(AppConfig.isValidBaseUrl('localhost:5000'), isTrue);
      expect(AppConfig.isValidBaseUrl('ftp://x'), isFalse);
    });
  });

  group('Networking helpers', () {
    test('ApiException reads field errors from the envelope', () {
      final e = ApiException.fromResponse(400, {
        'success': false,
        'message': 'Validation failed',
        'errors': [
          {'field': 'email', 'message': 'Email is taken'},
        ],
      });
      expect(e.message, 'Validation failed');
      expect(e.fieldError('email'), 'Email is taken');
      expect(e.isValidation, isTrue);
    });

    test('cleanQuery drops empties and joins lists', () {
      expect(
        ApiClient.cleanQuery({'q': '', 'brand': ['apple', 'samsung'], 'page': 2, 'onSale': true, 'x': null}),
        {'brand': 'apple,samsung', 'page': 2, 'onSale': 'true'},
      );
    });
  });

  group('Routes', () {
    test('builders encode params', () {
      expect(Routes.product(12), '/product/12');
      expect(Routes.productList(category: 'laptops', onSale: true), '/products?category=laptops&onSale=true');
      expect(Uri.parse(Routes.compareOf([1, 2])).queryParameters['ids'], '1,2');
      expect(Uri.parse(Routes.loginFrom('/cart')).queryParameters['from'], '/cart');
      expect(Routes.loginFrom('/login'), '/login');
    });

    test('protected matching and safe return targets', () {
      expect(Routes.isProtected('/cart'), isTrue);
      expect(Routes.isProtected('/account/orders/3'), isTrue);
      expect(Routes.isProtected('/account'), isFalse);
      expect(Routes.isProtected('/product/1'), isFalse);
      expect(Routes.returnTo('https://evil.com'), Routes.home);
      expect(Routes.returnTo('/login'), Routes.home);
      expect(Routes.returnTo('/product/1'), '/product/1');
    });
  });
}
