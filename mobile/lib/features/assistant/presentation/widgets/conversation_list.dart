import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/assistant_repository.dart';
import '../../data/chat_models.dart';
import '../../providers/chat_controller.dart';

/// Saved conversations with "New chat" and delete (confirm). Used as the
/// side panel on wide screens and as the history screen on phones.
class ConversationList extends ConsumerWidget {
  const ConversationList({super.key, required this.onSelect, required this.onNew, this.selectedId});

  final ValueChanged<ConversationSummary> onSelect;
  final VoidCallback onNew;
  final int? selectedId;

  Future<void> _delete(BuildContext context, WidgetRef ref, ConversationSummary c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversation?'),
        content: Text('"${c.title}" will be permanently deleted. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: context.colors.error, foregroundColor: context.colors.surface),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(assistantRepositoryProvider).deleteConversation(c.id);
      if (ref.read(chatControllerProvider).conversationId == c.id) {
        ref.read(chatControllerProvider.notifier).newChat();
      }
      ref.invalidate(conversationsProvider);
      if (context.mounted) AppSnack.success(context, 'Conversation deleted');
    } on ApiException catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(conversationsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.xs),
          child: AppButton.secondary(label: 'New chat', icon: Icons.add_rounded, expand: true, onPressed: onNew),
        ),
        Expanded(
          child: async.when(
            skipLoadingOnRefresh: true,
            loading: () => const SkeletonList(count: 6),
            error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(conversationsProvider)),
            data: (items) => items.isEmpty
                ? const EmptyState(
                    compact: true,
                    icon: Icons.forum_outlined,
                    title: 'No conversations yet',
                    message: 'Your chats with the assistant will appear here.',
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(conversationsProvider.future),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final c = items[i];
                        return _ConversationTile(
                          key: ValueKey(c.id),
                          conversation: c,
                          selected: c.id == selectedId,
                          onTap: () => onSelect(c),
                          onDelete: () => _delete(context, ref, c),
                        );
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    super.key,
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  final ConversationSummary conversation;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final c = conversation;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 1),
      child: Material(
        color: selected ? colors.aiSoft : Colors.transparent,
        borderRadius: AppRadii.inputAll,
        child: InkWell(
          borderRadius: AppRadii.inputAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, 0, AppSpacing.xs),
            child: Row(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 18, color: selected ? colors.ai : colors.muted),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelLarge!.copyWith(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
                      ),
                      if (c.lastMessage != null || c.updatedAt != null)
                        Text(
                          [Formatters.relative(c.updatedAt), ?c.lastMessage].where((s) => s.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall,
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete conversation',
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.muted),
                  style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
