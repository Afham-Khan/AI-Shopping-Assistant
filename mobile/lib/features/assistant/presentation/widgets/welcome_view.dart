import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/router/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/extensions.dart';
import '../../../ai/presentation/widgets/ai_ui.dart';
import '../../../auth/providers/auth_controller.dart';

/// Empty-chat hero: AI identity, capability cards and example prompts.
class WelcomeView extends ConsumerWidget {
  const WelcomeView({super.key, required this.onPrompt});

  final ValueChanged<String> onPrompt;

  static const examples = [
    'sasta mobile chahiye 30k tak',
    'Gaming laptop under 300k with RTX graphics',
    'Gift for my dad under 10k',
    'Best rated noise cancelling headphones',
    'Running shoes for women',
    'Compare the top 2 smartwatches',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.textTheme;
    final colors = context.colors;
    final name = ref.watch(currentUserProvider.select((u) => u?.name));
    final first = name?.trim().split(' ').first;

    final caps = <_Capability>[
      _Capability(Icons.search_rounded, 'Find anything', 'Describe it like you would to a friend', colors.primary,
          prompt: 'Gaming laptop under 300k with RTX graphics'),
      _Capability(Icons.compare_arrows_rounded, 'Compare', 'Specs side by side with a verdict', colors.secondary,
          prompt: 'Compare the top 2 smartphones under 100k'),
      _Capability(Icons.inventory_2_outlined, 'Build a bundle', 'A full set within your budget', colors.warning,
          route: Routes.bundleBuilder),
      _Capability(Icons.photo_camera_outlined, 'Snap & Find', 'Search with a photo', AppColors.departmentAccent('fashion'),
          route: Routes.visualSearch),
      _Capability(Icons.card_giftcard_rounded, 'Gift finder', 'Ideas for someone you love', colors.sale,
          route: Routes.giftFinder),
      _Capability(Icons.notifications_active_outlined, 'Price alerts', 'Hear when a price drops', colors.success,
          route: Routes.priceAlerts),
      _Capability(Icons.quiz_outlined, 'Guided finder', 'Answer a few questions', colors.ai, route: Routes.finder),
      _Capability(Icons.fingerprint_rounded, 'Shopping DNA', 'See what the AI learned about you',
          AppColors.departmentAccent('beauty-personal-care'), route: Routes.shoppingDna),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(context.pagePadding, AppSpacing.lg, context.pagePadding, AppSpacing.xl),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                const AiAvatar(size: 56),
                AppSpacing.gapSm,
                Semantics(
                  header: true,
                  child: AiText(
                    first == null ? "Hi, I'm ${AppConfig.assistantName}" : 'Hi $first, I\'m ${AppConfig.assistantName}',
                    textAlign: TextAlign.center,
                    style: t.headlineSmall!.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                AppSpacing.gapXs,
                Text(
                  'Your personal shopping assistant. Ask in English or Roman Urdu: '
                  'I search, compare, explain every pick and fit it to your budget.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium!.copyWith(color: colors.muted, height: 1.5),
                ),
                AppSpacing.gapXl,
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = c.maxWidth >= 640 ? 3 : 2;
                    final w = (c.maxWidth - AppSpacing.sm * (cols - 1)) / cols;
                    return Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (var i = 0; i < caps.length; i++)
                          SizedBox(
                            width: w,
                            child: SlideFadeIn(
                              delay: Duration(milliseconds: 60 * i),
                              child: _CapabilityCard(
                                cap: caps[i],
                                onTap: () {
                                  final c = caps[i];
                                  if (c.route != null) {
                                    context.push(c.route!);
                                  } else if (c.prompt != null) {
                                    onPrompt(c.prompt!);
                                  }
                                },
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                AppSpacing.gapXl,
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Try asking', style: t.labelLarge!.copyWith(color: colors.muted)),
                ),
                AppSpacing.gapXs,
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final e in examples)
                        AiSuggestionChip(
                          label: e,
                          icon: e.startsWith('sasta') ? Icons.translate_rounded : Icons.north_east_rounded,
                          onTap: () => onPrompt(e),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Capability {
  const _Capability(this.icon, this.title, this.subtitle, this.color, {this.prompt, this.route});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String? prompt;
  final String? route;
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.cap, required this.onTap});

  final _Capability cap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.textTheme;
    return Semantics(
      button: true,
      label: '${cap.title}. ${cap.subtitle}',
      excludeSemantics: true,
      child: Material(
        color: Color.alphaBlend(cap.color.withValues(alpha: context.isDark ? 0.14 : 0.07), colors.surface),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardAll,
          side: BorderSide(color: cap.color.withValues(alpha: 0.25)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadii.cardAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: cap.color.withValues(alpha: 0.16), borderRadius: AppRadii.inputAll),
                  child: Icon(cap.icon, size: 20, color: cap.color),
                ),
                AppSpacing.gapXs,
                Text(cap.title, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(cap.subtitle, style: t.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
