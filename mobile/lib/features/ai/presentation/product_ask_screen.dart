import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/app_config.dart';
import '../../../core/models/product.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/widgets.dart';
import '../data/ai_repository.dart';
import '../data/models/ai_models.dart';
import '../providers/ai_providers.dart';
import 'widgets/ai_ui.dart';
import 'widgets/simple_markdown.dart';

class _Qa {
  _Qa(this.question);

  final String question;
  ProductAnswer? answer;
  ApiException? error;
  bool get loading => answer == null && error == null;
}

/// "Ask about this product" (POST /ai/products/:id/ask): a mini chat grounded
/// on one product, with evidence (spec / review / description) and confidence.
class ProductAskScreen extends ConsumerStatefulWidget {
  const ProductAskScreen({super.key, required this.productId});

  final int productId;

  static const suggested = [
    'Is it worth the price?',
    'What do buyers like most?',
    'Any common complaints?',
    'What are the key specs?',
    'Does it come with a warranty?',
    'Who is this best for?',
  ];

  @override
  ConsumerState<ProductAskScreen> createState() => _ProductAskScreenState();
}

class _ProductAskScreenState extends ConsumerState<ProductAskScreen> {
  final _items = <_Qa>[];
  final _text = TextEditingController();
  final _scroll = ScrollController();

  bool get _busy => _items.isNotEmpty && _items.last.loading;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String q) async {
    final question = q.trim();
    if (question.isEmpty || _busy) return;
    _text.clear();
    final qa = _Qa(question);
    setState(() => _items.add(qa));
    _toBottom();
    try {
      final a = await ref.read(aiRepositoryProvider).askProduct(widget.productId, question);
      if (mounted) setState(() => qa.answer = a);
    } on ApiException catch (e) {
      if (mounted) setState(() => qa.error = e);
    }
    _toBottom();
  }

  Future<void> _retry(_Qa qa) async {
    setState(() => _items.remove(qa));
    await _ask(qa.question);
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: context.motion(AppDurations.normal), curve: AppCurves.standard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final product = ref.watch(aiProductProvider(widget.productId));
    return Scaffold(
      appBar: AppBar(title: const Text('Ask about this product')),
      body: Column(
        children: [
          Expanded(
            child: ResponsiveCenter(
              maxWidth: 760,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                children: [
                  product.when(
                    data: (p) => _ProductHeader(product: p),
                    loading: () => const SkeletonListTile(),
                    error: (e, _) => AiInlineError(
                      error: e,
                      title: "Couldn't load the product",
                      onRetry: () => ref.invalidate(aiProductProvider(widget.productId)),
                    ),
                  ),
                  AppSpacing.gapLg,
                  if (_items.isEmpty) ...[
                    AiHeader(
                      title: 'Ask ${AppConfig.appName} AI anything about it',
                      caption: 'Answers come from the specs, description and real reviews, with sources.',
                    ),
                    AppSpacing.gapMd,
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [for (final s in ProductAskScreen.suggested) AiSuggestionChip(label: s, onTap: () => _ask(s))],
                    ),
                  ],
                  for (var i = 0; i < _items.length; i++)
                    _QaView(
                      key: ObjectKey(_items[i]),
                      qa: _items[i],
                      isLatest: i == _items.length - 1,
                      onFollowUp: _ask,
                      onRetry: () => _retry(_items[i]),
                    ),
                ],
              ),
            ),
          ),
          _AskBar(controller: _text, busy: _busy, onSend: _ask),
        ],
      ),
    );
  }
}

class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.product});

  final ProductSummary product;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.cardAll, side: BorderSide(color: colors.border)),
      child: InkWell(
        borderRadius: AppRadii.cardAll,
        onTap: () => context.push(Routes.product(product.id)),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              AppNetworkImage(product.thumbnail, width: 56, height: 56, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (product.brand != null) Text(product.brand!, style: context.textTheme.labelSmall!.copyWith(color: colors.muted)),
                    Text(product.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: context.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        PriceText(product.price, size: PriceSize.small, singleLine: true),
                        const SizedBox(width: AppSpacing.sm),
                        if (product.ratingCount > 0) RatingStars(product.rating, count: product.ratingCount, size: 12),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QaView extends StatelessWidget {
  const _QaView({super.key, required this.qa, required this.isLatest, required this.onFollowUp, required this.onRetry});

  final _Qa qa;
  final bool isLatest;
  final ValueChanged<String> onFollowUp;
  final VoidCallback onRetry;

  static IconData sourceIcon(String source) => switch (source) {
    'spec' => Icons.list_alt_rounded,
    'review' => Icons.rate_review_outlined,
    _ => Icons.description_outlined,
  };

  static String confidenceLabel(double c) => c >= 0.75 ? 'High confidence' : (c >= 0.45 ? 'Medium confidence' : 'Low confidence');

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final a = qa.answer;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: colors.primary, borderRadius: AppRadii.cardAll),
              child: Text(qa.question, style: t.bodyMedium!.copyWith(color: colors.onPrimary)),
            ),
          ),
          AppSpacing.gapSm,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AiAvatar(size: 28),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: qa.loading
                    ? const AiThinking(messages: ['Reading specs and reviews…', 'Checking the evidence…'], lines: 2, compact: true)
                    : qa.error != null
                        ? AiInlineError(error: qa.error!, title: "Couldn't answer that", onRetry: onRetry)
                        : SlideFadeIn(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SimpleMarkdown(a!.answer),
                                if (a.confidence > 0) ...[
                                  AppSpacing.gapSm,
                                  Row(
                                    children: [
                                      Text(confidenceLabel(a.confidence), style: t.labelMedium!.copyWith(color: colors.muted)),
                                      const SizedBox(width: AppSpacing.xs),
                                      SizedBox(width: 96, child: AiConfidenceBar(value: a.confidence, semanticLabel: 'Answer confidence')),
                                    ],
                                  ),
                                ],
                                if (a.evidence.isNotEmpty) ...[
                                  AppSpacing.gapSm,
                                  Text('Sources', style: t.labelLarge),
                                  const SizedBox(height: 4),
                                  for (final ev in a.evidence)
                                    Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(AppSpacing.xs),
                                      decoration: BoxDecoration(
                                        color: colors.surfaceVariant.withValues(alpha: 0.6),
                                        borderRadius: AppRadii.inputAll,
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Icon(sourceIcon(ev.source), size: 16, color: colors.secondary),
                                          const SizedBox(width: AppSpacing.xs),
                                          Expanded(
                                            child: Text.rich(
                                              TextSpan(
                                                children: [
                                                  TextSpan(
                                                    text: '${ev.source.capitalized}  ',
                                                    style: t.labelSmall!.copyWith(color: colors.secondary, fontWeight: FontWeight.w700),
                                                  ),
                                                  TextSpan(text: ev.text, style: t.bodySmall!.copyWith(color: colors.text)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                                if (isLatest && a.followUps.isNotEmpty) ...[
                                  AppSpacing.gapSm,
                                  Wrap(
                                    spacing: AppSpacing.xs,
                                    runSpacing: AppSpacing.xs,
                                    children: [for (final f in a.followUps) AiSuggestionChip(label: f, onTap: () => onFollowUp(f))],
                                  ),
                                ],
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AskBar extends StatelessWidget {
  const _AskBar({required this.controller, required this.busy, required this.onSend});

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.background, border: Border(top: BorderSide(color: colors.border))),
      child: SafeArea(
        top: false,
        child: ResponsiveCenter(
          maxWidth: 760,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    maxLength: 300,
                    textInputAction: TextInputAction.send,
                    onSubmitted: onSend,
                    decoration: const InputDecoration(hintText: 'Ask a question about this product…', counterText: ''),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.filled(
                  tooltip: 'Ask',
                  onPressed: busy ? null : () => onSend(controller.text),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
