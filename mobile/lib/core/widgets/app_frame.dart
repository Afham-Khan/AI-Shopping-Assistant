import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_background.dart';
import 'app_logo.dart';
import 'editorial.dart';

/// Zelora is a mobile app on every screen.
///
/// On phones [AppFrame] does nothing. On anything at least
/// [Breakpoints.frameFrom] wide (tablet, desktop, web) it renders the whole
/// app — every route, dialog and sheet — inside a centred phone-width column
/// ([Breakpoints.appColumn]) with rounded corners and a soft shadow, floating
/// over the page wash. Inside the column the [MediaQuery] reports the
/// column's size, so every screen lays out exactly as it does on a phone
/// (`context.isWide` is false, the bottom bar is always shown).
///
/// There is deliberately no top navbar and no side rail around it: the only
/// things outside the column are a small brand lockup and the search
/// shortcut hint, both purely decorative.
///
/// Installed once in `ZeloraApp`'s `MaterialApp.builder`.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.child});

  final Widget child;

  /// True when [size] gets the framed column.
  static bool framed(Size size) => size.width >= Breakpoints.frameFrom;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    if (!framed(size)) return child;

    final colors = Theme.of(context).extension<AppPalette>() ?? AppPalette.light;
    final roomy = size.height >= 560;
    final margin = roomy ? AppSpacing.xl : 0.0;
    final width = math.min(Breakpoints.appColumn, size.width - AppSpacing.xxl);
    final height = math.max(320.0, math.min(size.height - margin * 2, 940.0));
    final radius = roomy ? AppRadii.frameAll : BorderRadius.zero;
    final decorations = size.width >= 1000 && roomy;

    final inner = MediaQuery(
      data: media.copyWith(
        size: Size(width, height),
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      child: child,
    );

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          const Positioned.fill(child: AppBackground()),
          if (decorations) ...[
            Positioned(left: AppSpacing.xxl, bottom: AppSpacing.xl, child: _BrandNote(colors: colors)),
            if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS)
              Positioned(right: AppSpacing.xxl, bottom: AppSpacing.xl, child: _ShortcutNote(colors: colors)),
          ],
          Center(
            child: Container(
              key: const Key('app-frame'),
              width: width,
              height: height,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: colors.shadowLg,
                border: Border.all(color: colors.surface.withValues(alpha: 0.7), width: 1),
              ),
              child: ClipRRect(borderRadius: radius, child: inner),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandNote extends StatelessWidget {
  const _BrandNote({required this.colors});

  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AppLogo(size: 26),
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 18, color: colors.borderStrong),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'AI shopping assistant',
            style: AppType.sans(TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.muted)),
          ),
        ],
      ),
    );
  }
}

class _ShortcutNote extends StatelessWidget {
  const _ShortcutNote({required this.colors});

  final AppPalette colors;

  @override
  Widget build(BuildContext context) {
    final apple = defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.iOS;
    return ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KbdChip(apple ? '⌘' : 'Ctrl'),
          const SizedBox(width: 4),
          const KbdChip('K'),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'to search',
            style: AppType.sans(TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: colors.muted)),
          ),
        ],
      ),
    );
  }
}
