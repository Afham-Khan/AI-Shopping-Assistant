import 'package:flutter/foundation.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/models/product.dart';
import '../../ai/data/models/ai_models.dart';
import '../../ai/data/models/shopping_models.dart';

/// An action button attached to an assistant reply.
///
/// Known types: `view_all` (query), `compare` (productIds), `add_to_cart`
/// (productId, quantity), `open_product` (productId), `view_order` (orderId),
/// `open_cart`. Unknown types render as nothing.
@immutable
class ChatAction {
  const ChatAction({
    required this.type,
    required this.label,
    this.query = const {},
    this.productIds = const [],
    this.productId,
    this.orderId,
    this.quantity = 1,
  });

  factory ChatAction.fromJson(Map<String, dynamic> j) => ChatAction(
    type: JsonX.asString(j['type']),
    label: JsonX.asString(j['label'], 'Open'),
    query: JsonX.asMap(j['query']),
    productIds: [for (final id in (j['productIds'] is List ? j['productIds'] as List : const [])) JsonX.asInt(id)],
    productId: JsonX.asIntOrNull(j['productId']),
    orderId: JsonX.asIntOrNull(j['orderId']),
    quantity: JsonX.asInt(j['quantity'], 1),
  );

  final String type;
  final String label;
  final Map<String, dynamic> query;
  final List<int> productIds;
  final int? productId;
  final int? orderId;
  final int quantity;
}

@immutable
class ChatClarify {
  const ChatClarify({required this.question, this.options = const []});

  final String question;
  final List<String> options;
}

/// `message.meta` of an assistant reply — everything is optional.
@immutable
class ChatMeta {
  const ChatMeta({
    this.intent,
    this.confidence,
    this.entities = const {},
    this.products = const [],
    this.suggestions = const [],
    this.actions = const [],
    this.comparison,
    this.clarify,
    this.bundle,
    this.explain,
    this.source,
    this.latencyMs,
    this.fallback = false,
    this.normalized,
    this.corrections = const [],
  });

  factory ChatMeta.fromJson(Map<String, dynamic> j) {
    final clarify = JsonX.asMapOrNull(j['clarify']);
    final comparison = JsonX.asMapOrNull(j['comparison']);
    final bundle = JsonX.asMapOrNull(j['bundle']);
    final explainJson = JsonX.asMapOrNull(j['explain'] ?? j['explainer'] ?? j['specExplainer']);
    final compare = comparison == null ? null : CompareResult.fromJson(comparison);
    final b = bundle == null ? null : BundleResult.fromJson(bundle);
    final explain = explainJson == null ? null : SpecExplainer.fromJson(explainJson);
    final nlu = JsonX.asMap(j['nlu']);
    return ChatMeta(
      intent: JsonX.asStringOrNull(j['intent']),
      confidence: JsonX.asDoubleOrNull(j['confidence']),
      entities: JsonX.asMap(j['entities']),
      products: JsonX.asList(j['products'], ProductSummary.fromJson),
      suggestions: JsonX.asStringList(j['suggestions']),
      actions: JsonX.asList(j['actions'], ChatAction.fromJson).where((a) => a.type.isNotEmpty).toList(),
      comparison: compare == null || compare.products.length < 2 ? null : compare,
      clarify: clarify == null
          ? null
          : ChatClarify(question: JsonX.asString(clarify['question']), options: JsonX.asStringList(clarify['options'])),
      bundle: b == null || b.items.isEmpty ? null : b,
      explain: explain == null || explain.isEmpty ? null : explain,
      source: JsonX.asStringOrNull(j['source']),
      latencyMs: JsonX.asIntOrNull(j['latencyMs']),
      fallback: JsonX.asBool(j['fallback']),
      normalized: JsonX.asStringOrNull(nlu['normalized']),
      corrections: TypoCorrection.listFrom(nlu['corrections']),
    );
  }

  final String? intent;
  final double? confidence;
  final Map<String, dynamic> entities;
  final List<ProductSummary> products;
  final List<String> suggestions;
  final List<ChatAction> actions;
  final CompareResult? comparison;
  final ChatClarify? clarify;
  final BundleResult? bundle;

  /// Plain-language spec explanation, when the assistant returns one.
  final SpecExplainer? explain;

  /// `local` | `gemini` | `groq`
  final String? source;
  final int? latencyMs;

  /// Constraints were relaxed to find results.
  final bool fallback;

  /// What the NLU understood after normalization / typo fixes.
  final String? normalized;
  final List<TypoCorrection> corrections;

  bool get hasReasoning => intent != null || source != null || entities.isNotEmpty;
}

/// A stored message (`{ id, role, content, createdAt, meta? }`).
@immutable
class ChatMessage {
  const ChatMessage({required this.id, required this.role, required this.content, this.createdAt, this.meta});

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final meta = JsonX.asMapOrNull(j['meta']);
    return ChatMessage(
      id: JsonX.asInt(j['id']),
      role: JsonX.asString(j['role'], 'assistant'),
      content: JsonX.asString(j['content']),
      createdAt: JsonX.asDate(j['createdAt']),
      meta: meta == null ? null : ChatMeta.fromJson(meta),
    );
  }

  final int id;
  final String role;
  final String content;
  final DateTime? createdAt;
  final ChatMeta? meta;

  bool get isUser => role == 'user';
}

/// `POST /ai/chat` response.
@immutable
class ChatReply {
  const ChatReply({required this.conversationId, required this.message, this.userMessage, this.title});

  factory ChatReply.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    final user = JsonX.asMapOrNull(j['userMessage']);
    return ChatReply(
      conversationId: JsonX.asInt(j['conversationId']),
      title: JsonX.asStringOrNull(j['title']),
      userMessage: user == null ? null : ChatMessage.fromJson(user),
      message: ChatMessage.fromJson(JsonX.asMap(j['message'])),
    );
  }

  final int conversationId;
  final String? title;
  final ChatMessage? userMessage;
  final ChatMessage message;
}

/// Row in `GET /ai/conversations`.
@immutable
class ConversationSummary {
  const ConversationSummary({required this.id, required this.title, this.lastMessage, this.updatedAt});

  factory ConversationSummary.fromJson(Map<String, dynamic> j) => ConversationSummary(
    id: JsonX.asInt(j['id']),
    title: JsonX.asStringOrNull(j['title']) ?? 'New chat',
    lastMessage: JsonX.asStringOrNull(j['lastMessage'] is Map ? j['lastMessage']['content'] : j['lastMessage']),
    updatedAt: JsonX.asDate(j['updatedAt'] ?? j['createdAt']),
  );

  final int id;
  final String title;
  final String? lastMessage;
  final DateTime? updatedAt;
}

/// `GET /ai/conversations/:id`.
@immutable
class ConversationDetail {
  const ConversationDetail({required this.id, required this.title, this.messages = const []});

  factory ConversationDetail.fromJson(Object? data) {
    final j = JsonX.asMap(data);
    return ConversationDetail(
      id: JsonX.asInt(j['id']),
      title: JsonX.asString(j['title'], 'Chat'),
      messages: JsonX.asList(j['messages'], ChatMessage.fromJson),
    );
  }

  final int id;
  final String title;
  final List<ChatMessage> messages;
}
