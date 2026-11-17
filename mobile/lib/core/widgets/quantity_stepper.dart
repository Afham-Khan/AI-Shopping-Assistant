import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../utils/extensions.dart';

/// Compact − value + control.
///
/// ```dart
/// QuantityStepper(value: item.quantity, max: 10, loading: busy,
///   onChanged: (q) => ref.read(cartProvider.notifier).setQuantity(id, q))
/// ```
/// When [min] is 0 the minus button becomes a delete icon at 1.
class QuantityStepper extends StatelessWidget {
  const QuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 10,
    this.loading = false,
    this.compact = false,
  });

  final int value;

  /// Null disables the control.
  final ValueChanged<int>? onChanged;
  final int min;
  final int max;

  /// Shows a spinner in place of the number (keeps width).
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final enabled = onChanged != null && !loading;
    final height = compact ? 36.0 : 44.0;
    final removes = min == 0 && value <= 1;

    Widget button({required IconData icon, required String label, required VoidCallback? onTap}) {
      return Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: height / 2,
          child: SizedBox(
            width: height,
            height: height,
            child: Icon(icon, size: compact ? 16 : 18, color: onTap == null ? colors.muted.withValues(alpha: 0.5) : colors.text),
          ),
        ),
      );
    }

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.inputAll,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            icon: removes ? Icons.delete_outline_rounded : Icons.remove_rounded,
            label: removes ? 'Remove' : 'Decrease quantity',
            onTap: enabled && value > min ? () => onChanged!(value - 1) : null,
          ),
          SizedBox(
            width: compact ? 24 : 32,
            child: Center(
              child: loading
                  ? const SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(
                      '$value',
                      semanticsLabel: 'Quantity $value',
                      style: context.textTheme.titleSmall!.copyWith(fontFeatures: AppType.tabular),
                    ),
            ),
          ),
          button(
            icon: Icons.add_rounded,
            label: 'Increase quantity',
            onTap: enabled && value < max ? () => onChanged!(value + 1) : null,
          ),
        ],
      ),
    );
  }
}
