import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/router/routes.dart';
import '../../auth/providers/auth_controller.dart';
import '../providers/chat_controller.dart';
import 'widgets/assistant_guest_view.dart';
import 'widgets/conversation_list.dart';

/// Chat history on phones (wide screens show it as the assistant's side panel).
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isAuthenticatedProvider);
    final selected = ref.watch(chatControllerProvider.select((s) => s.conversationId));
    return Scaffold(
      appBar: AppBar(title: const Text('Chat history')),
      body: !signedIn
          ? const AssistantGuestView(returnTo: Routes.conversations)
          : ConversationList(
              selectedId: selected,
              onNew: () {
                ref.read(chatControllerProvider.notifier).newChat();
                context.go(Routes.assistant);
              },
              onSelect: (c) {
                ref.read(chatControllerProvider.notifier).open(c.id);
                context.go(Routes.assistant);
              },
            ),
    );
  }
}
