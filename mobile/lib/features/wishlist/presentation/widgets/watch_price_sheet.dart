import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/providers/require_auth.dart';
import '../../data/price_watch_models.dart';
import '../../providers/price_watch_providers.dart';

/// What the sheet reports back to its caller (so the toast uses a live context).
class WatchSheetResult {
  const WatchSheetResult({required this.removed, this.message});

  final bool removed;
  final String? message;
}

/// Opens the "Watch price" sheet for [product]: pick a target (any drop, 5%,
/// 10% or a custom amount) and whether to be told when it's back in stock.
/// Guests are sent to sign in first. Returns true when a watch was saved or
/// removed.
Future<bool> showWatchPriceSheet(BuildContext context, WidgetRef ref, {required ProductSummary product}) async {
  if (!requireAuth(context, ref, message: 'Sign in to watch prices')) return false;
  final result = await showAppBottomSheet<WatchSheetResult>(
    context,
    builder: (_) => WatchPriceSheet(product: product),
  );
  if (result == null) return false;
  if (context.mounted) {
    final fallback = result.removed ? 'Stopped watching' : 'Watching this price';
    AppSnack.success(context, result.message ?? fallback);
  }
  return true;
}

class WatchPriceSheet extends ConsumerStatefulWidget {
  const WatchPriceSheet({super.key, required this.product});

  final ProductSummary product;

  @override
  ConsumerState<WatchPriceSheet> createState() => _WatchPriceSheetState();
}

class _WatchPriceSheetState extends ConsumerState<WatchPriceSheet> {
  late final PriceWatch? _existing = ref.read(priceWatchForProvider(widget.product.id));
  late WatchTargetKind _kind = WatchTarget.kindFor(_existing?.targetPrice, widget.product.price);
  late bool _restock = _existing?.notifyRestock ?? true;
  late final _custom = TextEditingController(
    text: _kind == WatchTargetKind.custom && _existing?.targetPrice != null ? _existing!.targetPrice!.round().toString() : '',
  );

  bool _busy = false;
  ApiException? _error;
  String? _customError;

  double get _price => widget.product.price;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// The target the current selection would send (null = any drop / invalid custom).
  double? get _target {
    if (_kind != WatchTargetKind.custom) return WatchTarget.forKind(_kind, _price);
    final parsed = WatchTarget.parse(_custom.text);
    return parsed != null && WatchTarget.validateCustom(_custom.text, _price) == null ? parsed : null;
  }

  void _pick(WatchTargetKind kind) {
    HapticFeedback.selectionClick();
    setState(() {
      _kind = kind;
      _error = null;
      _customError = null;
    });
  }

  Future<void> _save() async {
    double? target;
    if (_kind == WatchTargetKind.custom) {
      final problem = WatchTarget.validateCustom(_custom.text, _price);
      if (problem != null) {
        setState(() => _customError = problem);
        return;
      }
      target = WatchTarget.parse(_custom.text);
    } else {
      target = WatchTarget.forKind(_kind, _price);
    }
    setState(() {
      _busy = true;
      _error = null;
      _customError = null;
    });
    try {
      final message = await ref
          .read(priceWatchesProvider.notifier)
          .save(widget.product, targetPrice: target, notifyRestock: _restock);
      if (mounted) Navigator.of(context).pop(WatchSheetResult(removed: false, message: message));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.fieldError('targetPrice') != null ? null : e;
        _customError = e.fieldError('targetPrice');
        if (_customError != null) _kind = WatchTargetKind.custom;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    String? message;
    final removed = await ConfirmDialog.show(
      context,
      title: 'Stop watching this price?',
      message: "You won't get alerts for ${widget.product.title} any more.",
      confirmLabel: 'Stop watching',
      icon: Icons.notifications_off_outlined,
      onConfirm: () async => message = await ref.read(priceWatchesProvider.notifier).remove(widget.product.id),
    );
    if (removed && mounted) Navigator.of(context).pop(WatchSheetResult(removed: true, message: message));
  }

  String _preview() {
    final target = _target;
    return switch (_kind) {
      WatchTargetKind.anyDrop => "We'll tell you the moment the price drops.",
      WatchTargetKind.custom =>
        target == null
            ? 'Type the price you would be happy to pay.'
            : "We'll tell you at ${Formatters.price(target)} or lower"
                  '${WatchTarget.percentBelow(target, _price) == null ? '' : ' (${WatchTarget.percentBelow(target, _price)})'}.',
      _ => "We'll tell you at ${Formatters.price(target)} or lower.",
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final p = widget.product;
    final editing = _existing != null;

    return BottomSheetScaffold(
      title: editing ? 'Price alert' : 'Watch price',
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppButton(
            label: editing ? 'Save changes' : 'Start watching',
            icon: Icons.notifications_active_outlined,
            expand: true,
            loading: _busy,
            onPressed: _save,
          ),
          if (editing) ...[
            const SizedBox(height: AppSpacing.xxs),
            AppButton.ghost(label: 'Stop watching', expand: true, onPressed: _busy ? null : _stop),
          ],
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppNetworkImage(
                p.thumbnail,
                width: 56,
                height: 56,
                fit: BoxFit.contain,
                borderRadius: AppRadii.inputAll,
                semanticLabel: p.title,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('Now ${Formatters.price(p.price)}', style: t.bodySmall!.copyWith(color: colors.muted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Semantics(header: true, child: Text('Tell me when it reaches', style: t.titleSmall)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _KindChip(label: 'Any drop', selected: _kind == WatchTargetKind.anyDrop, onTap: () => _pick(WatchTargetKind.anyDrop)),
              _KindChip(label: '5% lower', selected: _kind == WatchTargetKind.percent5, onTap: () => _pick(WatchTargetKind.percent5)),
              _KindChip(label: '10% lower', selected: _kind == WatchTargetKind.percent10, onTap: () => _pick(WatchTargetKind.percent10)),
              _KindChip(label: 'Custom', selected: _kind == WatchTargetKind.custom, onTap: () => _pick(WatchTargetKind.custom)),
            ],
          ),
          AnimatedSize(
            duration: context.motion(AppDurations.normal),
            alignment: Alignment.topCenter,
            child: _kind == WatchTargetKind.custom
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: AppTextField(
                      controller: _custom,
                      label: 'Target price (Rs)',
                      hint: 'e.g. ${(_price * 0.85).floor()}',
                      prefixIcon: Icons.sell_outlined,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,]'))],
                      errorText: _customError,
                      onChanged: (_) => setState(() => _customError = null),
                      onSubmitted: (_) => _save(),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(_preview(), style: t.bodySmall!.copyWith(color: colors.muted, height: 1.4)),
          ),
          const SizedBox(height: AppSpacing.md),
          _RestockRow(
            value: _restock,
            outOfStock: !p.inStock,
            onChanged: (v) => setState(() => _restock = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          FormErrorBanner(message: _error?.message, padding: const EdgeInsets.only(top: AppSpacing.xs)),
        ],
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

class _RestockRow extends StatelessWidget {
  const _RestockRow({required this.value, required this.outOfStock, required this.onChanged});

  final bool value;
  final bool outOfStock;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.xs),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: AppRadii.inputAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined, size: 20, color: colors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tell me when it is back in stock', style: t.titleSmall),
                Text(
                  outOfStock ? 'It is out of stock right now.' : 'If it sells out and returns.',
                  style: t.bodySmall!.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
