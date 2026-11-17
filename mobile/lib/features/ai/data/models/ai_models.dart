import 'package:flutter/foundation.dart';

import '../../../../core/models/json_utils.dart';
import '../../../../core/models/product.dart';

typedef JsonMap = Map<String, dynamic>;

List<ProductSummary> _products(Object? v) => JsonX.asList(v, ProductSummary.fromJson);

/// 0..1 from either a ratio (0.42) or a percentage (42).
double _ratio(Object? v) {
  final d = JsonX.asDouble(v);
  final r = d > 1 ? d / 100 : d;
  return r.clamp(0.0, 1.0);
}

/// `GET /ai/recommendations` → `{ title, subtitle, products }`.
@immutable
class AiRecommendations {
  const AiRecommendations({required this.title, this.subtitle, this.products = const []});

  factory AiRecommendations.fromJson(Object? data) {
    // tolerate a bare list too
    if (data is List) return AiRecommendations(title: 'Picked for you', products: _products(data));
    final j = JsonX.asMap(data);
    return AiRecommendations(
      title: JsonX.asStringOrNull(j['title']) ?? 'Picked for you',
      subtitle: JsonX.asStringOrNull(j['subtitle']),
      products: _products(j['products']),
    );
  }

  final String title;
  final String? subtitle;
  final List<ProductSummary> products;
}

@immutable
class AspectCount {
  const AspectCount(this.aspect, this.mentions);

  factory AspectCount.fromJson(JsonMap j) =>
      AspectCount(JsonX.asString(j['aspect'] ?? j['label']), JsonX.asInt(j['mentions'] ?? j['count']));

  final String aspect;
  final int mentions;
}

/// `GET /ai/review-summary/:productId`.
@immutable
class ReviewSummary {
  const ReviewSummary({
    required this.reviewCount,
    required this.sentimentScore,
    required this.sentimentLabel,
    this.pros = const [],
    this.cons = const [],
    this.summary = '',
    this.highlights = const [],
  });

  factory ReviewSummary.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final s = JsonX.asMap(j['sentiment']);
    return ReviewSummary(
      reviewCount: JsonX.asInt(j['reviewCount']),
      sentimentScore: JsonX.asDouble(s['score']).clamp(-1.0, 1.0),
      sentimentLabel: JsonX.asStringOrNull(s['label']) ?? 'Mixed',
      pros: JsonX.asList(j['pros'], AspectCount.fromJson),
      cons: JsonX.asList(j['cons'], AspectCount.fromJson),
      summary: JsonX.asString(j['summary']),
      highlights: JsonX.asStringList(j['highlights']),
    );
  }

  final int reviewCount;

  /// -1..1
  final double sentimentScore;
  final String sentimentLabel;
  final List<AspectCount> pros;
  final List<AspectCount> cons;
  final String summary;
  final List<String> highlights;
}

@immutable
class CompareRow {
  const CompareRow({required this.label, required this.values, this.bestIndex});

  factory CompareRow.fromJson(JsonMap j) => CompareRow(
    label: JsonX.asString(j['label']),
    values: JsonX.asStringList(j['values']),
    bestIndex: JsonX.asIntOrNull(j['bestIndex']),
  );

  final String label;
  final List<String> values;
  final int? bestIndex;
}

@immutable
class VerdictPick {
  const VerdictPick({required this.label, required this.productId, this.reason = ''});

  factory VerdictPick.fromJson(JsonMap j) => VerdictPick(
    label: JsonX.asString(j['label']),
    productId: JsonX.asInt(j['productId']),
    reason: JsonX.asString(j['reason']),
  );

  final String label;
  final int productId;
  final String reason;
}

/// `POST /ai/compare` (also `meta.comparison` in chat replies).
@immutable
class CompareResult {
  const CompareResult({required this.products, this.rows = const [], this.summary = '', this.picks = const []});

  factory CompareResult.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final verdict = JsonX.asMap(j['verdict']);
    return CompareResult(
      products: _products(j['products']),
      rows: JsonX.asList(j['rows'], CompareRow.fromJson),
      summary: JsonX.asString(verdict['summary'] ?? j['summary']),
      picks: JsonX.asList(verdict['picks'], VerdictPick.fromJson),
    );
  }

  final List<ProductSummary> products;
  final List<CompareRow> rows;
  final String summary;
  final List<VerdictPick> picks;

  ProductSummary? productById(int id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// A chip in the smart-search interpretation (`{ type, label }`).
@immutable
class InterpretChip {
  const InterpretChip({required this.type, required this.label, this.value});

  factory InterpretChip.fromJson(JsonMap j) => InterpretChip(
    type: JsonX.asString(j['type'], 'keyword'),
    label: JsonX.asString(j['label']),
    value: JsonX.asStringOrNull(j['value']),
  );

  final String type;
  final String label;
  final String? value;
}

/// `GET /ai/search`.
@immutable
class SmartSearchResult {
  const SmartSearchResult({
    required this.interpretation,
    this.chips = const [],
    this.entities = const {},
    this.products = const [],
    this.total = 0,
    this.fallback = false,
  });

  factory SmartSearchResult.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final interp = j['interpretation'];
    final interpMap = JsonX.asMap(interp);
    final products = _products(j['products']);
    return SmartSearchResult(
      interpretation: interp is String ? interp : JsonX.asString(interpMap['text']),
      chips: JsonX.asList(interpMap['chips'] ?? j['chips'], InterpretChip.fromJson),
      entities: JsonX.asMap(j['entities']),
      products: products,
      total: JsonX.asInt(j['total'], products.length),
      fallback: JsonX.asBool(j['fallback']),
    );
  }

  final String interpretation;
  final List<InterpretChip> chips;
  final Map<String, dynamic> entities;
  final List<ProductSummary> products;
  final int total;
  final bool fallback;
}

@immutable
class IntentScore {
  const IntentScore(this.intent, this.confidence);

  factory IntentScore.fromJson(JsonMap j) => IntentScore(JsonX.asString(j['intent']), _ratio(j['confidence']));

  final String intent;
  final double confidence;
}

/// `POST /ai/nlu` (AI Lab playground).
@immutable
class NluResult {
  const NluResult({
    required this.intent,
    required this.confidence,
    this.alternatives = const [],
    this.entities = const {},
    this.tokens = const [],
    this.latencyMs,
    this.normalized,
    this.corrections = const [],
  });

  factory NluResult.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    return NluResult(
      intent: JsonX.asString(j['intent'], 'unknown'),
      confidence: _ratio(j['confidence']),
      alternatives: JsonX.asList(j['alternatives'], IntentScore.fromJson),
      entities: JsonX.asMap(j['entities']),
      tokens: JsonX.asStringList(j['tokens']),
      latencyMs: JsonX.asDoubleOrNull(j['latencyMs']),
      normalized: JsonX.asStringOrNull(j['normalized']),
      corrections: TypoCorrection.listFrom(j['corrections']),
    );
  }

  final String intent;
  final double confidence;
  final List<IntentScore> alternatives;
  final Map<String, dynamic> entities;
  final List<String> tokens;
  final double? latencyMs;

  /// Text after normalization (typo fixes, Roman-Urdu to English).
  final String? normalized;
  final List<TypoCorrection> corrections;

  /// The top intent followed by alternatives, without duplicates.
  List<IntentScore> get ranked {
    final out = <IntentScore>[IntentScore(intent, confidence)];
    for (final a in alternatives) {
      if (!out.any((o) => o.intent == a.intent)) out.add(a);
    }
    return out;
  }
}

/// `{ from: "samsng", to: "samsung" }`: a spelling fix applied by the NLU.
@immutable
class TypoCorrection {
  const TypoCorrection(this.from, this.to);

  static List<TypoCorrection> listFrom(Object? v) => JsonX.asList(
    v,
    (j) => TypoCorrection(JsonX.asString(j['from']), JsonX.asString(j['to'])),
  ).where((c) => c.from.isNotEmpty && c.to.isNotEmpty).toList();

  final String from;
  final String to;
}

@immutable
class FinderOption {
  const FinderOption({required this.label, required this.value});

  factory FinderOption.fromJson(JsonMap j) => FinderOption(label: JsonX.asString(j['label']), value: j['value'] ?? j['label']);

  final String label;

  /// String, number or `{min,max}` — sent back as-is.
  final Object? value;
}

enum FinderQuestionType { single, multi, budget }

@immutable
class FinderQuestion {
  const FinderQuestion({required this.id, required this.title, required this.type, this.options = const []});

  factory FinderQuestion.fromJson(JsonMap j) => FinderQuestion(
    id: JsonX.asString(j['id']),
    title: JsonX.asString(j['title'] ?? j['question']),
    type: switch (JsonX.asString(j['type'])) {
      'multi' => FinderQuestionType.multi,
      'budget' => FinderQuestionType.budget,
      _ => FinderQuestionType.single,
    },
    options: JsonX.asList(j['options'], FinderOption.fromJson),
  );

  final String id;
  final String title;
  final FinderQuestionType type;
  final List<FinderOption> options;
}

/// One department in `GET /ai/finder`.
@immutable
class FinderFlow {
  const FinderFlow({required this.department, required this.slug, required this.title, this.icon, this.questions = const []});

  factory FinderFlow.fromJson(JsonMap j) {
    final slug = JsonX.asString(j['slug'] ?? j['department']);
    return FinderFlow(
      department: JsonX.asString(j['department'], slug),
      slug: slug,
      title: JsonX.asString(j['title'] ?? j['department']),
      icon: JsonX.asStringOrNull(j['icon']),
      questions: JsonX.asList(j['questions'], FinderQuestion.fromJson),
    );
  }

  final String department;
  final String slug;
  final String title;
  final String? icon;
  final List<FinderQuestion> questions;
}

/// `POST /ai/finder` and similar `{ summary, products }` results.
@immutable
class AiProductsResult {
  const AiProductsResult({this.summary = '', this.products = const []});

  factory AiProductsResult.fromJson(Object? data) {
    if (data is List) return AiProductsResult(products: _products(data));
    final j = JsonX.asMap(data);
    return AiProductsResult(summary: JsonX.asString(j['summary']), products: _products(j['products']));
  }

  final String summary;
  final List<ProductSummary> products;
}

/// `GET /ai/insights` — kept mostly as maps so new backend fields just show up.
@immutable
class AiInsights {
  const AiInsights({
    this.intentModel = const {},
    this.embeddings = const {},
    this.llm = const {},
    this.recommender = const {},
    this.stats = const {},
    this.visual = const {},
    this.catalog = const {},
  });

  factory AiInsights.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    return AiInsights(
      intentModel: JsonX.asMap(j['intentModel']),
      embeddings: JsonX.asMap(j['embeddings']),
      llm: JsonX.asMap(j['llm']),
      recommender: JsonX.asMap(j['recommender']),
      stats: JsonX.asMap(j['stats']),
      visual: JsonX.asMap(j['visual']),
      catalog: JsonX.asMap(j['catalog']),
    );
  }

  final Map<String, dynamic> intentModel;
  final Map<String, dynamic> embeddings;
  final Map<String, dynamic> llm;
  final Map<String, dynamic> recommender;
  final Map<String, dynamic> stats;

  /// CLIP vision model behind Snap & Find.
  final Map<String, dynamic> visual;
  final Map<String, dynamic> catalog;
}

/// `POST /ai/visual-search`.
@immutable
class VisualSearchResult {
  const VisualSearchResult({this.products = const [], this.category, this.confidence = 0, this.latencyMs});

  factory VisualSearchResult.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final detected = JsonX.asMap(j['detected']);
    return VisualSearchResult(
      products: _products(j['products']),
      category: JsonX.asStringOrNull(detected['category'] is Map ? detected['category']['name'] : detected['category']),
      confidence: _ratio(detected['confidence']),
      latencyMs: JsonX.asIntOrNull(j['latencyMs']),
    );
  }

  final List<ProductSummary> products;
  final String? category;
  final double confidence;
  final int? latencyMs;
}

@immutable
class BundleItem {
  const BundleItem({required this.role, required this.product, this.alternatives = const []});

  factory BundleItem.fromJson(JsonMap j) => BundleItem(
    role: JsonX.asString(j['role'], 'Item'),
    product: ProductSummary.fromJson(JsonX.asMap(j['product'])),
    alternatives: _products(j['alternatives']),
  );

  final String role;
  final ProductSummary product;
  final List<ProductSummary> alternatives;

  BundleItem withProduct(ProductSummary next) {
    // the swapped-out product becomes an alternative so the user can undo
    final alts = [product, ...alternatives.where((a) => a.id != next.id)];
    return BundleItem(role: role, product: next, alternatives: alts);
  }
}

/// `POST /ai/bundle` (also `meta.bundle` in chat replies).
@immutable
class BundleResult {
  const BundleResult({
    required this.title,
    required this.budget,
    this.items = const [],
    this.explanation = '',
    this.savingsTips = const [],
    this.skippedRoles = const [],
  });

  factory BundleResult.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    return BundleResult(
      title: JsonX.asString(j['title'], 'Your bundle'),
      budget: JsonX.asDouble(j['budget']),
      items: JsonX.asList(j['items'], BundleItem.fromJson).where((i) => i.product.id != 0).toList(),
      explanation: JsonX.asString(j['explanation']),
      savingsTips: JsonX.asStringList(j['savingsTips']),
      skippedRoles: JsonX.asStringList(j['skippedRoles']),
    );
  }

  final String title;
  final double budget;
  final List<BundleItem> items;
  final String explanation;
  final List<String> savingsTips;

  /// Roles the budget couldn't cover.
  final List<String> skippedRoles;

  /// Recomputed locally so swaps update it.
  double get total => items.fold(0, (sum, i) => sum + i.product.price);
  double get remaining => budget - total;
  bool get overBudget => budget > 0 && total > budget;

  BundleResult swap(int index, ProductSummary next) => BundleResult(
    title: title,
    budget: budget,
    items: [for (var i = 0; i < items.length; i++) i == index ? items[i].withProduct(next) : items[i]],
    explanation: explanation,
    savingsTips: savingsTips,
    skippedRoles: skippedRoles,
  );
}

@immutable
class AnswerEvidence {
  const AnswerEvidence({required this.source, required this.text});

  factory AnswerEvidence.fromJson(JsonMap j) =>
      AnswerEvidence(source: JsonX.asString(j['source'], 'description'), text: JsonX.asString(j['text']));

  /// `spec` | `review` | `description`
  final String source;
  final String text;
}

/// `POST /ai/products/:id/ask`.
@immutable
class ProductAnswer {
  const ProductAnswer({required this.answer, this.confidence = 0, this.evidence = const [], this.followUps = const []});

  factory ProductAnswer.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    return ProductAnswer(
      answer: JsonX.asString(j['answer']),
      confidence: _ratio(j['confidence']),
      evidence: JsonX.asList(j['evidence'], AnswerEvidence.fromJson),
      followUps: JsonX.asStringList(j['followUps']),
    );
  }

  final String answer;
  final double confidence;
  final List<AnswerEvidence> evidence;
  final List<String> followUps;
}

@immutable
class SavingSwap {
  const SavingSwap({required this.productId, required this.alternative, required this.save, this.reason = ''});

  factory SavingSwap.fromJson(JsonMap j) => SavingSwap(
    productId: JsonX.asInt(j['productId']),
    alternative: ProductSummary.fromJson(JsonX.asMap(j['alternative'])),
    save: JsonX.asDouble(j['save']),
    reason: JsonX.asString(j['reason']),
  );

  final int productId;
  final ProductSummary alternative;
  final double save;
  final String reason;
}

@immutable
class FreeShippingGap {
  const FreeShippingGap({required this.remaining, this.suggestions = const []});

  final double remaining;
  final List<ProductSummary> suggestions;
}

/// `GET /ai/cart-insights`.
@immutable
class CartInsights {
  const CartInsights({this.savings = const [], this.completeTheSet = const [], this.freeShippingGap, this.summary = ''});

  factory CartInsights.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final gap = JsonX.asMapOrNull(j['freeShippingGap']);
    return CartInsights(
      savings: JsonX.asList(j['savings'], SavingSwap.fromJson).where((s) => s.alternative.id != 0).toList(),
      completeTheSet: _products(j['completeTheSet']),
      freeShippingGap: gap == null || JsonX.asDouble(gap['remaining']) <= 0
          ? null
          : FreeShippingGap(remaining: JsonX.asDouble(gap['remaining']), suggestions: _products(gap['suggestions'])),
      summary: JsonX.asString(j['summary']),
    );
  }

  final List<SavingSwap> savings;
  final List<ProductSummary> completeTheSet;
  final FreeShippingGap? freeShippingGap;
  final String summary;

  bool get isUseful => savings.isNotEmpty || completeTheSet.isNotEmpty || freeShippingGap != null;
  double get totalSavings => savings.fold(0, (s, e) => s + e.save);
}

@immutable
class ProfileTrait {
  const ProfileTrait({required this.label, required this.value, this.description = ''});

  factory ProfileTrait.fromJson(JsonMap j) => ProfileTrait(
    label: JsonX.asString(j['label']),
    value: _ratio(j['value']),
    description: JsonX.asString(j['description']),
  );

  final String label;
  final double value;
  final String description;
}

@immutable
class ShareItem {
  const ShareItem(this.name, this.share);

  factory ShareItem.fromJson(JsonMap j) => ShareItem(JsonX.asString(j['name'] ?? j['label']), _ratio(j['share']));

  final String name;

  /// 0..1
  final double share;
}

/// `GET /ai/profile` — the "Shopping DNA".
@immutable
class ShoppingProfile {
  const ShoppingProfile({
    required this.personaTitle,
    this.personaDescription = '',
    this.traits = const [],
    this.topCategories = const [],
    this.topBrands = const [],
    this.priceMin,
    this.priceMax,
    this.priceAvg,
    this.signals = const {},
    this.lastUpdated,
    this.howWeUseIt = const [],
  });

  factory ShoppingProfile.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final persona = JsonX.asMap(j['persona']);
    final band = JsonX.asMap(j['priceBand']);
    final signals = JsonX.asMap(j['signals']);
    return ShoppingProfile(
      personaTitle: JsonX.asString(persona['title'], 'New explorer'),
      personaDescription: JsonX.asString(persona['description']),
      traits: JsonX.asList(j['traits'], ProfileTrait.fromJson),
      topCategories: JsonX.asList(j['topCategories'], ShareItem.fromJson),
      topBrands: JsonX.asList(j['topBrands'], ShareItem.fromJson),
      priceMin: JsonX.asDoubleOrNull(band['min']),
      priceMax: JsonX.asDoubleOrNull(band['max']),
      priceAvg: JsonX.asDoubleOrNull(band['avg']),
      signals: {for (final e in signals.entries) e.key: JsonX.asInt(e.value)},
      lastUpdated: JsonX.asDate(j['lastUpdated']),
      howWeUseIt: JsonX.asStringList(j['howWeUseIt']),
    );
  }

  final String personaTitle;
  final String personaDescription;
  final List<ProfileTrait> traits;
  final List<ShareItem> topCategories;
  final List<ShareItem> topBrands;
  final double? priceMin;
  final double? priceMax;
  final double? priceAvg;
  final Map<String, int> signals;
  final DateTime? lastUpdated;

  /// Server-written explanation of how the profile is used.
  final List<String> howWeUseIt;

  int get totalSignals => signals.values.fold(0, (a, b) => a + b);

  /// Not enough activity yet to say anything meaningful.
  bool get isEmpty => totalSignals == 0 && traits.isEmpty && topCategories.isEmpty;
}
