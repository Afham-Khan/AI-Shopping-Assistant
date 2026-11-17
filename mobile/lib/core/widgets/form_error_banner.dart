import 'package:material_ui/material_ui.dart';

import '../theme/app_spacing.dart';
import '../utils/extensions.dart';

/// Inline form-level error (not tied to a field), e.g. "Invalid email or password".
/// Renders nothing when [message] is null, and animates in/out.
///
/// ```dart
/// FormErrorBanner(message: _error?.hasFieldErrors == true ? null : _error?.message)
/// ```
class FormErrorBanner extends StatelessWidget {
  const FormErrorBanner({super.key, required this.message, this.padding = const EdgeInsets.only(bottom: AppSpacing.md)});

  final String? message;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedSize(
      duration: context.motion(AppDurations.normal),
      curve: AppCurves.standard,
      alignment: Alignment.topCenter,
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: padding,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.saleSoft,
                    borderRadius: AppRadii.inputAll,
                    border: Border.all(color: colors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(message!, style: context.textTheme.bodyMedium!.copyWith(color: colors.error, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
