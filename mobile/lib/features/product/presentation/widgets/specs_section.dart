import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';

// ---------------------------------------------------------------------------
// pure helpers (unit-tested)

/// Icon for a specification, by its name: RAM → memory, Storage → sd card,
/// Display → phone / monitor, Battery → battery, Camera → camera, Processor →
/// circuit board, Weight → scale, Fabric → texture, Volume → drop … Unknown
/// names get a neutral "tune" icon, so new catalog data never breaks the UI.
///
/// [value] only matters for Display: a screen of 11 inches or more is shown
/// as a monitor, anything smaller as a phone.
abstract final class SpecIcons {
  // first rule whose keywords appear in the (lower-case) name wins
  static const _rules = <(List<String>, IconData)>[
    (['ram', 'memory'], Icons.memory_rounded),
    (['storage', 'rom', 'hard drive', 'ssd'], Icons.sd_storage_rounded),
    (['processor', 'chip', 'cpu', 'engine'], Icons.developer_board_rounded),
    (['graphics', 'gpu'], Icons.videogame_asset_rounded),
    (['front camera', 'selfie'], Icons.camera_front_rounded),
    (['webcam', 'video'], Icons.videocam_rounded),
    (['camera', 'lens', 'megapixel'], Icons.photo_camera_rounded),
    (['battery life', 'battery'], Icons.battery_full_rounded),
    (['charging', 'power output', 'voltage', 'magsafe'], Icons.bolt_rounded),
    (['power', 'wattage'], Icons.power_rounded),
    (['weight'], Icons.scale_rounded),
    (['volume'], Icons.water_drop_rounded),
    (['water resistance', 'waterproof', 'ip rating'], Icons.umbrella_rounded),
    (['fingerprint', 'security', 'locking'], Icons.fingerprint_rounded),
    (['fabric', 'material', 'upper', 'strap', 'surface', 'plating', 'stitching'], Icons.texture_rounded),
    (['dimension', 'length', 'height', 'width', 'diameter', 'thickness', 'size', 'circumference', 'sheet'], Icons.straighten_rounded),
    (['colour', 'color', 'shade', 'finish', 'pattern', 'print'], Icons.palette_rounded),
    (['network', 'sim', 'connectivity', 'cellular'], Icons.signal_cellular_alt_rounded),
    (['bluetooth', 'wifi', 'wi-fi', 'wireless'], Icons.wifi_rounded),
    (['port', 'connector', 'cable', 'input', 'output'], Icons.usb_rounded),
    (['audio', 'driver', 'speaker', 'noise cancellation', 'microphone'], Icons.headphones_rounded),
    (['warranty', 'safety', 'protection', 'uv'], Icons.verified_user_rounded),
    (['os', 'operating system', 'compatibility'], Icons.settings_suggest_rounded),
    (['movement', 'dial', 'crystal', 'bezel', 'complication', 'case', 'power reserve'], Icons.watch_rounded),
    (['fit', 'sleeve', 'collar', 'neckline', 'cut', 'closure', 'sole', 'heel', 'toe', 'occasion'], Icons.checkroom_rounded),
    (['fuel', 'mileage'], Icons.local_gas_station_rounded),
    (['top speed', 'speed', 'torque', 'transmission', 'drivetrain', 'brakes'], Icons.speed_rounded),
    (['seating', 'seat'], Icons.event_seat_rounded),
    (['skin type', 'formula', 'concentration', 'benefits', 'key ingredients'], Icons.spa_rounded),
    (['fragrance', 'notes', 'longevity'], Icons.local_florist_rounded),
    (['dietary', 'protein', 'servings', 'fat content', 'variety'], Icons.eco_rounded),
    (['flavour', 'flavor', 'roast', 'heat level'], Icons.restaurant_rounded),
    (['shelf life', 'wear time', 'cooking time'], Icons.schedule_rounded),
    (['care', 'dishwasher', 'microwave', 'maintenance', 'drainage'], Icons.cleaning_services_rounded),
    (['capacity', 'compartments', 'includes', 'set includes', 'quantity', 'count'], Icons.inventory_2_rounded),
    (['sport', 'skill level', 'grip', 'club type', 'court'], Icons.sports_rounded),
    (['ideal for', 'best for', 'suitable for', 'use', 'gender', 'life stage'], Icons.recommend_rounded),
    (['origin'], Icons.public_rounded),
    (['brand'], Icons.verified_rounded),
    (['type', 'style', 'design', 'form', 'features', 'functions'], Icons.category_rounded),
  ];

  static final _display = RegExp(r'display|screen|resolution');
  static final _inches = RegExp(r'(\d+(?:\.\d+)?)\s*(?:-|\s)?(?:inch|in\b|")');

  // compiled once: [of] runs for every spec on every build
  static final _compiled = [for (final (words, icon) in _rules) (_wordsPattern(words), icon)];

  static IconData of(String name, {String? value}) {
    final key = name.trim().toLowerCase();
    if (_display.hasMatch(key)) {
      final size = double.tryParse(_inches.firstMatch((value ?? '').toLowerCase())?.group(1) ?? '');
      return size != null && size >= 11 ? Icons.monitor_rounded : Icons.smartphone_rounded;
    }
    for (final (pattern, icon) in _compiled) {
      if (pattern.hasMatch(key)) return icon;
    }
    return Icons.tune_rounded;
  }
}

/// Matches any of [words] at the start of a word, case-insensitively. Short
/// words (≤ 4 letters: "ram", "os", "port") must also end there, bar a plural
/// "s", so "ram" doesn't hit "program" and "os" doesn't hit "cost"; longer
/// ones match as prefixes ("dimension" finds "Dimensions").
RegExp _wordsPattern(List<String> words) {
  final parts = words.map((w) => RegExp.escape(w) + (w.length <= 4 ? r's?(?![a-z])' : '')).join('|');
  return RegExp('(?:^|[^a-z])(?:$parts)', caseSensitive: false);
}

final _keySpecPatterns = [for (final term in keySpecPriority) (term, _wordsPattern([term]))];

/// Spec names worth a tile, most important first (matched as whole words,
/// case-insensitive). The first six that exist on a product become the grid.
const keySpecPriority = <String>[
  'processor',
  'chip',
  'cpu',
  'ram',
  'storage',
  'display',
  'screen',
  'battery',
  'rear camera',
  'camera',
  'front camera',
  'weight',
  'os',
  'network',
  'water resistance',
  'graphics',
  'power',
  'volume',
  'capacity',
  'fabric',
  'material',
  'fit',
  'size',
  'dimensions',
  'case size',
  'movement',
  'engine',
  'fuel',
  'top speed',
  'seating',
  'dietary',
  'shelf life',
  'skin type',
  'longevity',
  'sport',
];

/// The specs to feature as tiles: up to [max] (default 6), in priority order
/// (see [keySpecPriority]), skipping empty values. Returns fewer than 2 when
/// the product has nothing to feature — then the caller shows only the list.
List<MapEntry<String, String>> selectKeySpecs(List<MapEntry<String, String>> specs, {int max = 6}) {
  final picked = <MapEntry<String, String>>[];

  for (final (term, pattern) in _keySpecPatterns) {
    if (picked.length >= max) break;
    // an exact name beats a partial one ("Camera" before "Rear Camera Mode")
    final exact = specs.where((e) => e.key.toLowerCase() == term && !picked.contains(e));
    final loose = specs.where((e) => pattern.hasMatch(e.key) && !picked.contains(e));
    final hit = exact.isNotEmpty ? exact.first : (loose.isNotEmpty ? loose.first : null);
    if (hit != null && hit.value.trim().isNotEmpty) picked.add(hit);
  }
  return picked.length < 2 ? const [] : picked;
}

/// The headline part of a long value for a tile: up to the first ", ", " (",
/// " + " or " / " — "6.4-inch Super AMOLED, 2340 x 1080" → "6.4-inch Super
/// AMOLED". Short values come back unchanged.
String shortSpecValue(String value) {
  final v = value.trim();
  final cut = RegExp(r',\s| \(| \+ | / ').firstMatch(v);
  if (cut == null || cut.start < 3) return v;
  return v.substring(0, cut.start).trim();
}

/// A tile fits about two lines of bold text; longer values would be cut with
/// an ellipsis, so their full text also goes in the list.
const tileValueMaxChars = 26;

/// The specs for the list under the tiles: everything not featured, plus the
/// featured ones whose tile can't show the whole value — shortened to its
/// headline, or too long for two lines — so no detail is lost. Original
/// order is kept.
List<MapEntry<String, String>> specsForList(
  List<MapEntry<String, String>> all,
  List<MapEntry<String, String>> featured,
) => [
  for (final e in all)
    if (!featured.contains(e) || shortSpecValue(e.value) != e.value.trim() || e.value.trim().length > tileValueMaxChars) e,
];

// ---------------------------------------------------------------------------
// widgets

/// The specifications block of the product page, as a spec sheet instead of a
/// plain table:
///
/// 1. a prominent "Explain these specs" card (the assistant puts each one in
///    plain words),
/// 2. the **key specs** as a two-column grid of tiles — icon, bold value,
///    muted label,
/// 3. everything else in a clean label / value list with hairline separators
///    (collapsed to 6 rows, "Show all N specifications").
///
/// One column at 320 px or large text. Tokens only, no effects.
class SpecsSection extends StatefulWidget {
  const SpecsSection({super.key, required this.specs, this.onExplain});

  final List<MapEntry<String, String>> specs;

  /// Opens the spec explainer; without it the explain card is not shown.
  final VoidCallback? onExplain;

  @override
  State<SpecsSection> createState() => _SpecsSectionState();
}

class _SpecsSectionState extends State<SpecsSection> {
  static const _collapsedRows = 6;
  bool _all = false;
  late List<MapEntry<String, String>> _key;
  late List<MapEntry<String, String>> _rest;

  @override
  void initState() {
    super.initState();
    _split();
  }

  @override
  void didUpdateWidget(SpecsSection old) {
    super.didUpdateWidget(old);
    if (old.specs != widget.specs) _split();
  }

  // computed on change, not on every rebuild
  void _split() {
    _key = selectKeySpecs(widget.specs);
    _rest = specsForList(widget.specs, _key);
  }

  @override
  Widget build(BuildContext context) {
    final key = _key;
    final rest = _rest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onExplain != null) _ExplainCard(onTap: widget.onExplain!),
        if (key.isNotEmpty) ...[
          if (widget.onExplain != null) const SizedBox(height: AppSpacing.sm),
          _TileGrid(specs: key),
        ],
        if (rest.isNotEmpty) ...[
          if (key.isNotEmpty || widget.onExplain != null) const SizedBox(height: AppSpacing.sm),
          _SpecList(
            specs: rest,
            all: _all,
            collapsedRows: _collapsedRows,
            title: key.isEmpty ? null : 'All specifications',
            onToggle: () => setState(() => _all = !_all),
          ),
        ],
      ],
    );
  }
}

/// The prominent entry to the spec explainer: a soft AI-tinted card with the
/// mascot, a bold title and a one-line promise.
class _ExplainCard extends StatelessWidget {
  const _ExplainCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return AppCard(
      onTap: onTap,
      color: Color.alphaBlend(colors.aiSoft.withValues(alpha: 0.7), colors.surface),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      semanticLabel: 'Explain these specs',
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle, border: Border.all(color: colors.ai.withValues(alpha: 0.25))),
            child: const AiSparkleIcon(size: 22),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Explain these specs', style: t.titleSmall!.copyWith(fontWeight: FontWeight.w700, color: colors.text)),
                const SizedBox(height: 2),
                Text(
                  '${AppConfig.assistantName} puts every spec in plain words',
                  style: t.bodySmall!.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.ai),
        ],
      ),
    );
  }
}

/// Key specs as tiles, two per row (one per row when narrow or at large text).
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.specs});

  final List<MapEntry<String, String>> specs;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 300 && scale <= 1.5 ? 2 : 1;
        final rows = <Widget>[];
        for (var i = 0; i < specs.length; i += columns) {
          final cells = <Widget>[
            for (var j = i; j < i + columns && j < specs.length; j++)
              Expanded(child: SpecTile(spec: specs[j], horizontal: columns == 1 || specs.length - i < columns)),
          ];
          // a lone last tile spans the full row
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var k = 0; k < cells.length; k++) ...[if (k > 0) const SizedBox(width: AppSpacing.sm), cells[k]],
                ],
              ),
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[if (i > 0) const SizedBox(height: AppSpacing.sm), rows[i]],
          ],
        );
      },
    );
  }
}

/// One key spec: icon well, bold value, muted label.
class SpecTile extends StatelessWidget {
  const SpecTile({super.key, required this.spec, this.horizontal = false});

  final MapEntry<String, String> spec;

  /// Icon beside the text (a full-width tile) instead of above it (the
  /// two-column grid, where the text needs the width).
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final value = shortSpecValue(spec.value);

    final icon = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: colors.primarySoft, borderRadius: AppRadii.inputAll),
      child: Icon(SpecIcons.of(spec.key, value: spec.value), size: 20, color: colors.primary),
    );
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: t.titleSmall!.copyWith(fontWeight: FontWeight.w700, color: colors.text, height: 1.25),
        ),
        const SizedBox(height: 2),
        Text(
          spec.key,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.labelMedium!.copyWith(color: colors.muted, fontWeight: FontWeight.w500),
        ),
      ],
    );

    return Semantics(
      container: true,
      label: '${spec.key}: ${spec.value}',
      excludeSemantics: true,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: horizontal
            ? Row(children: [icon, const SizedBox(width: AppSpacing.sm), Expanded(child: text)])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(alignment: Alignment.centerLeft, child: icon),
                  const SizedBox(height: AppSpacing.xs),
                  text,
                ],
              ),
      ),
    );
  }
}

/// Label / value rows in a white card, hairlines between them.
class _SpecList extends StatelessWidget {
  const _SpecList({
    required this.specs,
    required this.all,
    required this.collapsedRows,
    required this.onToggle,
    this.title,
  });

  final List<MapEntry<String, String>> specs;
  final bool all;
  final int collapsedRows;
  final VoidCallback onToggle;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final rows = all ? specs : specs.take(collapsedRows).toList();
    final canToggle = specs.length > collapsedRows;

    return AppCard(
      padding: EdgeInsets.zero,
      child: AnimatedSize(
        duration: context.motion(AppDurations.normal),
        curve: AppCurves.standard,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xs),
                child: Semantics(
                  header: true,
                  child: Text(title!, style: t.labelLarge!.copyWith(color: colors.text, fontWeight: FontWeight.w700)),
                ),
              ),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0 || title != null)
                Divider(height: 1, thickness: 1, indent: AppSpacing.md, endIndent: AppSpacing.md, color: colors.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: Text(rows[i].key, style: t.bodyMedium!.copyWith(color: colors.muted))),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      flex: 3,
                      child: Text(rows[i].value, style: t.bodyMedium!.copyWith(fontWeight: FontWeight.w600, color: colors.text)),
                    ),
                  ],
                ),
              ),
            ],
            if (canToggle) ...[
              Divider(height: 1, thickness: 1, color: colors.border),
              InkWell(
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          all ? 'Show fewer' : 'Show all ${specs.length} specifications',
                          textAlign: TextAlign.center,
                          style: t.labelLarge!.copyWith(color: colors.primary, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(all ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: colors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Product highlights as check-icon chips (soft blue pills).
///
/// ```dart
/// HighlightChips(items: detail.highlights)
/// ```
class HighlightChips extends StatelessWidget {
  const HighlightChips({super.key, required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final h in items)
          Container(
            padding: const EdgeInsets.fromLTRB(10, 7, 14, 7),
            decoration: BoxDecoration(
              color: colors.primarySoft,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: colors.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(Icons.check_circle_rounded, size: 17, color: colors.primary),
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(h, style: t.bodyMedium!.copyWith(color: colors.text, fontWeight: FontWeight.w500, height: 1.3))),
              ],
            ),
          ),
      ],
    );
  }
}
