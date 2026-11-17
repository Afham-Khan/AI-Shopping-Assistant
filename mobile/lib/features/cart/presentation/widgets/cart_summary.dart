import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/cart.dart';
import '../../providers/cart_controller.dart';

/// "Add Rs 1,200 more for free delivery" with an animated bar.
class FreeShippingProgress extends StatelessWidget {
  const FreeShippingProgress({super.key, required this.summary});

  final CartSummary summary;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final left = summary.remainingForFreeShipping;
    final unlocked = left <= 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: unlocked ? colors.primarySoft : colors.surface,
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: unlocked ? Colors.transparent : colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? Icons.local_shipping_rounded : Icons.local_shipping_outlined,
                size: 20,
                color: unlocked ? colors.primary : colors.text,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text.rich(
                    unlocked
                        ? const TextSpan(text: 'You\'ve unlocked free delivery')
                        : TextSpan(
                            children: [
                              const TextSpan(text: 'Add '),
                              TextSpan(text: Formatters.price(left), style: const TextStyle(fontWeight: FontWeight.w700)),
                              const TextSpan(text: ' more for free delivery'),
                            ],
                          ),
                    style: t.bodyMedium!.copyWith(color: unlocked ? colors.primary : colors.text),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadii.pillAll,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: summary.freeShippingProgress),
              duration: context.motion(AppDurations.slow),
              curve: AppCurves.standard,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 6,
                color: colors.primary,
                backgroundColor: colors.surfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Applied coupon chip, or a code field + "See available coupons".
class CouponCard extends ConsumerStatefulWidget {
  const CouponCard({super.key, required this.summary});

  final CartSummary summary;

  @override
  ConsumerState<CouponCard> createState() => _CouponCardState();
}

class _CouponCardState extends ConsumerState<CouponCard> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _apply([String? code]) async {
    final value = (code ?? _code.text).trim();
    if (value.isEmpty) {
      setState(() => _error = 'Enter a coupon code');
      return;
    }
    context.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final cart = await ref.read(cartProvider.notifier).applyCoupon(value);
      if (!mounted) return;
      _code.clear();
      HapticFeedback.lightImpact();
      AppSnack.success(context, 'Coupon applied — you save ${Formatters.price(cart.summary.discount)}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.fieldError('code') ?? e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(cartProvider.notifier).removeCoupon();
    } on ApiException catch (e) {
      if (mounted) AppSnack.error(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _browse() async {
    final code = await showAppBottomSheet<String>(
      context,
      builder: (_) => _CouponsSheet(subtotal: widget.summary.subtotal),
    );
    if (code != null) await _apply(code);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final coupon = widget.summary.coupon;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: colors.border),
      ),
      child: AnimatedSize(
        duration: context.motion(AppDurations.normal),
        alignment: Alignment.topCenter,
        child: coupon != null
            ? Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.inputAll),
                    child: Icon(Icons.local_offer_rounded, size: 20, color: colors.primary),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${coupon.code} applied', style: t.titleSmall),
                        if (coupon.description != null) Text(coupon.description!, style: t.bodySmall),
                      ],
                    ),
                  ),
                  _busy
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : IconButton(
                          tooltip: 'Remove coupon',
                          onPressed: _remove,
                          icon: Icon(Icons.close_rounded, color: colors.muted),
                        ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Coupon code', style: t.labelLarge),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _code,
                          hint: 'e.g. WELCOME10',
                          prefixIcon: Icons.local_offer_outlined,
                          textCapitalization: TextCapitalization.characters,
                          errorText: _error,
                          onChanged: (_) {
                            if (_error != null) setState(() => _error = null);
                          },
                          onSubmitted: (_) => _apply(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      AppButton.secondary(label: 'Apply', loading: _busy, onPressed: () => _apply()),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _browse,
                      style: TextButton.styleFrom(foregroundColor: colors.secondary, padding: EdgeInsets.zero),
                      child: const Text('See available coupons'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CouponsSheet extends ConsumerWidget {
  const _CouponsSheet({required this.subtotal});

  final double subtotal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(couponsProvider);
    final colors = context.colors;
    final t = context.textTheme;
    return BottomSheetScaffold(
      title: 'Available coupons',
      child: switch (async) {
        AsyncValue(:final value?) when value.isEmpty => const EmptyState(
          compact: true,
          icon: Icons.local_offer_outlined,
          title: 'No coupons right now',
          message: 'Check back soon for new offers.',
        ),
        AsyncValue(:final value?) => Column(
          children: [
            for (final c in value)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    borderRadius: AppRadii.cardAll,
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: colors.primarySoft,
                                borderRadius: AppRadii.inputAll,
                              ),
                              child: Text(c.code, style: t.labelLarge!.copyWith(color: colors.primary, letterSpacing: 0.6)),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(c.description, style: t.bodyMedium),
                            if (c.minOrderAmount > subtotal)
                              Text(
                                'Add ${Formatters.price(c.minOrderAmount - subtotal)} more to use',
                                style: t.bodySmall!.copyWith(color: colors.warning),
                              )
                            else if (c.expiresAt != null)
                              Text('Valid till ${Formatters.date(c.expiresAt)}', style: t.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      AppButton.secondary(
                        label: 'Apply',
                        size: AppButtonSize.small,
                        onPressed: c.minOrderAmount > subtotal ? null : () => Navigator.of(context).pop(c.code),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        AsyncValue(:final error?) => ErrorState(error: error, compact: true, onRetry: () => ref.invalidate(couponsProvider)),
        _ => const SkeletonList(count: 3),
      },
    );
  }
}

/// Subtotal, discount, shipping, total and savings.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.summary, this.title = 'Order summary'});

  final CartSummary summary;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SummaryBox(
      title: title,
      itemCount: summary.itemCount,
      subtotal: summary.subtotal,
      discount: summary.discount,
      couponCode: summary.coupon?.code,
      shippingFee: summary.shippingFee,
      total: summary.total,
      savings: summary.savings,
    );
  }
}

/// Totals box shared by cart, checkout and order detail.
class SummaryBox extends StatelessWidget {
  const SummaryBox({
    super.key,
    required this.title,
    required this.subtotal,
    required this.discount,
    required this.shippingFee,
    required this.total,
    this.itemCount,
    this.couponCode,
    this.savings = 0,
  });

  final String title;
  final int? itemCount;
  final double subtotal;
  final double discount;
  final String? couponCode;
  final double shippingFee;
  final double total;
  final double savings;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    const tabular = [FontFeature.tabularFigures()];

    Widget row(String label, String value, {Color? color, TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style ?? t.bodyMedium!.copyWith(color: colors.muted))),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: (style ?? t.bodyMedium!).copyWith(color: color, fontFeatures: tabular),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.cardAll,
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(header: true, child: Text(title, style: t.titleMedium)),
          const SizedBox(height: AppSpacing.sm),
          row(itemCount == null ? 'Subtotal' : 'Subtotal (${Formatters.plural(itemCount!, 'item')})', Formatters.price(subtotal)),
          if (discount > 0)
            row(
              couponCode == null ? 'Discount' : 'Discount ($couponCode)',
              '− ${Formatters.price(discount)}',
              color: colors.success,
            ),
          row('Delivery', shippingFee <= 0 ? 'Free' : Formatters.price(shippingFee), color: shippingFee <= 0 ? colors.success : null),
          const Padding(padding: EdgeInsets.symmetric(vertical: AppSpacing.xs), child: Divider()),
          row('Total', Formatters.price(total), style: t.titleMedium),
          if (savings > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.inputAll),
                child: Text(
                  'You\'re saving ${Formatters.price(savings)} on this order',
                  style: t.labelLarge!.copyWith(color: colors.primary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
