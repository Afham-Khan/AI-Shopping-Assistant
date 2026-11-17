import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';

/// The page background: a very soft lavender-blue wash, lighter at the top
/// (like daylight from above), with one faint highlight behind the header
/// area. No loud gradient — at a glance it reads as a calm flat color.
///
/// Every page route already paints it (the page transition wraps each page
/// in an `AppBackground`), and scaffolds are transparent, so screens get it
/// for free. Use it yourself only for custom routes / overlays / full-bleed
/// panels that sit outside a page:
///
/// ```dart
/// AppBackground(child: myCustomOverlay)
/// ```
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, this.child, this.highlight = true});

  final Widget? child;

  /// The faint top highlight (off for small embedded panels).
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
    return DecoratedBox(
      decoration: BoxDecoration(gradient: p.backgroundWash),
      child: highlight
          ? DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -1.15),
                  radius: 1.1,
                  colors: [p.backgroundTop.withValues(alpha: 0.9), p.backgroundTop.withValues(alpha: 0)],
                ),
              ),
              child: child ?? const SizedBox.expand(),
            )
          : child ?? const SizedBox.expand(),
    );
  }
}
