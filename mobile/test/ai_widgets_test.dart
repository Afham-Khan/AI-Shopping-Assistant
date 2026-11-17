import 'package:cartwise/core/models/product.dart';
import 'package:cartwise/core/storage/local_storage.dart';
import 'package:cartwise/core/theme/app_theme.dart';
import 'package:cartwise/features/ai/data/models/ai_models.dart';
import 'package:cartwise/features/ai/presentation/widgets/compare_table.dart';
import 'package:cartwise/features/assistant/data/chat_models.dart';
import 'package:cartwise/features/assistant/presentation/widgets/chat_message_tile.dart';
import 'package:cartwise/features/assistant/providers/chat_controller.dart';
import 'package:cartwise/features/auth/providers/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _p1 = ProductSummary(
  id: 1,
  title: 'Realme C35',
  slug: 'realme-c35',
  brand: 'Realme',
  price: 41999,
  rating: 3.6,
  ratingCount: 8,
  stock: 10,
  match: ProductMatch(score: 0.58, reasons: ['15% off — save Rs 7,600']),
);

const _p2 = ProductSummary(id: 2, title: 'Infinix Hot 30', slug: 'infinix-hot-30', brand: 'Infinix', price: 44999, stock: 5);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Map<String, Object> prefs = const {},
  double textScale = 1,
  Size size = const Size(400, 1000),
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sp),
        isAuthenticatedProvider.overrideWithValue(false),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery.withClampedTextScaling(
          minScaleFactor: textScale,
          maxScaleFactor: textScale,
          child: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: child)),
        ),
      ),
    ),
  );
  await tester.pump();
}

ChatEntry _assistant({ChatMeta? meta}) => ChatEntry(
  key: 'm2',
  id: 2,
  isUser: false,
  content: 'Here are **2 phones** near Rs 30,000:\n- Great battery\n- Big screen',
  meta: meta,
);

const _meta = ChatMeta(
  intent: 'budget_query',
  confidence: 0.71,
  entities: {'category': 'smartphones', 'budget': {'max': 30000}},
  products: [_p1, _p2],
  suggestions: ['Show cheaper options', 'Only Realme'],
  actions: [
    ChatAction(type: 'view_all', label: 'See all 15 results', query: {'category': 'smartphones'}),
    ChatAction(type: 'mystery', label: 'Unknown action'),
  ],
  source: 'local',
  latencyMs: 164,
);

void main() {
  setUpAll(() => AppTheme.useGoogleFonts = false);

  testWidgets('user bubble shows text and a retry for failed messages', (tester) async {
    await _pump(
      tester,
      const ChatMessageTile(
        entry: ChatEntry(key: 'l1', isUser: true, content: 'sasta mobile chahiye 30k tak', status: ChatStatus.failed),
      ),
    );
    expect(find.text('sasta mobile chahiye 30k tak'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('assistant reply renders markdown, products, chips and supported actions', (tester) async {
    final sent = <String>[];
    await _pump(tester, ChatMessageTile(entry: _assistant(meta: _meta), isLatest: true, onSend: sent.add));
    await tester.pumpAndSettle();

    // markdown: bold span + bullets rendered as plain text
    expect(find.textContaining('2 phones', findRichText: true), findsOneWidget);
    expect(find.textContaining('Great battery', findRichText: true), findsOneWidget);
    // carousel + why-this only on the product with a match
    expect(find.text('Infinix Hot 30'), findsOneWidget);
    expect(find.text('Why this?'), findsOneWidget);
    // supported action only
    expect(find.text('See all 15 results'), findsOneWidget);
    expect(find.text('Unknown action'), findsNothing);
    // reasoning hidden by default
    expect(find.text('reasoning'), findsNothing);

    await tester.tap(find.text('Show cheaper options'));
    expect(sent, ['Show cheaper options']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quick replies only on the latest reply; reasoning panel when enabled', (tester) async {
    await _pump(
      tester,
      ChatMessageTile(entry: _assistant(meta: _meta), onSend: (_) {}),
      prefs: {'ai.showReasoning': true},
    );
    await tester.pumpAndSettle();
    expect(find.text('Show cheaper options'), findsNothing);
    expect(find.text('reasoning'), findsOneWidget);
    expect(find.text('budget_query'), findsOneWidget);
    expect(find.text('164 ms'), findsOneWidget);
    expect(find.text('local nlu'), findsOneWidget);
  });

  testWidgets('assistant reply does not overflow at 320 px and 2x text', (tester) async {
    await _pump(
      tester,
      ChatMessageTile(entry: _assistant(meta: _meta), isLatest: true, onSend: (_) {}),
      size: const Size(320, 1400),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('compare table', () {
    const result = CompareResult(
      products: [_p1, _p2],
      rows: [
        CompareRow(label: 'Price', values: ['Rs 41,999', 'Rs 44,999'], bestIndex: 0),
        CompareRow(label: 'RAM', values: ['4 GB', '8 GB'], bestIndex: 1),
        CompareRow(label: 'Color', values: ['Gold', ''], bestIndex: null),
      ],
      summary: 'Realme is the best value.',
      picks: [VerdictPick(label: 'Best value', productId: 1, reason: 'Cheapest with solid ratings')],
    );

    testWidgets('aligns values and highlights the best per row', (tester) async {
      await _pump(tester, const CompareTable(result: result));
      expect(find.text('PRICE'), findsOneWidget);
      expect(find.text('RAM'), findsOneWidget);
      expect(find.text('8 GB'), findsOneWidget);
      // empty value → dash; one best marker per row with a bestIndex
      expect(find.text('—'), findsOneWidget);
      expect(find.byIcon(Icons.verified_rounded), findsNWidgets(2));
      expect(find.bySemanticsLabel('Rs 41,999, best'), findsOneWidget);
    });

    testWidgets('verdict cards show the pick with its product', (tester) async {
      await _pump(tester, const VerdictCards(result: result));
      await tester.pumpAndSettle();
      expect(find.text('Best value'), findsOneWidget);
      expect(find.text('Cheapest with solid ratings'), findsOneWidget);
      expect(find.text('Realme C35'), findsOneWidget);
    });

    test('column width fits 2 on a phone and scrolls for 4', () {
      expect(compareColumnWidth(360, 2), 180);
      expect(compareColumnWidth(360, 4), 140);
      expect(compareColumnWidth(1000, 4), 250);
    });
  });

  test('chat meta parses the live backend shape leniently', () {
    final meta = ChatMeta.fromJson({
      'intent': 'budget_query',
      'confidence': '0.705',
      'entities': {'category': 'smartphones', 'ordinals': null},
      'products': [
        {'id': 128, 'title': 'Realme C35', 'price': 41999, 'match': {'score': 0.583, 'reasons': ['15% off']}},
      ],
      'actions': [
        {'type': 'view_all', 'label': 'See all', 'query': {'category': 'smartphones', 'maxPrice': 30000}},
        {'type': 'compare', 'label': 'Compare', 'productIds': [128, '130']},
      ],
      'comparison': null,
      'bundle': null,
      'clarify': {'question': 'Who is it for?', 'options': ['Mom', 'Dad']},
      'nlu': {'normalized': 'cheap mobile want upto 30k', 'corrections': [{'from': 'mobil', 'to': 'mobile'}]},
      'fallback': true,
      'source': 'local',
      'latencyMs': 164,
    });
    expect(meta.confidence, closeTo(0.705, 1e-9));
    expect(meta.products.single.match!.score, closeTo(0.583, 1e-9));
    expect(meta.actions[1].productIds, [128, 130]);
    expect(meta.clarify!.options, ['Mom', 'Dad']);
    expect(meta.normalized, 'cheap mobile want upto 30k');
    expect(meta.corrections.single.to, 'mobile');
    expect(meta.fallback, isTrue);
    expect(meta.comparison, isNull);
  });
}
