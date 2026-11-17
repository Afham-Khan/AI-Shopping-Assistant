import 'package:cartwise/core/network/api_client.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/features/ai/data/ai_repository.dart';
import 'package:cartwise/features/ai/data/models/ai_models.dart';
import 'package:cartwise/features/ai/presentation/bundle_builder_screen.dart';
import 'package:cartwise/features/home/presentation/room/setup_sheet.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _advice =
    'No gaming laptop fits Rs 150,000 — the most affordable one is Rs 307,999. '
    'Raise the budget to about Rs 375,000 to include it.';

Map<String, dynamic> _product(int id, String title, double price, String slug) => {
  'id': id,
  'title': title,
  'slug': 'p-$id',
  'category': {'id': id, 'name': slug, 'slug': slug},
  'price': price,
  'stock': 5,
  'inStock': true,
  'match': {'score': 0.8, 'reasons': ['Best pick']},
};

/// What the API returns for "gaming setup" when the budget can't cover the laptop.
Map<String, dynamic> _shortJson({double budget = 150000, double suggested = 375000, bool empty = false}) => {
  'title': 'Gaming setup',
  'budget': budget,
  'items': empty
      ? <Map<String, dynamic>>[]
      : [
          {'role': 'Headphones', 'product': _product(1, 'Studio earphones', 13999, 'mobile-accessories')},
          {'role': 'Speaker', 'product': _product(2, 'Echo speaker', 27999, 'mobile-accessories')},
        ],
  'skippedRoles': ['Gaming laptop', 'Gaming chair'],
  'explanation': 'I split your budget across 2 pieces. $_advice The speaker is the biggest piece.',
  'savingsTips': <String>[],
  'budgetAdvice': {
    'minimumForAll': 489996,
    'minimumForRequired': 321998,
    'suggestedBudget': suggested,
    'cheapestByRole': [
      {'role': 'Gaming laptop', 'price': 307999, 'productId': 81},
      {'role': 'Headphones', 'price': 13999, 'productId': 107},
    ],
    'missingRequired': ['Gaming laptop'],
    'message': _advice,
  },
};

Map<String, dynamic> _fullJson(double budget) => {
  'title': 'Gaming setup',
  'budget': budget,
  'items': [
    {'role': 'Gaming laptop', 'product': _product(81, 'Gaming laptop X', 307999, 'laptops')},
    {'role': 'Headphones', 'product': _product(1, 'Studio earphones', 13999, 'mobile-accessories')},
  ],
  'skippedRoles': <String>[],
  'explanation': 'I split your budget across 2 pieces for a gaming setup.',
  'savingsTips': <String>[],
  'budgetAdvice': {
    'minimumForAll': 489996,
    'minimumForRequired': 321998,
    'suggestedBudget': 375000,
    'cheapestByRole': <Map<String, dynamic>>[],
    'missingRequired': <String>[],
    'message': 'Everything fits — the cheapest way to get every piece is Rs 489,996.',
  },
};

BundleTemplate _template(String id, String label, double budget) => BundleTemplate(
  id: id,
  goal: label.toLowerCase(),
  label: label,
  suggestedBudget: budget,
);

class _FakeBundleAi extends AiRepository {
  _FakeBundleAi({this.templatesFail = false, this.fullAt = 375000, this.empty = false}) : super(ApiClient(Dio()));

  final bool templatesFail;

  /// Budgets from this value up cover the essentials.
  final double fullAt;

  /// The short result has no items at all.
  final bool empty;

  int templateCalls = 0;
  final calls = <({String goal, double budget})>[];

  @override
  Future<List<BundleTemplate>> bundleTemplates() async {
    templateCalls++;
    if (templatesFail) throw const ApiException('offline', code: ApiException.networkError);
    return [
      _template('gaming_setup', 'Gaming setup', 375000),
      _template('home_office', 'Home office setup', 525000),
      _template('skincare_routine', 'Skincare routine', 6500),
      _template('university_kit', 'University starter kit', 150000),
    ];
  }

  @override
  Future<BundleResult> bundle({required String goal, required double budget}) async {
    calls.add((goal: goal, budget: budget));
    return BundleResult.fromJson(
      budget >= fullAt ? _fullJson(budget) : _shortJson(budget: budget, suggested: fullAt, empty: empty),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  _FakeBundleAi ai, {
  double scale = 1,
  Size size = const Size(400, 1000),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final List<Override> overrides = [
    sharedPreferencesProvider.overrideWithValue(prefs),
    aiRepositoryProvider.overrideWithValue(ai),
  ];
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery.withClampedTextScaling(minScaleFactor: scale, maxScaleFactor: scale, child: home),
      ),
    ),
  );
  await _settle(tester);
}

class _SheetHost extends StatelessWidget {
  const _SheetHost({required this.onResult});

  final ValueChanged<BundleResult?> onResult;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () async => onResult(await showSetupSheet(context)),
          child: const Text('Open'),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => AppTheme.useGoogleFonts = false);

  group('budget advice models', () {
    test('BundleResult reads budgetAdvice and strips it from the explanation body', () {
      final b = BundleResult.fromJson(_shortJson());
      final a = b.budgetAdvice;
      expect(a.missesEssentials, isTrue);
      expect(a.missingRequired, ['Gaming laptop']);
      expect(a.minimumForAll, 489996);
      expect(a.minimumForRequired, 321998);
      expect(a.suggestedBudget, 375000);
      expect(a.cheapestByRole.first.role, 'Gaming laptop');
      expect(a.cheapestByRole.first.price, 307999);
      expect(a.cheapestByRole.first.productId, 81);
      expect(a.message, _advice);
      expect(b.explanation, contains(_advice));
      expect(b.explanationBody, isNot(contains('No gaming laptop')));
      expect(b.explanationBody, 'I split your budget across 2 pieces. The speaker is the biggest piece.');
      // swapping an item keeps the advice
      final alt = b.items.first.product;
      expect(b.swap(0, alt).budgetAdvice.suggestedBudget, 375000);
    });

    test('an older API without budgetAdvice parses to "nothing to say"', () {
      final json = _fullJson(400000)..remove('budgetAdvice');
      final b = BundleResult.fromJson(json);
      expect(b.budgetAdvice.missesEssentials, isFalse);
      expect(b.budgetAdvice.message, isEmpty);
      expect(b.budgetAdvice.suggestionAbove(1000), isNull);
      expect(b.explanationBody, b.explanation);
    });

    test('suggestionAbove only offers a higher budget', () {
      const a = BudgetAdvice(suggestedBudget: 375000, missingRequired: ['Laptop']);
      expect(a.suggestionAbove(150000), 375000);
      expect(a.suggestionAbove(375000), isNull);
      expect(a.suggestionAbove(500000), isNull);
    });

    test('templates decode and look up suggested budgets by id', () {
      final list = [
        BundleTemplate.fromJson({
          'id': 'gaming_setup',
          'goal': 'gaming setup',
          'label': 'Gaming setup',
          'suggestedBudget': 375000,
          'roles': [
            {'role': 'Gaming laptop', 'required': true, 'minPrice': 307999},
            {'role': 'Speaker', 'required': false, 'minPrice': null},
          ],
        }),
        BundleTemplate.fromJson({'id': 'broken', 'suggestedBudget': 0}),
      ];
      expect(list.first.roles.first.required, isTrue);
      expect(list.first.roles.first.minPrice, 307999);
      expect(list.first.roles.last.minPrice, isNull);
      expect(list.suggestedFor('gaming_setup'), 375000);
      expect(list.suggestedFor('broken'), isNull, reason: 'a zero suggestion is not a suggestion');
      expect(list.suggestedFor('nope'), isNull);
    });
  });

  group('Bundle Builder screen', () {
    testWidgets("a picked goal starts at the server's suggested budget", (tester) async {
      final ai = _FakeBundleAi();
      await _pump(tester, const BundleBuilderScreen(), ai);

      // cards advertise the live suggestion, not the old hard-coded one
      expect(find.text('~Rs 375K'), findsOneWidget);
      expect(find.text('~Rs 525K'), findsOneWidget);
      expect(find.text('~Rs 300K'), findsNothing);

      await tester.tap(find.text('Gaming setup'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '375000'), findsOneWidget);
      await tester.tap(find.text('Home office'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '525000'), findsOneWidget, reason: 'above the old 500k cap');
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to the built-in defaults when the templates endpoint fails', (tester) async {
      final ai = _FakeBundleAi(templatesFail: true);
      await _pump(tester, const BundleBuilderScreen(), ai);

      expect(ai.templateCalls, greaterThanOrEqualTo(1));
      expect(find.text('~Rs 300K'), findsOneWidget);
      await tester.tap(find.text('Gaming setup'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '300000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('skipped essentials show the honest notice and "Use Rs X" re-runs with the suggestion', (tester) async {
      final ai = _FakeBundleAi();
      await _pump(tester, const BundleBuilderScreen(), ai);

      await tester.enterText(find.byType(TextField).first, 'gaming setup');
      await tester.tap(find.text('Build my bundle'));
      await _settle(tester);

      expect(ai.calls.single.budget, 50000);
      expect(find.byKey(const ValueKey('budget-advice-notice')), findsOneWidget);
      expect(find.text('Budget is too low for the essentials'), findsOneWidget);
      // the backend message is shown once, in the notice, not again in the explanation
      expect(find.textContaining('No gaming laptop fits', findRichText: true), findsOneWidget);
      expect(find.text('Use Rs 375,000'), findsOneWidget);
      expect(find.text('Studio earphones'), findsOneWidget);

      await tester.ensureVisible(find.text('Use Rs 375,000'));
      await tester.tap(find.text('Use Rs 375,000'));
      await _settle(tester);

      expect(ai.calls.map((c) => c.budget), [50000, 375000]);
      expect(find.byKey(const ValueKey('budget-advice-notice')), findsNothing);
      expect(find.text('Gaming laptop X'), findsOneWidget);
      expect(find.widgetWithText(TextField, '375000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty result still explains what it would take', (tester) async {
      final ai = _FakeBundleAi(empty: true);
      await _pump(tester, const BundleBuilderScreen(), ai);

      await tester.enterText(find.byType(TextField).first, 'gaming setup');
      await tester.tap(find.text('Build my bundle'));
      await _settle(tester);

      expect(find.text("Couldn't fit a full set"), findsOneWidget);
      expect(find.byKey(const ValueKey('budget-advice-notice')), findsOneWidget);
      expect(find.text('Use Rs 375,000'), findsOneWidget);
    });

    testWidgets('a covered budget shows no notice', (tester) async {
      final ai = _FakeBundleAi(fullAt: 1000);
      await _pump(tester, const BundleBuilderScreen(), ai);

      await tester.enterText(find.byType(TextField).first, 'gaming setup');
      await tester.tap(find.text('Build my bundle'));
      await _settle(tester);

      expect(find.byKey(const ValueKey('budget-advice-notice')), findsNothing);
      expect(find.text('Gaming laptop X'), findsOneWidget);
    });

    testWidgets('the notice fits at 320 px, text scale 2.0', (tester) async {
      final ai = _FakeBundleAi();
      await _pump(tester, const BundleBuilderScreen(), ai, scale: 2, size: const Size(320, 700));

      await tester.enterText(find.byType(TextField).first, 'gaming setup');
      // large text pushes the button below the fold: scroll it into reach
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pump();
      await tester.tap(find.text('Build my bundle'));
      await _settle(tester);

      expect(find.byKey(const ValueKey('budget-advice-notice')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('Room setup sheet', () {
    testWidgets("goals start at the server's suggested budget and the slider grows to fit", (tester) async {
      final ai = _FakeBundleAi();
      await _pump(tester, _SheetHost(onResult: (_) {}), ai);
      await _openSheet(tester);

      expect(find.text('Rs 375,000'), findsOneWidget, reason: 'gaming setup is the first goal');
      await tester.tap(find.text('Home office'));
      await tester.pump();
      expect(find.text('Rs 525,000'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).max, 600000);
      await tester.tap(find.text('Skincare routine'));
      await tester.pump();
      expect(find.text('Rs 6,500'), findsOneWidget);
      expect(tester.widget<Slider>(find.byType(Slider)).max, 500000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a slider budget sticks until another goal is picked', (tester) async {
      final ai = _FakeBundleAi();
      await _pump(tester, _SheetHost(onResult: (_) {}), ai);
      await _openSheet(tester);
      final slider = find.byType(Slider);
      tester.widget<Slider>(slider).onChanged!(200000);
      await tester.pump();
      expect(find.text('Rs 200,000'), findsOneWidget);
      // switching goals goes back to that goal's own suggestion
      await tester.tap(find.text('Home office'));
      await tester.pump();
      expect(find.text('Rs 525,000'), findsOneWidget);
    });

    testWidgets('falls back to Rs 150,000 when the templates endpoint fails', (tester) async {
      final ai = _FakeBundleAi(templatesFail: true);
      await _pump(tester, _SheetHost(onResult: (_) {}), ai);
      await _openSheet(tester);

      expect(find.text('Rs 150,000'), findsOneWidget);
      await tester.tap(find.text('Home office'));
      await tester.pump();
      expect(find.text('Rs 150,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('skipped essentials keep the sheet open with the notice; "Use Rs X" re-runs and closes it', (tester) async {
      final ai = _FakeBundleAi(fullAt: 400000);
      BundleResult? result;
      await _pump(tester, _SheetHost(onResult: (r) => result = r), ai);
      await _openSheet(tester);

      await tester.tap(find.text('Furnish the room'));
      await _settle(tester);

      expect(ai.calls.single.budget, 375000);
      expect(result, isNull);
      expect(find.text('Furnish a room with AI'), findsOneWidget, reason: 'the sheet stays open');
      expect(find.byKey(const ValueKey('budget-advice-notice')), findsOneWidget);
      expect(find.textContaining('No gaming laptop fits', findRichText: true), findsOneWidget);
      expect(find.text('Use Rs 400,000'), findsOneWidget);
      expect(find.text('Keep 2 pieces that fit'), findsOneWidget);

      await tester.tap(find.text('Use Rs 400,000'));
      await _settle(tester);

      expect(ai.calls.map((c) => c.budget), [375000, 400000]);
      expect(result, isNotNull);
      expect(result!.items.map((i) => i.role), ['Gaming laptop', 'Headphones']);
      expect(find.text('Furnish a room with AI'), findsNothing);
    });

    testWidgets('"Keep these pieces" furnishes the room with what fits', (tester) async {
      final ai = _FakeBundleAi(fullAt: 400000);
      BundleResult? result;
      await _pump(tester, _SheetHost(onResult: (r) => result = r), ai);
      await _openSheet(tester);

      await tester.tap(find.text('Furnish the room'));
      await _settle(tester);
      await tester.tap(find.text('Keep 2 pieces that fit'));
      await _settle(tester);

      expect(ai.calls, hasLength(1));
      expect(result!.items, hasLength(2));
      expect(result!.budgetAdvice.missesEssentials, isTrue);
    });

    testWidgets('an empty result offers the suggestion but nothing to keep', (tester) async {
      final ai = _FakeBundleAi(fullAt: 400000, empty: true);
      await _pump(tester, _SheetHost(onResult: (_) {}), ai);
      await _openSheet(tester);

      await tester.tap(find.text('Furnish the room'));
      await _settle(tester);

      expect(find.text('Use Rs 400,000'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Keep .*that fit')), findsNothing);
    });

    testWidgets('changing the budget or goal clears a stale notice', (tester) async {
      final ai = _FakeBundleAi(fullAt: 400000);
      await _pump(tester, _SheetHost(onResult: (_) {}), ai);
      await _openSheet(tester);

      await tester.tap(find.text('Furnish the room'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('budget-advice-notice')), findsOneWidget);
      await tester.tap(find.text('Skincare routine'));
      await tester.pump();
      expect(find.byKey(const ValueKey('budget-advice-notice')), findsNothing);
    });

    testWidgets('the notice fits at 320 px, text scale 2.0', (tester) async {
      final ai = _FakeBundleAi(fullAt: 400000);
      await _pump(tester, _SheetHost(onResult: (_) {}), ai, scale: 2, size: const Size(320, 700));
      await _openSheet(tester);

      await tester.tap(find.text('Furnish the room'));
      await _settle(tester);
      expect(find.byKey(const ValueKey('budget-advice-notice')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
