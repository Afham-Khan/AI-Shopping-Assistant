import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../providers/storefront_provider.dart';

/// Shared layout for auth screens (mobile everywhere): a top row with a
/// circular back button (or the logo) and a circular settings button, then
/// a bold title, a muted subtitle and the form on the page wash. The footer
/// carries a live "store online" line (and a shortcut to the server address
/// when it isn't), so a connection problem is visible before anyone types a
/// password.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.footer,
    this.onBack,
    this.showLogo = true,
    this.eyebrow,
    this.step,
    this.steps,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Below the form (e.g. "New here? Create account").
  final Widget? footer;

  /// Shows a back button when set.
  final VoidCallback? onBack;
  final bool showLogo;

  /// Small uppercase label above the title.
  final String? eyebrow;

  /// Progress through a multi-step flow (1-based), drawn as rounded segments.
  final int? step;
  final int? steps;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, 0),
              child: Row(
                children: [
                  if (onBack != null)
                    CircleIconButton(icon: Icons.arrow_back_ios_new_rounded, iconSize: 17, tooltip: 'Back', onPressed: onBack)
                  else if (showLogo)
                    const Padding(padding: EdgeInsets.only(left: AppSpacing.xs), child: AppLogo(size: 30)),
                  const Spacer(),
                  CircleIconButton(
                    icon: Icons.tune_rounded,
                    iconSize: 19,
                    tooltip: 'Settings',
                    onPressed: () => context.push(Routes.settings),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.lg, context.pagePadding, AppSpacing.xl),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: Breakpoints.maxForm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (step != null && steps != null) ...[
                          _StepBar(step: step!, steps: steps!),
                          AppSpacing.gapLg,
                        ],
                        if (eyebrow != null) ...[
                          Align(alignment: Alignment.centerLeft, child: Eyebrow(eyebrow!)),
                          AppSpacing.gapXs,
                        ],
                        Semantics(
                          header: true,
                          child: Text(title, style: t.displaySmall!.copyWith(fontSize: 28)),
                        ),
                        if (subtitle != null) ...[
                          AppSpacing.gapXs,
                          Text(subtitle!, style: t.bodyLarge!.copyWith(color: colors.muted, fontSize: 15)),
                        ],
                        AppSpacing.gapXl,
                        child,
                        if (footer != null) ...[AppSpacing.gapMd, footer!],
                        AppSpacing.gapLg,
                        const Center(child: StoreStatusLine()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rounded segmented progress for multi-step flows ("Step 2 of 3").
class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.steps});

  final int step;
  final int steps;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Semantics(
      label: 'Step $step of $steps',
      child: Row(
        children: [
          for (var i = 1; i <= steps; i++) ...[
            if (i > 1) const SizedBox(width: 6),
            Expanded(
              child: AnimatedContainer(
                duration: context.motion(AppDurations.normal),
                curve: AppCurves.standard,
                height: 5,
                decoration: BoxDecoration(
                  color: i <= step ? colors.primary : colors.surfaceRaised,
                  borderRadius: AppRadii.pillAll,
                ),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Step $step of $steps',
            style: AppType.data(context, color: colors.muted, size: 12, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Live server reachability: "Store online · 38 ms". When the store can't be
/// reached it turns amber and links to the server address in Settings.
class StoreStatusLine extends ConsumerWidget {
  const StoreStatusLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final health = ref.watch(storeHealthProvider);
    final value = health.value;

    if (value == null) {
      return StatusLine('Checking the store', color: colors.faint, pulse: false, textColor: colors.faint);
    }
    if (value.status == StoreStatus.online) {
      return Tooltip(
        message: 'The Zelora API answered in ${value.ms} ms',
        child: StatusLine('Store online · ${value.ms} ms', color: colors.success, textColor: colors.faint),
      );
    }
    return InkWell(
      onTap: () => context.push(Routes.settings),
      borderRadius: AppRadii.pillAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: StatusLine("Can't reach the store · check server address", color: colors.warning, textColor: colors.warning),
      ),
    );
  }
}

/// "── or ──" divider between auth options.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key, this.label = 'or'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final line = Expanded(child: Divider(color: colors.borderStrong.withValues(alpha: 0.7)));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            line,
            ConstrainedBox(
              // the label never pushes the lines off a narrow screen
              constraints: BoxConstraints(maxWidth: box.maxWidth * 0.7),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.bodySmall!.copyWith(color: colors.muted, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            line,
          ],
        ),
      ),
    );
  }
}

/// "Question? Action" line used under auth forms.
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({super.key, required this.question, required this.action, required this.onTap});

  final String question;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: context.textTheme.bodyMedium!.copyWith(color: colors.muted)),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: colors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            textStyle: context.textTheme.labelLarge!.copyWith(fontWeight: FontWeight.w700),
          ),
          child: Text(action),
        ),
      ],
    );
  }
}
