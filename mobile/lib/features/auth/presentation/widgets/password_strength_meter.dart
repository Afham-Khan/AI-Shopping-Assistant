import 'package:material_ui/material_ui.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/utils/validators.dart';

/// Four-segment strength bar with a short hint, under a new-password field.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final strength = Validators.strength(password);
    final color = switch (strength) {
      PasswordStrength.empty => colors.surfaceRaised,
      PasswordStrength.weak => colors.error,
      PasswordStrength.fair => colors.warning,
      PasswordStrength.good || PasswordStrength.strong => colors.success,
    };
    final hint = switch (strength) {
      PasswordStrength.empty => 'At least 8 characters with a letter and a number.',
      PasswordStrength.weak => Validators.password(password) ?? 'Too weak',
      PasswordStrength.fair => 'Fair — longer or mixed case is stronger.',
      PasswordStrength.good => 'Good password.',
      PasswordStrength.strong => 'Strong password.',
    };

    return Semantics(
      liveRegion: true,
      label: strength == PasswordStrength.empty ? hint : 'Password strength ${strength.label}. $hint',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              for (var i = 1; i <= 4; i++) ...[
                if (i > 1) const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: AnimatedContainer(
                    duration: context.motion(AppDurations.normal),
                    height: 3,
                    decoration: BoxDecoration(
                      color: i <= strength.level ? color : colors.surfaceRaised,
                      borderRadius: AppRadii.pillAll,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(hint, style: context.textTheme.bodySmall!.copyWith(color: colors.faint)),
        ],
      ),
    );
  }
}
