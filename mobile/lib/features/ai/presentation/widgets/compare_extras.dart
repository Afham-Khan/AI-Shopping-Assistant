import 'package:material_ui/material_ui.dart';

import '../../../../core/models/product.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/models/ai_models.dart';
import 'ai_ui.dart';

/// Quick ideas under the "What do you need it for?" box.
const kCompareNeeds = ['Gaming', 'Travel', 'Work', 'Camera', 'Battery life', 'A gift'];

/// "What do you need it for?" — a short free-text need that re-ranks the
/// comparison and picks a "Best for you" product.
class CompareNeedField extends StatefulWidget {
  const CompareNeedField({super.key, required this.need, required this.busy, required this.onSubmit, required this.onClear});

  /// The need currently applied (empty = none).
  final String need;
  final bool busy;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  @override
  State<CompareNeedField> createState() => _CompareNeedFieldState();
}

class _CompareNeedFieldState extends State<CompareNeedField> {
  late final _controller = TextEditingController(text: widget.need);

  @override
  void didUpdateWidget(CompareNeedField old) {
    super.didUpdateWidget(old);
    // cleared from outside (e.g. the chip below)
    if (old.need != widget.need && widget.need.isEmpty && _controller.text.isNotEmpty) _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? value]) {
    final text = (value ?? _controller.text).trim();
    // the API wants 2-200 characters
    if (text.length < 2) return;
    context.unfocus();
    _controller.text = text;
    widget.onSubmit(text);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final active = widget.need.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AiSparkleIcon(size: 16),
              const SizedBox(width: AppSpacing.xs),
              Expanded(child: Semantics(header: true, child: Text('What do you need it for?', style: t.titleSmall))),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  textInputAction: TextInputAction.search,
                  maxLength: 80,
                  onSubmitted: _submit,
                  decoration: const InputDecoration(hintText: 'e.g. gaming, travel, a gift for mom', counterText: ''),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppButton(label: 'Ask Zel', size: AppButtonSize.small, loading: widget.busy, onPressed: _submit),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [for (final n in kCompareNeeds) AiSuggestionChip(label: n, onTap: widget.busy ? null : () => _submit(n))],
          ),
          if (active) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, size: 16, color: colors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Picked for "${widget.need}"', style: t.labelMedium!.copyWith(color: colors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                TextButton(onPressed: widget.onClear, style: TextButton.styleFrom(minimumSize: const Size(44, 36)), child: const Text('Clear')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// "Only show differences" switch with how many rows that leaves.
class DifferencesToggle extends StatelessWidget {
  const DifferencesToggle({super.key, required this.value, required this.onChanged, required this.differing, required this.total});

  final bool value;
  final ValueChanged<bool> onChanged;
  final int differing;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Semantics(
      container: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Only show differences', style: t.titleSmall),
                Text(
                  differing == total
                      ? 'Every row is different'
                      : '$differing of $total rows differ. The rest are the same.',
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

/// "Best for you: X" with the server's reason.
class BestForYouCard extends StatelessWidget {
  const BestForYouCard({super.key, required this.product, required this.reason, required this.need, this.onOpen});

  final ProductSummary product;
  final String reason;
  final String need;
  final ValueChanged<ProductSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    return Semantics(
      container: true,
      label: 'Best for you: ${product.title}. $reason',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.primarySoft,
          borderRadius: AppRadii.cardAll,
          border: Border.all(color: colors.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AiSparkleIcon(size: 16),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    need.isEmpty ? 'Best for you' : 'Best for "$need"',
                    style: t.labelLarge!.copyWith(color: colors.primary, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            InkWell(
              onTap: onOpen == null ? null : () => onOpen!(product),
              borderRadius: AppRadii.inputAll,
              child: Row(
                children: [
                  AppNetworkImage(product.thumbnail, width: 52, height: 52, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(product.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(reason, style: t.bodyMedium!.copyWith(height: 1.45)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pros and cons per product (only for products the server had something to say about).
class CompareProsConsSection extends StatelessWidget {
  const CompareProsConsSection({super.key, required this.result, this.bestForYouId, this.onOpen});

  final CompareResult result;
  final int? bestForYouId;
  final ValueChanged<ProductSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final p in result.products)
        if (result.prosCons[p.id] != null) (p, result.prosCons[p.id]!),
    ];
    if (entries.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AiHeader(title: 'Pros and cons', caption: 'What each one does well, and where it falls short'),
        AppSpacing.gapSm,
        for (final (p, pc) in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _ProsConsCard(product: p, prosCons: pc, highlight: p.id == bestForYouId, onOpen: onOpen),
          ),
      ],
    );
  }
}

class _ProsConsCard extends StatelessWidget {
  const _ProsConsCard({required this.product, required this.prosCons, required this.highlight, this.onOpen});

  final ProductSummary product;
  final ProductProsCons prosCons;
  final bool highlight;
  final ValueChanged<ProductSummary>? onOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;

    Widget bullets(IconData icon, Color color, List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 15, color: color)),
                const SizedBox(width: 6),
                Expanded(child: Text(s, style: t.bodyMedium!.copyWith(height: 1.4))),
              ],
            ),
          ),
      ],
    );

    return AppCard(
      selected: highlight,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen == null ? null : () => onOpen!(product),
            borderRadius: AppRadii.inputAll,
            child: Row(
              children: [
                AppNetworkImage(product.thumbnail, width: 40, height: 40, fit: BoxFit.contain, borderRadius: AppRadii.inputAll),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(product.title, style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                if (highlight) const StatusBadge('Best for you', tone: StatusTone.accent),
              ],
            ),
          ),
          if (prosCons.pros.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            bullets(Icons.add_circle_outline_rounded, colors.success, prosCons.pros),
          ],
          if (prosCons.cons.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            bullets(Icons.remove_circle_outline_rounded, colors.warning, prosCons.cons),
          ],
        ],
      ),
    );
  }
}
