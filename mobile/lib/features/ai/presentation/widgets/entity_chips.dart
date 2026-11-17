import 'package:material_ui/material_ui.dart';

import '../../../../core/models/json_utils.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/formatters.dart';

/// One extracted entity, ready to show as a chip.
@immutable
class EntityChipData {
  const EntityChipData(this.type, this.label, {this.slug});

  final String type;
  final String label;

  /// Raw value for category/department chips (drives the department accent).
  final String? slug;

  /// Per-type accent so chips read at a glance (budget amber, brand blue…).
  Color accent(AppPalette colors) => switch (type) {
    'budget' || 'price' => colors.warning,
    'brand' => colors.secondary,
    'category' || 'department' => AppColors.departmentAccent(slug),
    'feature' => colors.ai,
    'rating' => colors.star,
    'exclude' => colors.error,
    'occasion' || 'recipient' => colors.sale,
    _ => colors.primary,
  };

  IconData get icon => switch (type) {
    'department' => Icons.storefront_outlined,
    'category' => Icons.category_outlined,
    'brand' => Icons.sell_outlined,
    'budget' || 'price' => Icons.payments_outlined,
    'color' => Icons.palette_outlined,
    'gender' => Icons.person_outline_rounded,
    'feature' => Icons.bolt_rounded,
    'rating' => Icons.star_outline_rounded,
    'sort' => Icons.sort_rounded,
    'occasion' => Icons.celebration_outlined,
    'recipient' => Icons.card_giftcard_rounded,
    'exclude' => Icons.block_rounded,
    _ => Icons.search_rounded,
  };

  @override
  bool operator ==(Object other) => other is EntityChipData && other.type == type && other.label == label;

  @override
  int get hashCode => Object.hash(type, label);
}

/// Turns the NLU `entities` map (any shape, nulls allowed) into chips.
/// Unknown keys still show up, so new backend entities are visible.
List<EntityChipData> entityChips(Map<String, dynamic> entities) {
  final out = <EntityChipData>[];
  void add(String type, Object? value, [String Function(String)? fmt]) {
    final s = JsonX.asStringOrNull(value)?.trim();
    if (s == null || s.isEmpty) return;
    final chip = EntityChipData(type, fmt == null ? s : fmt(s), slug: s.toLowerCase().replaceAll(' ', '-'));
    if (!out.contains(chip)) out.add(chip);
  }

  String title(String s) => s.titleCase;

  for (final MapEntry(:key, :value) in entities.entries) {
    if (value == null || value == false) continue;
    switch (key) {
      case 'department':
        add('department', value, title);
      case 'category' || 'categories':
        for (final v in value is List ? value : [value]) {
          add('category', v is Map ? v['name'] ?? v['slug'] : v, title);
        }
      case 'brands' || 'brand':
        for (final v in value is List ? value : [value]) {
          add('brand', v, title);
        }
      case 'excludeBrands' || 'excludeColors':
        for (final v in value is List ? value : [value]) {
          add('exclude', v, (s) => 'No ${s.titleCase}');
        }
      case 'budget' || 'price':
        final label = budgetLabel(value);
        if (label != null) add('budget', label);
      case 'features':
        for (final v in value is List ? value : [value]) {
          add('feature', v, title);
        }
      case 'keywords':
        for (final v in value is List ? value : [value]) {
          add('keyword', v, (s) => '"$s"');
        }
      case 'minRating':
        add('rating', value, (s) => '${Formatters.rating(JsonX.asDouble(s))}★ & up');
      case 'sort':
        add('sort', value, (s) => s.replaceAll('_asc', ' ↑').replaceAll('_desc', ' ↓').titleCase);
      case 'gender' || 'color' || 'occasion' || 'recipient':
        add(key, value, title);
      case 'ordinals':
        break;
      default:
        if (value is List) {
          for (final v in value) {
            if (v is! Map) add(key, v, (s) => '${key.titleCase}: $s');
          }
        } else if (value is! Map) {
          add(key, value, (s) => '${key.titleCase}: $s');
        }
    }
  }
  return out;
}

/// `{min: null, max: 30000}` → `Under Rs 30K`.
String? budgetLabel(Object? value) {
  final m = JsonX.asMap(value);
  final min = JsonX.asDoubleOrNull(m['min']);
  final max = JsonX.asDoubleOrNull(m['max']);
  final hasMin = min != null && min > 0;
  final hasMax = max != null && max > 0;
  if (hasMin && hasMax) return '${Formatters.priceCompact(min)} – ${Formatters.priceCompact(max)}';
  if (hasMax) return 'Under ${Formatters.priceCompact(max)}';
  if (hasMin) return 'Over ${Formatters.priceCompact(min)}';
  return null;
}

/// Wrap of entity chips. Pass [onRemove] to make them removable.
class EntityChipWrap extends StatelessWidget {
  const EntityChipWrap({super.key, required this.chips, this.onRemove, this.dense = false});

  final List<EntityChipData> chips;
  final ValueChanged<EntityChipData>? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [for (final c in chips) EntityChip(chip: c, dense: dense, onRemove: onRemove == null ? null : () => onRemove!(c))],
    );
  }
}

class EntityChip extends StatelessWidget {
  const EntityChip({super.key, required this.chip, this.onRemove, this.dense = false});

  final EntityChipData chip;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = chip.accent(colors);
    final style = (dense ? context.textTheme.labelSmall : context.textTheme.labelMedium)!.copyWith(
      color: colors.text,
      fontWeight: FontWeight.w600,
    );
    final body = Container(
      padding: EdgeInsets.fromLTRB(dense ? 8 : 10, dense ? 4 : 6, onRemove == null ? (dense ? 8 : 10) : 4, dense ? 4 : 6),
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: context.isDark ? 0.2 : 0.1), colors.surface),
        borderRadius: AppRadii.pillAll,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: dense ? 12 : 14, color: accent),
          const SizedBox(width: 4),
          Flexible(child: Text(chip.label, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (onRemove != null)
            Semantics(
              button: true,
              label: 'Remove ${chip.label}',
              child: InkResponse(
                onTap: onRemove,
                radius: 18,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.close_rounded, size: 16, color: colors.muted),
                ),
              ),
            ),
        ],
      ),
    );
    if (onRemove == null) return body;
    // keep a 44 px hit area without inflating the visual chip
    return ConstrainedBox(constraints: const BoxConstraints(minHeight: 44), child: Center(widthFactor: 1, child: body));
  }
}
