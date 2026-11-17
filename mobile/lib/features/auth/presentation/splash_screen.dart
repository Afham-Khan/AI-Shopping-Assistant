import 'package:material_ui/material_ui.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/extensions.dart';
import '../../../core/widgets/app_logo.dart';

/// Shown while the session is restored; the router leaves it automatically.
/// The mark settles in once, with the tagline in the ledger voice beneath.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      body: Center(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: context.motion(AppDurations.slow),
          curve: AppCurves.standard,
          builder: (context, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(offset: Offset(0, 6 * (1 - value)), child: child),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 44),
              AppSpacing.gapMd,
              Text('AI SHOPPING ASSISTANT', style: AppType.eyebrow(context, color: colors.faint)),
            ],
          ),
        ),
      ),
    );
  }
}
