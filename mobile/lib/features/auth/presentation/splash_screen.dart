import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/app_logo.dart';

/// Shown while the session is restored; the router leaves it automatically.
///
/// The Z-bag mark pops in once (scale with a gentle overshoot), then the
/// wordmark and tagline rise in beneath it. Under reduced motion everything
/// simply appears.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: context.motion(const Duration(milliseconds: 900)),
          builder: (context, v, _) {
            // mark: 0 → 0.55 of the timeline, easeOutBack
            final mark = Curves.easeOutBack.transform((v / 0.55).clamp(0.0, 1.0));
            final markFade = Curves.easeOut.transform((v / 0.3).clamp(0.0, 1.0));
            // words: 0.35 → 1
            final words = Curves.easeOutCubic.transform(((v - 0.35) / 0.65).clamp(0.0, 1.0));
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: markFade,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * mark,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Radius.circular(26)),
                        boxShadow: colors.shadowMd,
                      ),
                      child: const AppLogo(size: 84, showWordmark: false),
                    ),
                  ),
                ),
                AppSpacing.gapLg,
                Opacity(
                  opacity: words,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - words)),
                    child: Column(
                      children: [
                        ZeloraWordmark(size: 32, color: colors.text),
                        AppSpacing.gapXs,
                        Text('Your AI shopping assistant', style: t.bodyMedium!.copyWith(color: colors.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
