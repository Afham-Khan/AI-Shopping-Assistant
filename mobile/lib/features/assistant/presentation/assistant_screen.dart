import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../../ai/presentation/widgets/ai_ui.dart';
import '../../auth/providers/auth_controller.dart';
import '../providers/chat_controller.dart';
import 'widgets/assistant_guest_view.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_tile.dart';
import 'widgets/conversation_list.dart';
import 'widgets/typing_indicator.dart';
import 'widgets/welcome_view.dart';

/// The AI assistant tab. `?c=<id>` opens a saved conversation and
/// `?prompt=` / `?q=` sends a first message (the Home hero bar uses it).
/// Two panes (history + chat) from 1000 px; guests see a sign-in prompt.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key, this.conversationId, this.initialPrompt});

  final int? conversationId;
  final String? initialPrompt;

  static const twoPaneWidth = 1000.0;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _scroll = ScrollController();
  String? _handledPrompt;

  ChatController get _chat => ref.read(chatControllerProvider.notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyRoute());
  }

  @override
  void didUpdateWidget(AssistantScreen old) {
    super.didUpdateWidget(old);
    if (old.conversationId != widget.conversationId || old.initialPrompt != widget.initialPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyRoute());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _applyRoute() {
    if (!mounted || !ref.read(isAuthenticatedProvider)) return;
    final id = widget.conversationId;
    if (id != null && ref.read(chatControllerProvider).conversationId != id) _chat.open(id);

    final prompt = widget.initialPrompt?.trim();
    if (prompt != null && prompt.isNotEmpty && prompt != _handledPrompt) {
      _handledPrompt = prompt;
      // a deep-linked prompt starts a fresh chat unless a conversation was named
      if (id == null) _chat.newChat();
      _send(prompt);
      // drop the prompt from the URL so back/forward doesn't resend it
      context.go(Routes.assistantWith(conversationId: id));
    } else if (prompt == null || prompt.isEmpty) {
      _handledPrompt = null;
    }
  }

  void _send(String text) {
    _chat.send(text);
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: context.motion(AppDurations.normal), curve: AppCurves.standard);
    }
  }

  void _newChat() {
    _chat.newChat();
    if (widget.conversationId != null) context.go(Routes.assistant);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isAuthenticatedProvider);
    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const _AssistantTitle()),
        body: const AssistantGuestView(),
      );
    }

    // run route intent once the user signs in from the guest view
    ref.listen(isAuthenticatedProvider, (prev, next) {
      if (next && prev != true) WidgetsBinding.instance.addPostFrameCallback((_) => _applyRoute());
    });

    final showReasoning = ref.watch(showReasoningProvider);
    final selectedId = ref.watch(chatControllerProvider.select((s) => s.conversationId));

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= AssistantScreen.twoPaneWidth;
        final chat = _ChatPane(scroll: _scroll, onSend: _send);
        return Scaffold(
          appBar: AppBar(
            title: const _AssistantTitle(),
            actions: [
              IconButton(
                tooltip: showReasoning ? 'Hide AI reasoning' : 'Show AI reasoning',
                isSelected: showReasoning,
                onPressed: () => ref.read(showReasoningProvider.notifier).toggle(),
                icon: Icon(
                  showReasoning ? Icons.psychology_alt_rounded : Icons.psychology_alt_outlined,
                  color: showReasoning ? context.colors.ai : null,
                ),
              ),
              if (!twoPane) ...[
                IconButton(tooltip: 'New chat', onPressed: _newChat, icon: const Icon(Icons.edit_square)),
                IconButton(
                  tooltip: 'Chat history',
                  onPressed: () => context.push(Routes.conversations),
                  icon: const Icon(Icons.history_rounded),
                ),
              ],
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          body: twoPane
              ? Row(
                  children: [
                    SizedBox(
                      width: 300,
                      child: ConversationList(
                        selectedId: selectedId,
                        onNew: _newChat,
                        onSelect: (c) => _chat.open(c.id),
                      ),
                    ),
                    VerticalDivider(width: 1, color: context.colors.border),
                    Expanded(child: chat),
                  ],
                )
              : chat,
        );
      },
    );
  }
}

class _AssistantTitle extends ConsumerWidget {
  const _AssistantTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = ref.watch(chatControllerProvider.select((s) => s.title));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AiAvatar(size: 28),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${AppConfig.appName} AI', maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                title ?? 'Shopping assistant',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatPane extends ConsumerWidget {
  const _ChatPane({required this.scroll, required this.onSend});

  final ScrollController scroll;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sending = ref.watch(chatControllerProvider.select((s) => s.sending));
    return Column(
      children: [
        Expanded(child: _Transcript(scroll: scroll, onSend: onSend)),
        ChatInputBar(
          sending: sending,
          onSend: onSend,
          onImage: () => context.push(Routes.visualSearch),
        ),
      ],
    );
  }
}

class _Transcript extends ConsumerStatefulWidget {
  const _Transcript({required this.scroll, required this.onSend});

  final ScrollController scroll;
  final ValueChanged<String> onSend;

  @override
  ConsumerState<_Transcript> createState() => _TranscriptState();
}

class _TranscriptState extends ConsumerState<_Transcript> {
  bool _showJump = false;

  @override
  void initState() {
    super.initState();
    widget.scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scroll.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    // reversed list: offset 0 is the newest message
    final show = widget.scroll.hasClients && widget.scroll.offset > 400;
    if (show != _showJump) setState(() => _showJump = show);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    if (state.loading) return const _TranscriptSkeleton();
    if (state.loadError != null) {
      return ErrorState(
        error: state.loadError,
        onRetry: () => ref.read(chatControllerProvider.notifier).open(state.conversationId!, force: true),
      );
    }
    if (state.entries.isEmpty && !state.sending) return WelcomeView(onPrompt: widget.onSend);

    final entries = state.entries;
    final typing = state.sending ? 1 : 0;
    final count = entries.length + typing;
    final latestAssistant = entries.lastIndexWhere((e) => !e.isUser);
    final keyIndex = <String, int>{
      for (var i = 0; i < entries.length; i++) entries[i].key: entries.length - 1 - i + typing,
    };

    return Stack(
      children: [
        ListView.builder(
          controller: widget.scroll,
          reverse: true,
          padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.md, context.pagePadding, AppSpacing.md),
          itemCount: count,
          findChildIndexCallback: (key) => key is ValueKey<String> ? (key.value == '_typing' ? 0 : keyIndex[key.value]) : null,
          itemBuilder: (context, index) {
            if (typing == 1 && index == 0) {
              return const _Row(key: ValueKey('_typing'), child: SlideFadeIn(child: TypingIndicator()));
            }
            final i = entries.length - 1 - (index - typing);
            final entry = entries[i];
            return _Row(
              key: ValueKey(entry.key),
              child: ChatMessageTile(
                entry: entry,
                isLatest: i == latestAssistant && i == entries.length - 1 && !state.sending,
                onSend: widget.onSend,
              ),
            );
          },
        ),
        Positioned(
          right: context.pagePadding,
          bottom: AppSpacing.md,
          child: AnimatedScale(
            scale: _showJump ? 1 : 0,
            duration: context.motion(AppDurations.fast),
            child: FloatingActionButton.small(
              heroTag: null,
              tooltip: 'Scroll to latest',
              onPressed: () => widget.scroll.animateTo(
                0,
                duration: context.motion(AppDurations.slow),
                curve: AppCurves.standard,
              ),
              child: const Icon(Icons.arrow_downward_rounded),
            ),
          ),
        ),
      ],
    );
  }
}

/// Centers a transcript row and caps its width on wide screens.
class _Row extends StatelessWidget {
  const _Row({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 820), child: child),
      ),
    );
  }
}

class _TranscriptSkeleton extends StatelessWidget {
  const _TranscriptSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(context.pagePadding),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        Align(alignment: Alignment.centerRight, child: Skeleton(width: 180, height: 40, borderRadius: AppRadii.cardAll)),
        AppSpacing.gapLg,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton.circle(size: 30),
            AppSpacing.gapSm,
            Expanded(child: SkeletonText(lines: 4)),
          ],
        ),
        AppSpacing.gapLg,
        Align(alignment: Alignment.centerRight, child: Skeleton(width: 140, height: 40, borderRadius: AppRadii.cardAll)),
        AppSpacing.gapLg,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Skeleton.circle(size: 30),
            AppSpacing.gapSm,
            Expanded(child: SkeletonText(lines: 3)),
          ],
        ),
      ],
    );
  }
}
