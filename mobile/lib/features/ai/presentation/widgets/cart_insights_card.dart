import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../cart/providers/cart_provider.dart';
import '../../data/ai_repository.dart';
import '../../data/models/ai_models.dart';
import '../../providers/ai_providers.dart';
import 'ai_product_widgets.dart';
import 'ai_ui.dart';

/// AI insights about the current cart (GET /ai/cart-insights): cheaper swaps
/// with one-tap "Swap", complete-the-set picks and the free-shipping gap.
/// Collapsible; hidden for guests, empty carts and when there's nothing useful.
///
/// Pass [onCartChanged] so the cart screen can reload after a swap
/// (the badge count is synced automatically).
class CartInsightsCard extends ConsumerStatefulWidget {
  const CartInsightsCard({super.key, this.onCartChanged});

  final VoidCallback? onCartChanged;

  @override
  ConsumerState<CartInsightsCard> createState() => _CartInsightsCardState();
}

class _CartInsightsCardState extends ConsumerState<CartInsightsCard> {
  bool _expanded = true;
  int? _swapping;

  Future<void> _swap(SavingSwap s) async {
    setState(() => _swapping = s.productId);
    final repo = ref.read(aiRepositoryProvider);
    try {
      // keep the same quantity the shopper had
      final qty = await repo.cartQuantity(s.productId);
      await repo.addToCart(s.alternative.id, quantity: qty < 1 ? 1 : qty, source: 'cart_insights');
      final count = await repo.removeFromCart(s.productId);
      ref.read(cartCountProvider.notifier).set(count);
      ref.invalidate(cartInsightsProvider);
      widget.onCartChanged?.call();
      if (mounted) AppSnack.success(context, 'Swapped — you save ${Formatters.price(s.save)}');
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _swapping = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cartInsightsProvider);
    final insights = async.value;
    if (insights == null) {
      // loading the first time: a slim thinking strip; errors stay quiet (non-critical)
      if (async.isLoading && !async.hasValue) {
        return const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.md),
          child: AiCard(child: AiThinking(messages: ['Checking your cart for savings…'], lines: 1, compact: true)),
        );
      }
      return const SizedBox.shrink();
    }
    if (!insights.isUseful) return const SizedBox.shrink();

    final t = context.textTheme;
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AiCard(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              button: true,
              expanded: _expanded,
              child: InkWell(
                borderRadius: AppRadii.inputAll,
                onTap: () => setState(() => _expanded = !_expanded),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      Expanded(
                        child: AiHeader(
                          title: '${AppConfig.appName} AI cart check',
                          caption: insights.totalSavings > 0
                              ? 'Save up to ${Formatters.price(insights.totalSavings)}'
                              : (insights.summary.isEmpty ? null : insights.summary),
                        ),
                      ),
                      AnimatedRotation(
                        turns: _expanded ? 0.5 : 0,
                        duration: context.motion(AppDurations.normal),
                        child: Icon(Icons.expand_more_rounded, color: colors.muted),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ),
                ),
              ),
            ),
            AnimatedSize(
              duration: context.motion(AppDurations.normal),
              curve: AppCurves.standard,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (insights.summary.isNotEmpty && insights.totalSavings > 0) ...[
                            AppSpacing.gapXs,
                            Text(insights.summary, style: t.bodySmall!.copyWith(color: colors.text)),
                          ],
                          if (insights.freeShippingGap != null) ...[
                            AppSpacing.gapSm,
                            _FreeShipping(gap: insights.freeShippingGap!),
                          ],
                          for (final s in insights.savings) ...[
                            AppSpacing.gapSm,
                            _SwapRow(swap: s, busy: _swapping == s.productId, onSwap: _swapping == null ? () => _swap(s) : null),
                          ],
                          if (insights.completeTheSet.isNotEmpty) ...[
                            AppSpacing.gapMd,
                            Text('Complete the set', style: t.labelLarge),
                            AppSpacing.gapXs,
                            AiProductRail(
                              products: insights.completeTheSet,
                              source: 'cart_insights',
                              cardWidth: 136,
                              padding: EdgeInsets.zero,
                              showWhy: false,
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwapRow extends StatelessWidget {
  const _SwapRow({required this.swap, required this.busy, this.onSwap});

  final SavingSwap swap;
  final bool busy;
  final VoidCallback? onSwap;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final alt = swap.alternative;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(color: colors.surface, borderRadius: AppRadii.cardAll, border: Border.all(color: colors.border)),
      child: Row(
        children: [
          AppNetworkImage(alt.thumbnail, width: 48, height: 48, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Save ${Formatters.price(swap.save)}',
                  style: t.labelLarge!.copyWith(color: colors.success, fontWeight: FontWeight.w700),
                ),
                Text(alt.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall!.copyWith(color: colors.text)),
                if (swap.reason.isNotEmpty)
                  Text(swap.reason, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          AppButton.secondary(label: 'Swap', size: AppButtonSize.small, loading: busy, onPressed: onSwap),
        ],
      ),
    );
  }
}

class _FreeShipping extends StatelessWidget {
  const _FreeShipping({required this.gap});

  final FreeShippingGap gap;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.local_shipping_outlined, size: 18, color: colors.secondary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Add ${Formatters.price(gap.remaining)} more for free shipping',
                style: t.labelLarge!.copyWith(color: colors.text),
              ),
            ),
          ],
        ),
        if (gap.suggestions.isNotEmpty) ...[
          AppSpacing.gapXs,
          AiProductRail(
            products: gap.suggestions,
            source: 'cart_insights',
            cardWidth: 136,
            padding: EdgeInsets.zero,
            showWhy: false,
          ),
        ],
      ],
    );
  }
}
