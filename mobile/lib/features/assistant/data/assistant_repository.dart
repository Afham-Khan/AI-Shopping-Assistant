import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json_utils.dart';
import '../../../core/network/api_client.dart';
import 'chat_models.dart';

/// Chat endpoints (`/ai/chat`, `/ai/conversations`, feedback). All require auth.
class AssistantRepository {
  AssistantRepository(this._api);

  final ApiClient _api;

  Future<ChatReply> send(String message, {int? conversationId}) => _api.post(
    '/ai/chat',
    body: {'message': message, 'conversationId': ?conversationId},
    decode: ChatReply.fromJson,
  );

  Future<List<ConversationSummary>> conversations() => _api.get(
    '/ai/conversations',
    decode: (d) => JsonX.asList(d is Map ? d['items'] ?? d['conversations'] : d, ConversationSummary.fromJson),
  );

  Future<ConversationDetail> conversation(int id) =>
      _api.get('/ai/conversations/$id', decode: ConversationDetail.fromJson);

  Future<void> deleteConversation(int id) => _api.delete<void>('/ai/conversations/$id');

  Future<void> feedback(int messageId, int rating) =>
      _api.post<void>('/ai/messages/$messageId/feedback', body: {'rating': rating});
}

final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => AssistantRepository(ref.watch(apiClientProvider)),
);
