import 'package:cartwise/core/network/api_client.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/features/ai/data/ai_repository.dart';
import 'package:cartwise/features/ai/data/models/ai_models.dart';
import 'package:cartwise/features/ai/presentation/visual_search_screen.dart';
import 'package:cartwise/features/ai/presentation/widgets/ai_product_widgets.dart';
import 'package:cartwise/features/auth/providers/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notesJson = {
  'recognized': false,
  'message': 'This looks like a page of handwritten notes, not something we sell. Try a clear photo of a product — shoes, a phone, a bag…',
  // a misbehaving server must still never put random products on screen
  'products': [
    {'id': 9, 'title': 'Random Laptop', 'slug': 'random-laptop', 'price': 1000, 'stock': 3},
  ],
  'detected': {'label': 'a page of handwritten notes', 'confidence': 0.87, 'category': null, 'alternatives': <Object>[]},
  'suggestions': ['Smartphones', 'Mens Shoes', 'Womens Bags'],
  'latencyMs': 120,
};

const _shoesJson = {
  'recognized': true,
  'message': null,
  'products': [
    {
      'id': 1,
      'title': 'Nike Air Jordan',
      'slug': 'nike-air-jordan',
      'price': 18000,
      'stock': 5,
      'match': {'score': 0.82, 'reasons': ['82% visual match']},
    },
  ],
  'detected': {
    'label': 'Mens Shoes',
    'category': {'slug': 'mens-shoes', 'name': 'Mens Shoes'},
    'confidence': 0.52,
    'alternatives': <Object>[],
  },
  'suggestions': <String>[],
  'latencyMs': 90,
};

class _FakeVisualAi extends AiRepository {
  _FakeVisualAi() : super(ApiClient(Dio()));

  final queries = <String>[];

  @override
  Future<VisualSearchResult> describeSearch(String text) async {
    queries.add(text);
    if (text.contains('notes')) {
      return VisualSearchResult.fromJson({
        'recognized': false,
        'message': "We couldn't find anything in the catalog that looks like “$text”. Try naming a product — shoes, a phone, a bag…",
        'products': <Object>[],
        'suggestions': ['Smartphones', 'Mens Shoes'],
        'latencyMs': 40,
      });
    }
    return VisualSearchResult.fromJson(_shoesJson);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester tester, Widget home, {AiRepository? ai, Size size = const Size(400, 1000)}) async {
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
        isAuthenticatedProvider.overrideWithValue(false),
        if (ai != null) aiRepositoryProvider.overrideWithValue(ai),
      ],
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await _settle(tester);
}

void main() {
  group('VisualSearchResult', () {
    test('an unrecognized photo carries label, message and suggestions and never products', () {
      final r = VisualSearchResult.fromJson(_notesJson);
      expect(r.recognized, isFalse);
      expect(r.products, isEmpty);
      expect(r.label, 'a page of handwritten notes');
      expect(r.category, isNull);
      expect(r.confidence, closeTo(0.87, 1e-9));
      expect(r.message, startsWith('This looks like a page of handwritten notes'));
      expect(r.suggestions, ['Smartphones', 'Mens Shoes', 'Womens Bags']);
    });

    test('recognized results and older payloads without the flag keep their products', () {
      final r = VisualSearchResult.fromJson(_shoesJson);
      expect(r.recognized, isTrue);
      expect(r.category, 'Mens Shoes');
      expect(r.label, 'Mens Shoes');
      expect(r.products.single.match?.score, closeTo(0.82, 1e-9));

      final legacy = VisualSearchResult.fromJson({
        'products': _shoesJson['products'],
        'detected': {'category': {'slug': 'mens-shoes', 'name': 'Mens Shoes'}, 'confidence': 0.9},
      });
      expect(legacy.recognized, isTrue);
      expect(legacy.products, hasLength(1));
    });

    test('confidence words stay honest', () {
      expect(VisualSearchResult.confidenceWord(0.9), 'Confident');
      expect(VisualSearchResult.confidenceWord(0.52), 'Fairly sure');
      expect(VisualSearchResult.confidenceWord(0.2), 'Best guess');
    });
  });

  group('VisualNoMatch', () {
    testWidgets('shows what the photo looks like, the message, retry and category chips', (tester) async {
      var retried = 0;
      final picked = <String>[];
      await _pump(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: VisualNoMatch(
              result: VisualSearchResult.fromJson(_notesJson),
              onTryAnother: () => retried++,
              onSuggestion: picked.add,
              describe: const Text('Describe it instead'),
            ),
          ),
        ),
      );

      expect(find.text("That's not something we sell"), findsOneWidget);
      expect(find.text('Looks like a page of handwritten notes'), findsOneWidget);
      expect(find.text('87% likely'), findsOneWidget);
      expect(find.textContaining('not something we sell. Try a clear photo'), findsOneWidget);
      expect(find.text('Describe it instead'), findsOneWidget);
      expect(find.text('Popular categories'), findsOneWidget);
      expect(find.byType(AiProductTile), findsNothing);

      await tester.tap(find.text('Try another photo'));
      expect(retried, 1);
      await tester.tap(find.text('Mens Shoes'));
      expect(picked, ['Mens Shoes']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a narrow phone at large text without overflow', (tester) async {
      await _pump(
        tester,
        MediaQuery.withClampedTextScaling(
          minScaleFactor: 1.6,
          maxScaleFactor: 1.6,
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: VisualNoMatch(
                result: VisualSearchResult.fromJson(_notesJson),
                onTryAnother: () {},
                onSuggestion: (_) {},
              ),
            ),
          ),
        ),
        size: const Size(320, 1400),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Try another photo'), findsOneWidget);
    });
  });

  group('VisualSearchScreen', () {
    testWidgets('an unrecognized description shows the no-match state, a chip searches again', (tester) async {
      final ai = _FakeVisualAi();
      await _pump(tester, const VisualSearchScreen(), ai: ai);

      await tester.enterText(find.byType(TextField), 'my class notes');
      await tester.tap(find.text('Find'));
      await _settle(tester);

      expect(ai.queries, ['my class notes']);
      expect(find.text('Nothing in the catalog looks like that'), findsOneWidget);
      expect(find.text('Try a photo'), findsOneWidget);
      expect(find.text('Describe it instead'), findsOneWidget);
      expect(find.byType(AiProductTile), findsNothing);

      await tester.ensureVisible(find.text('Mens Shoes'));
      await tester.tap(find.text('Mens Shoes'));
      await _settle(tester);

      expect(ai.queries.last, 'Mens Shoes');
      expect(find.text('Nothing in the catalog looks like that'), findsNothing);
      expect(find.byType(AiProductTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
