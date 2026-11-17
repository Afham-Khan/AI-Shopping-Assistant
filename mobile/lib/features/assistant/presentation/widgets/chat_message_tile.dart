import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../ai/data/models/ai_models.dart';
import '../../../ai/presentation/ai_actions.dart';
import '../../../ai/presentation/widgets/ai_product_widgets.dart';
import '../../../ai/presentation/widgets/ai_ui.dart';
import '../../../ai/presentation/widgets/bundle_view.dart';
import '../../../ai/presentation/widgets/compare_table.dart';
import '../../../ai/presentation/widgets/spec_explainer.dart';
import '../../data/chat_models.dart';
import '../../providers/chat_controller.dart';
import '../chat_actions.dart';
import 'reasoning_panel.dart';
import 'reveal_markdown.dart';

/// One transcript row: a user bubble or an assistant reply with its extras.
class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile({super.key, required this.entry, this.isLatest = false, this.onSend});

  final ChatEntry entry;

  /// Only the latest reply shows quick replies / clarify options.
  final bool isLatest;
  final ValueChanged<String>? onSend;

  @override
  Widget build(BuildContext context) {
    return entry.isUser
        ? UserBubble(entry: entry)
        : AssistantMessage(entry: entry, isLatest: isLatest, onSend: onSend);
  }
}

class UserBubble extends ConsumerWidget {
  const UserBubble({super.key, required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final failed = entry.status == ChatStatus.failed;
    final sending = entry.status == ChatStatus.sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: (context.screenWidth * 0.8).clamp(200, 560)),
            child: AnimatedOpacity(
              opacity: sending ? 0.75 : 1,
              duration: context.motion(AppDurations.fast),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: failed ? colors.error.withValues(alpha: 0.12) : colors.primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: SelectableText(
                  entry.content,
                  style: context.textTheme.bodyMedium!.copyWith(
                    color: failed ? colors.text : colors.onPrimary,
                    height: 1.45,
                  ),
                ),
              ),
            ),
          ),
        ),
        if (failed)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 14, color: colors.error),
                const SizedBox(width: 4),
                Text(
                  entry.error?.message ?? 'Not sent',
                  style: context.textTheme.labelSmall!.copyWith(color: colors.error),
                ),
                TextButton.icon(
                  onPressed: () => ref.read(chatControllerProvider.notifier).retry(entry.key),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 36)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class AssistantMessage extends ConsumerStatefulWidget {
  const AssistantMessage({super.key, required this.entry, this.isLatest = false, this.onSend});

  final ChatEntry entry;
  final bool isLatest;
  final ValueChanged<String>? onSend;

  @override
  ConsumerState<AssistantMessage> createState() => _AssistantMessageState();
}

class _AssistantMessageState extends ConsumerState<AssistantMessage> {
  // read once in initState so dispose() never touches ref (unsafe once the widget is deactivated)
  late final ChatController _chat;
  late final bool _animate;
  late bool _revealed;

  @override
  void initState() {
    super.initState();
    _chat = ref.read(chatControllerProvider.notifier);
    _animate = _chat.shouldReveal(widget.entry);
    _revealed = !_animate;
  }

  void _onRevealed() {
    if (!mounted) return;
    _chat.markRevealed(widget.entry.key);
    if (!_revealed) setState(() => _revealed = true);
  }

  @override
  void dispose() {
    // scrolled away mid-reveal: don't replay it later
    if (_animate) _chat.markRevealed(widget.entry.key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final meta = entry.meta;
    final showReasoning = ref.watch(showReasoningProvider);
    final send = widget.onSend;
    final extrasAnimate = _animate;

    final extras = <Widget>[];
    if (meta != null && _revealed) {
      if (meta.products.isNotEmpty) {
        extras.add(
          AiProductRail(products: meta.products, source: 'assistant', padding: EdgeInsets.zero, animate: extrasAnimate),
        );
      }
      if (meta.comparison != null) extras.add(_ComparisonCard(result: meta.comparison!));
      if (meta.explain != null) extras.add(SpecExplainerCard(data: meta.explain!));
      if (meta.bundle != null) {
        extras.add(AiCard(child: BundleView(bundle: meta.bundle!, compact: true, source: 'assistant', animate: extrasAnimate)));
      }
      if (widget.isLatest && meta.clarify != null && send != null) {
        extras.add(_Clarify(clarify: meta.clarify!, onSend: send));
      }
      final actions = meta.actions.where(isSupportedChatAction).toList();
      if (actions.isNotEmpty) extras.add(_Actions(actions: actions, meta: meta));
      if (widget.isLatest && meta.suggestions.isNotEmpty && send != null) {
        extras.add(
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [for (final s in meta.suggestions) AiSuggestionChip(label: s, onTap: () => send(s))],
          ),
        );
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: AiAvatar(size: 30)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: RevealMarkdown(text: entry.content, animate: _animate, onDone: _onRevealed),
                ),
              ),
              for (var i = 0; i < extras.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: SlideFadeIn(enabled: extrasAnimate, delay: Duration(milliseconds: 90 * i), child: extras[i]),
                ),
              if (_revealed && showReasoning && meta != null && meta.hasReasoning)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: SlideFadeIn(enabled: extrasAnimate, child: ReasoningPanel(meta: meta)),
                ),
              if (_revealed) _Footer(entry: entry),
            ],
          ),
        ),
      ],
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.entry});

  final ChatEntry entry;

  Future<void> _rate(BuildContext context, WidgetRef ref, int rating) async {
    HapticFeedback.selectionClick();
    try {
      await ref.read(chatControllerProvider.notifier).rate(entry.key, rating);
      if (context.mounted) AppSnack.success(context, 'Thanks for the feedback');
    } on ApiException catch (e) {
      if (context.mounted) AppSnack.error(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final rated = entry.feedback;
    final canRate = entry.id != null;
    Widget btn(IconData icon, String tip, VoidCallback? onTap, {bool active = false, Color? activeColor}) => IconButton(
      tooltip: tip,
      onPressed: onTap,
      isSelected: active,
      icon: Icon(icon, size: 17, color: active ? activeColor : colors.muted),
      style: IconButton.styleFrom(minimumSize: const Size(40, 40), padding: EdgeInsets.zero),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          btn(Icons.copy_rounded, 'Copy reply', () {
            Clipboard.setData(ClipboardData(text: entry.content));
            AppSnack.info(context, 'Copied to clipboard');
          }),
          if (canRate) ...[
            btn(
              rated == 1 ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
              'Good response',
              rated == 1 ? null : () => _rate(context, ref, 1),
              active: rated == 1,
              activeColor: colors.primary,
            ),
            btn(
              rated == -1 ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
              'Bad response',
              rated == -1 ? null : () => _rate(context, ref, -1),
              active: rated == -1,
              activeColor: colors.error,
            ),
          ],
        ],
      ),
    );
  }
}

class _Clarify extends StatelessWidget {
  const _Clarify({required this.clarify, required this.onSend});

  final ChatClarify clarify;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (clarify.question.isNotEmpty) ...[
          Text(clarify.question, style: context.textTheme.labelLarge),
          AppSpacing.gapXs,
        ],
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final o in clarify.options)
              AiSuggestionChip(label: o, filled: true, icon: Icons.touch_app_outlined, onTap: () => onSend(o)),
          ],
        ),
      ],
    );
  }
}

class _Actions extends ConsumerWidget {
  const _Actions({required this.actions, required this.meta});

  final List<ChatAction> actions;
  final ChatMeta meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final a in actions)
          OutlinedButton.icon(
            onPressed: () => runChatAction(context, ref, a, meta: meta),
            icon: Icon(chatActionIcon(a.type), size: 18, color: colors.secondary),
            label: Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: colors.text,
              side: BorderSide(color: colors.secondary.withValues(alpha: 0.4)),
              backgroundColor: colors.secondarySoft.withValues(alpha: 0.5),
              shape: const StadiumBorder(),
            ),
          ),
      ],
    );
  }
}

class _ComparisonCard extends ConsumerWidget {
  const _ComparisonCard({required this.result});

  final CompareResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AiCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AiHeader(title: 'Side-by-side', caption: 'Best value in each row is highlighted'),
          AppSpacing.gapSm,
          CompareTable(
            result: result,
            maxRows: 6,
            onOpen: (p) => openAiProduct(context, ref, p.id),
          ),
          if (result.summary.isNotEmpty) ...[
            AppSpacing.gapSm,
            Text(result.summary, style: context.textTheme.bodySmall!.copyWith(color: context.colors.text)),
          ],
          AppSpacing.gapSm,
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton.secondary(
              label: 'Open full comparison',
              size: AppButtonSize.small,
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: () => context.push(Routes.compareOf([for (final p in result.products) p.id])),
            ),
          ),
        ],
      ),
    );
  }
}
