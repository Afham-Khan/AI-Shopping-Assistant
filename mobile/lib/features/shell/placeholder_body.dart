import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/extensions.dart';

/// Temporary body for screens another engineer will build.
/// Delete the usage when the real screen lands.
class PlaceholderBody extends StatelessWidget {
  const PlaceholderBody({super.key, required this.title, this.params = const {}, this.children = const []});

  final String title;

  /// Route params, shown so routing can be verified.
  final Map<String, Object?> params;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    final shown = params.entries.where((e) => e.value != null).toList();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_rounded, size: 32, color: colors.muted),
              AppSpacing.gapMd,
              Text(title, style: t.titleLarge, textAlign: TextAlign.center),
              AppSpacing.gapXs,
              Text('Coming soon', style: t.bodyMedium!.copyWith(color: colors.muted)),
              if (shown.isNotEmpty) ...[
                AppSpacing.gapMd,
                for (final e in shown)
                  Text('${e.key}: ${e.value}', style: t.bodySmall, textAlign: TextAlign.center),
              ],
              if (children.isNotEmpty) ...[AppSpacing.gapXl, ...children],
            ],
          ),
        ),
      ),
    );
  }
}
