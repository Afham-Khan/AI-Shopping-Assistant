import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../providers/storefront_provider.dart';

/// Shared layout for auth screens: a form column on phones/tablets, a split
/// view with the storefront panel on desktop. The footer carries a live
/// "store online" line (and a shortcut to the server address when it isn't),
/// so a connection problem is visible before anyone types a password.
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

  /// Progress through a multi-step flow (1-based), drawn as thin segments.
  final int? step;
  final int? steps;

  @override
  Widget build(BuildContext context) {
    final t = context.textTheme;
    final colors = context.colors;
    final desktop = context.isDesktop;

    final form = SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back_rounded), tooltip: 'Back')
                else if (showLogo && !desktop)
                  const Padding(padding: EdgeInsets.only(left: AppSpacing.xs), child: AppLogo(size: 26)),
                const Spacer(),
                IconButton(
                  onPressed: () => context.push(Routes.settings),
                  icon: Icon(Icons.tune_rounded, color: colors.muted, size: 20),
                  tooltip: 'Settings',
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.md, context.pagePadding, AppSpacing.xl),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                        Align(alignment: Alignment.centerLeft, child: Eyebrow(eyebrow!, dot: true)),
                        AppSpacing.gapSm,
                      ],
                      Semantics(
                        header: true,
                        child: Text(title, style: t.displaySmall!.copyWith(fontSize: context.isWide ? 34 : 30)),
                      ),
                      if (subtitle != null) ...[
                        AppSpacing.gapXs,
                        Text(subtitle!, style: t.bodyLarge!.copyWith(color: colors.muted, fontSize: 15)),
                      ],
                      AppSpacing.gapXl,
                      child,
                      if (footer != null) ...[AppSpacing.gapLg, footer!],
                      AppSpacing.gapXl,
                      const Center(child: StoreStatusLine()),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      body: desktop
          ? Row(
              children: [
                const Expanded(flex: 11, child: _BrandPanel()),
                Expanded(flex: 10, child: form),
              ],
            )
          : form,
    );
  }
}

/// Thin segmented progress for multi-step flows ("step 2 of 3").
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
                height: 3,
                decoration: BoxDecoration(
                  color: i <= step ? colors.primary : colors.surfaceRaised,
                  borderRadius: AppRadii.pillAll,
                ),
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${step.toString().padLeft(2, '0')} / ${steps.toString().padLeft(2, '0')}',
            style: AppType.data(context, color: colors.faint, size: 11),
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
      borderRadius: AppRadii.tagAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: StatusLine("Can't reach the store · check server address", color: colors.warning, textColor: colors.warning),
      ),
    );
  }
}

/// Desktop-only left panel: the store itself. Serif headline, real cover
/// photos and live catalog numbers on a quiet dot grid.
class _BrandPanel extends ConsumerWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.colors;
    final t = context.textTheme;
    final glance = ref.watch(storefrontGlanceProvider).value;

    return Container(
      margin: const EdgeInsets.all(AppSpacing.md),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadii.sheetAll,
        border: Border.all(color: colors.border),
      ),
      child: DotGridBackground(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: LayoutBuilder(
            builder: (context, box) {
              final roomy = box.maxHeight > 560;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppLogo(size: 30),
                  const Spacer(),
                  const Eyebrow('AI shopping assistant', dot: true),
                  AppSpacing.gapMd,
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Shop like you have\n'),
                        TextSpan(text: 'a buyer on call.', style: TextStyle(color: colors.primary)),
                      ],
                    ),
                    style: t.displayLarge,
                  ),
                  AppSpacing.gapMd,
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Text(
                      'Tell Zel what you need in plain words. It reads the reviews, weighs the '
                      'trade-offs and shows its reasoning. You make the call.',
                      style: t.bodyLarge!.copyWith(color: colors.muted, height: 1.55),
                    ),
                  ),
                  if (roomy) ...[
                    AppSpacing.gapXxl,
                    _CoverStrip(images: glance?.images ?? const []),
                  ],
                  AppSpacing.gapXxl,
                  Container(height: 1, color: colors.border),
                  AppSpacing.gapLg,
                  Row(
                    children: [
                      Expanded(child: StatBlock.count(count: glance?.products, caption: 'Products', compact: true)),
                      Expanded(child: StatBlock.count(count: glance?.categories, caption: 'Categories', compact: true)),
                      Expanded(child: StatBlock.count(count: glance?.departments, caption: 'Departments', compact: true)),
                      const Expanded(
                        child: StatBlock(value: '0', caption: 'Sponsored picks', compact: true),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A row of real department cover photos in studio wells.
class _CoverStrip extends StatelessWidget {
  const _CoverStrip({required this.images});

  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    const count = 5;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 10.0;
          final size = ((box.maxWidth - gap * (count - 1)) / count).clamp(48.0, 112.0);
          return Row(
            children: [
              for (var i = 0; i < count; i++) ...[
                if (i > 0) const SizedBox(width: gap),
                Container(
                  width: size,
                  height: size,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: colors.imageWell,
                    borderRadius: AppRadii.cardAll,
                    border: Border.all(color: colors.border),
                  ),
                  child: i < images.length
                      ? Padding(
                          padding: EdgeInsets.all(size * 0.1),
                          child: AppNetworkImage(images[i], fit: BoxFit.contain, backgroundColor: Colors.transparent),
                        )
                      : null,
                ),
              ],
            ],
          );
        },
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              label.toUpperCase(),
              style: AppType.eyebrow(context, color: colors.faint).copyWith(fontSize: 10, letterSpacing: 1.1),
            ),
          ),
          const Expanded(child: Divider()),
        ],
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
            textStyle: context.textTheme.labelLarge,
          ),
          child: Text(action),
        ),
      ],
    );
  }
}
