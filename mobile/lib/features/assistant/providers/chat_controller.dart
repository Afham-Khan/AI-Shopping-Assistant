import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/storage/local_storage.dart';
import '../../auth/providers/auth_controller.dart';
import '../data/assistant_repository.dart';
import '../data/chat_models.dart';

enum ChatStatus { sending, failed, sent }

/// One bubble in the transcript. Immutable; [key] is stable for the list.
@immutable
class ChatEntry {
  const ChatEntry({
    required this.key,
    required this.isUser,
    required this.content,
    this.id,
    this.meta,
    this.status = ChatStatus.sent,
    this.createdAt,
    this.fresh = false,
    this.feedback,
    this.error,
  });

  factory ChatEntry.fromMessage(ChatMessage m, {bool fresh = false}) => ChatEntry(
    key: 'm${m.id}',
    id: m.id,
    isUser: m.isUser,
    content: m.content,
    meta: m.meta,
    createdAt: m.createdAt,
    fresh: fresh,
  );

  final String key;
  final int? id;
  final bool isUser;
  final String content;
  final ChatMeta? meta;
  final ChatStatus status;
  final DateTime? createdAt;

  /// Just received → reveal progressively (once).
  final bool fresh;

  /// 1 / -1 once rated.
  final int? feedback;
  final ApiException? error;

  ChatEntry copyWith({int? id, ChatStatus? status, int? feedback, ApiException? error, bool clearError = false}) =>
      ChatEntry(
        key: key,
        id: id ?? this.id,
        isUser: isUser,
        content: content,
        meta: meta,
        status: status ?? this.status,
        createdAt: createdAt,
        fresh: fresh,
        feedback: feedback ?? this.feedback,
        error: clearError ? null : (error ?? this.error),
      );
}

@immutable
class ChatState {
  const ChatState({
    this.conversationId,
    this.title,
    this.entries = const [],
    this.sending = false,
    this.loading = false,
    this.loadError,
  });

  final int? conversationId;
  final String? title;

  /// Chronological (oldest first).
  final List<ChatEntry> entries;
  final bool sending;
  final bool loading;
  final Object? loadError;

  bool get isEmpty => entries.isEmpty && !loading && loadError == null;

  ChatState copyWith({
    int? conversationId,
    String? title,
    List<ChatEntry>? entries,
    bool? sending,
    bool? loading,
    Object? loadError,
    bool clearError = false,
  }) => ChatState(
    conversationId: conversationId ?? this.conversationId,
    title: title ?? this.title,
    entries: entries ?? this.entries,
    sending: sending ?? this.sending,
    loading: loading ?? this.loading,
    loadError: clearError ? null : (loadError ?? this.loadError),
  );
}

/// The open conversation. Kept alive with the assistant tab; reset on logout.
///
/// ```dart
/// ref.read(chatControllerProvider.notifier).send('sasta mobile chahiye 30k tak');
/// ```
final chatControllerProvider = NotifierProvider<ChatController, ChatState>(ChatController.new);

class ChatController extends Notifier<ChatState> {
  int _epoch = 0;
  int _localSeq = 0;
  final _revealed = <String>{};

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  @override
  ChatState build() {
    ref.watch(isAuthenticatedProvider);
    _epoch++;
    _revealed.clear();
    return const ChatState();
  }

  /// Whether [entry] should still play its reveal animation.
  bool shouldReveal(ChatEntry entry) => entry.fresh && !_revealed.contains(entry.key);

  void markRevealed(String key) => _revealed.add(key);

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty || state.sending) return;
    final epoch = _epoch;
    final local = ChatEntry(
      key: 'local${_localSeq++}',
      isUser: true,
      content: message,
      status: ChatStatus.sending,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(entries: [...state.entries, local], sending: true, clearError: true);
    await _deliver(local, epoch);
  }

  /// Re-sends a failed message, keeping its text.
  Future<void> retry(String key) async {
    if (state.sending) return;
    final index = state.entries.indexWhere((e) => e.key == key);
    if (index < 0) return;
    final epoch = _epoch;
    final entry = state.entries[index].copyWith(status: ChatStatus.sending, clearError: true);
    final entries = [...state.entries]..removeAt(index);
    state = state.copyWith(entries: [...entries, entry], sending: true);
    await _deliver(entry, epoch);
  }

  Future<void> _deliver(ChatEntry local, int epoch) async {
    try {
      final reply = await _repo.send(local.content, conversationId: state.conversationId);
      if (!ref.mounted || epoch != _epoch) return;
      final sentUser = local.copyWith(id: reply.userMessage?.id, status: ChatStatus.sent);
      final assistant = ChatEntry.fromMessage(reply.message, fresh: true);
      state = state.copyWith(
        conversationId: reply.conversationId == 0 ? state.conversationId : reply.conversationId,
        title: reply.title,
        entries: [
          for (final e in state.entries)
            if (e.key == local.key) sentUser else e,
          assistant,
        ],
        sending: false,
      );
      ref.invalidate(conversationsProvider);
    } on ApiException catch (e) {
      if (!ref.mounted || epoch != _epoch) return;
      state = state.copyWith(
        entries: [
          for (final x in state.entries)
            if (x.key == local.key) x.copyWith(status: ChatStatus.failed, error: e) else x,
        ],
        sending: false,
      );
    }
  }

  /// Opens a saved conversation (no-op when it's already open).
  Future<void> open(int conversationId, {bool force = false}) async {
    if (!force && state.conversationId == conversationId && state.loadError == null && state.entries.isNotEmpty) return;
    final epoch = ++_epoch;
    state = ChatState(conversationId: conversationId, loading: true);
    try {
      final detail = await _repo.conversation(conversationId);
      if (!ref.mounted || epoch != _epoch) return;
      state = ChatState(
        conversationId: detail.id == 0 ? conversationId : detail.id,
        title: detail.title,
        entries: [for (final m in detail.messages) ChatEntry.fromMessage(m)],
      );
    } on ApiException catch (e) {
      if (!ref.mounted || epoch != _epoch) return;
      state = ChatState(conversationId: conversationId, loadError: e);
    }
  }

  void newChat() {
    _epoch++;
    state = const ChatState();
  }

  /// Thumbs up/down (optimistic; reverts on failure).
  Future<void> rate(String key, int rating) async {
    final entry = state.entries.where((e) => e.key == key).firstOrNull;
    if (entry == null || entry.id == null) return;
    final previous = entry.feedback;
    _replace(key, (e) => e.copyWith(feedback: rating));
    try {
      await _repo.feedback(entry.id!, rating);
    } on ApiException {
      if (ref.mounted) {
        _replace(key, (e) => ChatEntry(
          key: e.key,
          id: e.id,
          isUser: e.isUser,
          content: e.content,
          meta: e.meta,
          createdAt: e.createdAt,
          fresh: e.fresh,
          feedback: previous,
        ));
      }
      rethrow;
    }
  }

  void _replace(String key, ChatEntry Function(ChatEntry) update) {
    state = state.copyWith(entries: [for (final e in state.entries) e.key == key ? update(e) : e]);
  }
}

/// Saved conversations (newest first). Empty for guests.
final conversationsProvider = FutureProvider.autoDispose<List<ConversationSummary>>((ref) async {
  if (!ref.watch(isAuthenticatedProvider)) return const [];
  final list = await ref.watch(assistantRepositoryProvider).conversations();
  return [...list]..sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
});

/// "Show AI reasoning" toggle, persisted.
final showReasoningProvider = NotifierProvider<ShowReasoningController, bool>(ShowReasoningController.new);

class ShowReasoningController extends Notifier<bool> {
  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(StorageKeys.aiShowReasoning) ?? false;

  Future<void> toggle() async {
    state = !state;
    await ref.read(sharedPreferencesProvider).setBool(StorageKeys.aiShowReasoning, state);
  }
}
