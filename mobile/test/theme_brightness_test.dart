import 'dart:math' as math;

import 'package:cartwise/core/theme/app_colors.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/core/widgets/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  double lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double lum(Color c) => 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
  final la = lum(a), lb = lum(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// A translucent colour as it looks over [bg].
Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  group('light palette clears WCAG AA (4.5:1 for text, 3:1 for large text and icons)', () {
    const p = AppPalette.light;
    final washes = [p.backgroundTop, p.background, p.backgroundBottom];

    test('royal blue: as button fill under white text, and as text on the page, cards and its own tint', () {
      expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5));
      expect(contrast(p.primaryHover, p.onPrimary), greaterThanOrEqualTo(4.5));
      for (final wash in washes) {
        expect(contrast(p.primary, wash), greaterThanOrEqualTo(4.5), reason: 'blue on $wash');
      }
      expect(contrast(p.primary, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.primary, p.primarySoft), greaterThanOrEqualTo(4.5));
      expect(contrast(p.primary, p.surfaceVariant), greaterThanOrEqualTo(4.5));
    });

    test('body, muted and faint text on the wash, cards and quiet fills', () {
      for (final bg in [...washes, p.surface, p.surfaceVariant]) {
        expect(contrast(p.text, bg), greaterThanOrEqualTo(12), reason: 'text on $bg');
        expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5), reason: 'muted on $bg');
        expect(contrast(p.faint, bg), greaterThanOrEqualTo(4.5), reason: 'faint on $bg');
      }
    });

    test('prices are confident navy: far above AA on white, cards, wells and tinted wells', () {
      expect(p.price, AppColors.priceNavy);
      for (final bg in [p.surface, p.surfaceVariant, p.imageWell, ...washes]) {
        expect(contrast(p.price, bg), greaterThanOrEqualTo(10), reason: 'price on $bg');
      }
      // and distinct from body text, so amounts read first
      expect(p.price, isNot(p.text));
    });

    test('sale: vivid coral-red under white text, and as text on its soft tint and on cards', () {
      expect(contrast(p.onSale, p.sale), greaterThanOrEqualTo(4.5));
      expect(contrast(p.sale, p.saleSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(p.sale, p.surface), greaterThanOrEqualTo(4.5));
      for (final wash in washes) {
        expect(contrast(p.sale, wash), greaterThanOrEqualTo(4.5));
      }
      // more vivid than the old calm red (#DC2626)
      final hsl = HSLColor.fromColor(p.sale);
      expect(hsl.saturation, greaterThan(HSLColor.fromColor(const Color(0xFFDC2626)).saturation));
    });

    test('deal amber: navy ink on the amber fill and brown ink on its soft tint', () {
      expect(contrast(p.onDeal, p.deal), greaterThanOrEqualTo(7));
      expect(contrast(p.dealInk, p.dealSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(p.dealInk, p.surface), greaterThanOrEqualTo(4.5));
    });

    test('status colours still read on white cards', () {
      expect(contrast(p.success, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.warning, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.secondary, p.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(p.error, p.surface), greaterThanOrEqualTo(4.5));
    });

    test('the page wash is lighter and cleaner than before, cards stay pure white', () {
      expect(p.surface, const Color(0xFFFFFFFF));
      // lighter than the previous #EEF1FB / #E6EAF8
      expect(p.background.computeLuminance(), greaterThan(const Color(0xFFEEF1FB).computeLuminance()));
      expect(p.backgroundBottom.computeLuminance(), greaterThan(const Color(0xFFE6EAF8).computeLuminance()));
      // still separable from the white cards (hairline + shadow carry the rest)
      expect(contrast(p.surface, p.backgroundBottom), greaterThan(1.1));
    });

    test('the brand blue is a bit more saturated than before (#2563EB)', () {
      expect(HSLColor.fromColor(AppColors.blue).saturation, greaterThan(HSLColor.fromColor(const Color(0xFF2563EB)).saturation));
      expect(p.primary, AppColors.blue);
    });
  });

  group('dark palette keeps its contrast', () {
    const p = AppPalette.dark;
    test('accent, price, sale and deal tokens read on the dark surfaces', () {
      for (final bg in [p.surface, p.surfaceVariant, p.background]) {
        expect(contrast(p.primary, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.price, bg), greaterThanOrEqualTo(7));
        expect(contrast(p.sale, bg), greaterThanOrEqualTo(4.5));
        expect(contrast(p.muted, bg), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(p.onPrimary, p.primary), greaterThanOrEqualTo(4.5));
      expect(contrast(p.dealInk, p.dealSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(p.onDeal, p.deal), greaterThanOrEqualTo(7));
    });
  });

  group('department tints', () {
    test('categories map to their department, unknown slugs to nothing', () {
      expect(AppColors.departmentKey('smartphones'), 'electronics');
      expect(AppColors.departmentKey('laptops'), 'electronics');
      expect(AppColors.departmentKey('womens-dresses'), 'fashion');
      expect(AppColors.departmentKey('fragrances'), 'beauty-personal-care');
      expect(AppColors.departmentKey('kitchen-accessories'), 'home-living');
      expect(AppColors.departmentKey('motorcycle'), 'automotive');
      expect(AppColors.departmentKey('sports-accessories'), 'sports-outdoors');
      expect(AppColors.departmentKey('groceries'), 'groceries');
      // a department slug maps to itself
      expect(AppColors.departmentKey('fashion'), 'fashion');
      expect(AppColors.departmentKey('mystery-box'), isNull);
      expect(AppColors.departmentKey(null), isNull);
    });

    test('image wells are a very soft tint of the department hue, still light, and neutral when unknown', () {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        for (final slug in ['smartphones', 'womens-dresses', 'fragrances', 'furniture', 'groceries', 'sports-accessories', 'vehicle']) {
          final well = p.departmentWell(slug);
          expect(well, isNot(p.imageWell), reason: slug);
          // light in both themes: cut-out photos (many are black) must stay visible
          expect(well.computeLuminance(), greaterThan(0.75), reason: slug);
          expect(contrast(AppColors.navy, well), greaterThanOrEqualTo(12), reason: slug);
          // "very soft": within a whisker of the plain well
          expect(contrast(well, p.imageWell), lessThan(1.15), reason: slug);
        }
        expect(p.departmentWell('mystery-box'), p.imageWell);
        expect(p.departmentWell(null), p.imageWell);
      }
      // different departments get different tints
      expect(AppPalette.light.departmentWell('smartphones'), isNot(AppPalette.light.departmentWell('womens-dresses')));
      expect(AppPalette.light.departmentWell('smartphones'), AppPalette.light.departmentWell('laptops'));
    });

    test('tile tints on a card surface stay soft and keep the label readable', () {
      for (final p in [AppPalette.light, AppPalette.dark]) {
        final soft = p.departmentSoft('electronics');
        expect(soft, isNot(p.surface));
        expect(contrast(p.text, soft), greaterThanOrEqualTo(7));
        expect(p.departmentSoft('mystery-box'), p.surfaceVariant);
      }
    });
  });

  group('palette plumbing', () {
    test('copyWith and lerp carry the new tokens', () {
      final tweaked = AppPalette.light.copyWith(price: const Color(0xFF000000), deal: const Color(0xFF111111));
      expect(tweaked.price, const Color(0xFF000000));
      expect(tweaked.deal, const Color(0xFF111111));
      expect(tweaked.onDeal, AppPalette.light.onDeal);
      final mid = AppPalette.light.lerp(AppPalette.dark, 1);
      expect(mid.price, AppPalette.dark.price);
      expect(mid.dealSoft, AppPalette.dark.dealSoft);
    });

    test('shadows got a touch crisper but are still navy-tinted and soft', () {
      final sm = AppPalette.light.shadowSm;
      expect(sm, hasLength(2));
      expect(sm.first.color.a, lessThan(0.12));
      expect(sm.first.blurRadius, greaterThanOrEqualTo(12));
    });
  });

  group('widgets use the new tokens', () {
    Widget host(Widget child) => MaterialApp(theme: AppTheme.light, home: Scaffold(body: Center(child: child)));

    testWidgets('PriceText paints the amount in price navy', (tester) async {
      await tester.pumpWidget(host(const PriceText(45999)));
      final text = tester.widget<RichText>(find.descendant(of: find.byType(PriceText), matching: find.byType(RichText)).first);
      expect(text.text.style!.color, AppColors.priceNavy);
    });

    testWidgets('StatusTone.deal is an amber pill and DealTag is solid amber with navy ink', (tester) async {
      await tester.pumpWidget(host(const Column(mainAxisSize: MainAxisSize.min, children: [
        StatusBadge('Flash deal', tone: StatusTone.deal),
        DealTag('Ends today'),
      ])));
      expect(find.text('Flash deal'), findsOneWidget);
      final tag = tester.widget<Container>(find.ancestor(of: find.text('Ends today'), matching: find.byType(Container)).first);
      expect((tag.decoration! as BoxDecoration).color, AppPalette.light.deal);
      final style = tester.widget<Text>(find.text('Ends today')).style!;
      expect(style.color, AppPalette.light.onDeal);
    });

    testWidgets('chips take a light blue tint and a soft blue outline under the pointer', (tester) async {
      final theme = AppTheme.light.chipTheme;
      final p = AppPalette.light;
      final hovered = theme.color!.resolve({WidgetState.hovered});
      expect(hovered, p.primarySoft);
      expect(theme.color!.resolve(<WidgetState>{}), p.surface);
      expect(WidgetStateProperty.resolveAs<BorderSide?>(theme.side, {WidgetState.hovered})!.color, p.primary.withValues(alpha: 0.45));
      expect(WidgetStateProperty.resolveAs<BorderSide?>(theme.side, {WidgetState.selected})!.width, 1.5);
    });
  });
}
